package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/labs"
)

// LabRepo implements labs.Repository backed by PostgreSQL.
type LabRepo struct {
	db *pgxpool.Pool
}

func NewLabRepo(db *pgxpool.Pool) *LabRepo {
	return &LabRepo{db: db}
}

func (r *LabRepo) Create(ctx context.Context, lr *labs.LabResult) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if lr.ID == uuid.Nil {
		lr.ID = uuid.New()
	}
	now := time.Now().UTC()
	lr.CreatedAt = now
	lr.UpdatedAt = now
	lr.Version = 1
	lr.IsCurrent = true

	query := `
		INSERT INTO lab_results (
			id, profile_id,
			version, previous_id, is_current, created_at, updated_at, content_enc
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`

	_, err = tx.Exec(ctx, query,
		lr.ID, lr.ProfileID,
		lr.Version, lr.PreviousID, lr.IsCurrent, lr.CreatedAt, lr.UpdatedAt, lr.ContentEnc,
	)
	if err != nil {
		return fmt.Errorf("insert lab_result: %w", err)
	}

	for i := range lr.Values {
		v := &lr.Values[i]
		if v.ID == uuid.Nil {
			v.ID = uuid.New()
		}
		v.LabResultID = lr.ID

		_, err = tx.Exec(ctx, `
			INSERT INTO lab_values (
				id, lab_result_id, content_enc
			) VALUES ($1,$2,$3)`,
			v.ID, v.LabResultID, v.ContentEnc,
		)
		if err != nil {
			return fmt.Errorf("insert lab_value: %w", err)
		}
	}

	return tx.Commit(ctx)
}

func (r *LabRepo) GetByID(ctx context.Context, id uuid.UUID) (*labs.LabResult, error) {
	query := `
		SELECT id, profile_id,
			version, previous_id, is_current, created_at, updated_at, deleted_at, content_enc
		FROM lab_results WHERE id = $1 AND deleted_at IS NULL`

	var lr labs.LabResult
	err := r.db.QueryRow(ctx, query, id).Scan(
		&lr.ID, &lr.ProfileID,
		&lr.Version, &lr.PreviousID, &lr.IsCurrent, &lr.CreatedAt, &lr.UpdatedAt, &lr.DeletedAt, &lr.ContentEnc,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan lab_result: %w", err)
	}

	values, err := r.getValues(ctx, lr.ID)
	if err != nil {
		return nil, err
	}
	lr.Values = values

	return &lr, nil
}

func (r *LabRepo) List(ctx context.Context, profileID uuid.UUID, limit, offset int) ([]labs.LabResult, int, error) {
	var total int
	err := r.db.QueryRow(ctx,
		"SELECT COUNT(*) FROM lab_results WHERE profile_id = $1 AND is_current = TRUE AND deleted_at IS NULL",
		profileID,
	).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("count lab_results: %w", err)
	}

	query := `
		SELECT id, profile_id,
			version, previous_id, is_current, created_at, updated_at, deleted_at, content_enc
		FROM lab_results
		WHERE profile_id = $1 AND is_current = TRUE AND deleted_at IS NULL
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3`

	rows, err := r.db.Query(ctx, query, profileID, limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("query lab_results: %w", err)
	}
	defer rows.Close()

	var results []labs.LabResult
	for rows.Next() {
		var lr labs.LabResult
		if err := rows.Scan(
			&lr.ID, &lr.ProfileID,
			&lr.Version, &lr.PreviousID, &lr.IsCurrent, &lr.CreatedAt, &lr.UpdatedAt, &lr.DeletedAt, &lr.ContentEnc,
		); err != nil {
			return nil, 0, fmt.Errorf("scan lab_result row: %w", err)
		}

		values, err := r.getValues(ctx, lr.ID)
		if err != nil {
			return nil, 0, err
		}
		lr.Values = values

		results = append(results, lr)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate rows: %w", err)
	}

	return results, total, nil
}

func (r *LabRepo) Update(ctx context.Context, lr *labs.LabResult) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Mark the old version as no longer current
	_, err = tx.Exec(ctx,
		"UPDATE lab_results SET is_current = FALSE, updated_at = $2 WHERE id = $1",
		lr.ID, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("mark old version: %w", err)
	}

	// Insert the new version
	previousID := lr.ID
	lr.PreviousID = &previousID
	lr.ID = uuid.New()
	lr.Version++
	lr.IsCurrent = true
	now := time.Now().UTC()
	lr.CreatedAt = now
	lr.UpdatedAt = now

	query := `
		INSERT INTO lab_results (
			id, profile_id,
			version, previous_id, is_current, created_at, updated_at, content_enc
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`

	_, err = tx.Exec(ctx, query,
		lr.ID, lr.ProfileID,
		lr.Version, lr.PreviousID, lr.IsCurrent, lr.CreatedAt, lr.UpdatedAt, lr.ContentEnc,
	)
	if err != nil {
		return fmt.Errorf("insert new version: %w", err)
	}

	// Insert values for the new version
	for i := range lr.Values {
		v := &lr.Values[i]
		v.ID = uuid.New()
		v.LabResultID = lr.ID

		_, err = tx.Exec(ctx, `
			INSERT INTO lab_values (
				id, lab_result_id, content_enc
			) VALUES ($1,$2,$3)`,
			v.ID, v.LabResultID, v.ContentEnc,
		)
		if err != nil {
			return fmt.Errorf("insert lab_value: %w", err)
		}
	}

	return tx.Commit(ctx)
}

func (r *LabRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE lab_results SET deleted_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		id, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("soft delete lab result: %w", err)
	}
	return nil
}

// CheckDuplicate looks for a lab result with the same profile created within +/-2 minutes.
func (r *LabRepo) CheckDuplicate(ctx context.Context, lr *labs.LabResult) (*uuid.UUID, error) {
	query := `
		SELECT id FROM lab_results
		WHERE profile_id = $1
		  AND deleted_at IS NULL
		  AND is_current = TRUE
		  AND created_at BETWEEN $2 - INTERVAL '2 minutes' AND $2 + INTERVAL '2 minutes'
		LIMIT 1`

	var existingID uuid.UUID
	err := r.db.QueryRow(ctx, query, lr.ProfileID, lr.CreatedAt).Scan(&existingID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, fmt.Errorf("check duplicate: %w", err)
	}
	return &existingID, nil
}

func (r *LabRepo) getValues(ctx context.Context, labResultID uuid.UUID) ([]labs.LabValue, error) {
	query := `
		SELECT id, lab_result_id, content_enc
		FROM lab_values WHERE lab_result_id = $1`

	rows, err := r.db.Query(ctx, query, labResultID)
	if err != nil {
		return nil, fmt.Errorf("query lab_values: %w", err)
	}
	defer rows.Close()

	var values []labs.LabValue
	for rows.Next() {
		var v labs.LabValue
		if err := rows.Scan(
			&v.ID, &v.LabResultID, &v.ContentEnc,
		); err != nil {
			return nil, fmt.Errorf("scan lab_value: %w", err)
		}
		values = append(values, v)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}

	return values, nil
}

func (r *LabRepo) ListTrends(ctx context.Context, profileID uuid.UUID, from, to *time.Time) ([]labs.MarkerTrend, error) {
	// NOTE: ListTrends previously read plaintext lab_values columns (marker,
	// value, unit, reference_low, reference_high, flag) and lab_results.sample_date.
	// Those columns have been dropped in Stage 2.4. Trend analysis must now be
	// performed client-side after decrypting content_enc. Return empty until
	// the client-side implementation is ready.
	return nil, nil
}

// SetLabResultContentEnc populates content_enc only if currently NULL
// (idempotent lazy-migration path).
func (r *LabRepo) SetLabResultContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error {
	_, err := r.db.Exec(ctx,
		"UPDATE lab_results SET content_enc = $2 WHERE id = $1 AND content_enc IS NULL AND deleted_at IS NULL",
		id, contentEnc,
	)
	if err != nil {
		return fmt.Errorf("set content_enc: %w", err)
	}
	return nil
}

// SetLabValueContentEnc populates content_enc only if currently NULL
// (idempotent lazy-migration path). lab_values has no deleted_at column.
func (r *LabRepo) SetLabValueContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error {
	_, err := r.db.Exec(ctx,
		"UPDATE lab_values SET content_enc = $2 WHERE id = $1 AND content_enc IS NULL",
		id, contentEnc,
	)
	if err != nil {
		return fmt.Errorf("set content_enc: %w", err)
	}
	return nil
}
