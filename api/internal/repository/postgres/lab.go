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
			id, profile_id, lab_name, ordered_by, sample_date, result_date,
			notes, version, previous_id, is_current, created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`

	_, err = tx.Exec(ctx, query,
		lr.ID, lr.ProfileID, lr.LabName, lr.OrderedBy, lr.SampleDate, lr.ResultDate,
		lr.Notes, lr.Version, lr.PreviousID, lr.IsCurrent, lr.CreatedAt, lr.UpdatedAt,
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
				id, lab_result_id, marker, value, value_text, unit,
				reference_low, reference_high, flag
			) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
			v.ID, v.LabResultID, v.Marker, v.Value, v.ValueText, v.Unit,
			v.ReferenceLow, v.ReferenceHigh, v.Flag,
		)
		if err != nil {
			return fmt.Errorf("insert lab_value: %w", err)
		}
	}

	return tx.Commit(ctx)
}

func (r *LabRepo) GetByID(ctx context.Context, id uuid.UUID) (*labs.LabResult, error) {
	query := `
		SELECT id, profile_id, lab_name, ordered_by, sample_date, result_date,
			notes, version, previous_id, is_current, created_at, updated_at, deleted_at
		FROM lab_results WHERE id = $1 AND deleted_at IS NULL`

	var lr labs.LabResult
	err := r.db.QueryRow(ctx, query, id).Scan(
		&lr.ID, &lr.ProfileID, &lr.LabName, &lr.OrderedBy, &lr.SampleDate, &lr.ResultDate,
		&lr.Notes, &lr.Version, &lr.PreviousID, &lr.IsCurrent, &lr.CreatedAt, &lr.UpdatedAt, &lr.DeletedAt,
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
		SELECT id, profile_id, lab_name, ordered_by, sample_date, result_date,
			notes, version, previous_id, is_current, created_at, updated_at, deleted_at
		FROM lab_results
		WHERE profile_id = $1 AND is_current = TRUE AND deleted_at IS NULL
		ORDER BY sample_date DESC
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
			&lr.ID, &lr.ProfileID, &lr.LabName, &lr.OrderedBy, &lr.SampleDate, &lr.ResultDate,
			&lr.Notes, &lr.Version, &lr.PreviousID, &lr.IsCurrent, &lr.CreatedAt, &lr.UpdatedAt, &lr.DeletedAt,
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
			id, profile_id, lab_name, ordered_by, sample_date, result_date,
			notes, version, previous_id, is_current, created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`

	_, err = tx.Exec(ctx, query,
		lr.ID, lr.ProfileID, lr.LabName, lr.OrderedBy, lr.SampleDate, lr.ResultDate,
		lr.Notes, lr.Version, lr.PreviousID, lr.IsCurrent, lr.CreatedAt, lr.UpdatedAt,
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
				id, lab_result_id, marker, value, value_text, unit,
				reference_low, reference_high, flag
			) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
			v.ID, v.LabResultID, v.Marker, v.Value, v.ValueText, v.Unit,
			v.ReferenceLow, v.ReferenceHigh, v.Flag,
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

// CheckDuplicate looks for a lab result with the same profile, lab_name,
// and sample_date within +/-2 minutes.
func (r *LabRepo) CheckDuplicate(ctx context.Context, lr *labs.LabResult) (*uuid.UUID, error) {
	query := `
		SELECT id FROM lab_results
		WHERE profile_id = $1
		  AND deleted_at IS NULL
		  AND is_current = TRUE
		  AND sample_date BETWEEN $2 - INTERVAL '2 minutes' AND $2 + INTERVAL '2 minutes'
		  AND (($3::text IS NULL AND lab_name IS NULL) OR lab_name = $3)
		LIMIT 1`

	var existingID uuid.UUID
	err := r.db.QueryRow(ctx, query, lr.ProfileID, lr.SampleDate, lr.LabName).Scan(&existingID)
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
		SELECT id, lab_result_id, marker, value, value_text, unit,
			reference_low, reference_high, flag
		FROM lab_values WHERE lab_result_id = $1
		ORDER BY marker ASC`

	rows, err := r.db.Query(ctx, query, labResultID)
	if err != nil {
		return nil, fmt.Errorf("query lab_values: %w", err)
	}
	defer rows.Close()

	var values []labs.LabValue
	for rows.Next() {
		var v labs.LabValue
		if err := rows.Scan(
			&v.ID, &v.LabResultID, &v.Marker, &v.Value, &v.ValueText, &v.Unit,
			&v.ReferenceLow, &v.ReferenceHigh, &v.Flag,
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
	query := `
		SELECT lv.marker, lv.value, lv.unit, lv.reference_low, lv.reference_high, lv.flag, lr.sample_date
		FROM lab_values lv
		JOIN lab_results lr ON lv.lab_result_id = lr.id
		WHERE lr.profile_id = $1
		  AND lr.is_current = TRUE
		  AND lr.deleted_at IS NULL
		  AND lv.value IS NOT NULL`

	args := []interface{}{profileID}
	argIdx := 2

	if from != nil {
		query += fmt.Sprintf(" AND lr.sample_date >= $%d", argIdx)
		args = append(args, *from)
		argIdx++
	}
	if to != nil {
		query += fmt.Sprintf(" AND lr.sample_date <= $%d", argIdx)
		args = append(args, *to)
		argIdx++
	}

	query += " ORDER BY lv.marker ASC, lr.sample_date ASC LIMIT 10000"

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("query lab trends: %w", err)
	}
	defer rows.Close()

	// Group rows by marker
	trendsMap := make(map[string]*labs.MarkerTrend)
	var order []string

	for rows.Next() {
		var (
			marker     string
			value      float64
			unit       *string
			refLow     *float64
			refHigh    *float64
			flag       *string
			sampleDate time.Time
		)
		if err := rows.Scan(&marker, &value, &unit, &refLow, &refHigh, &flag, &sampleDate); err != nil {
			return nil, fmt.Errorf("scan lab trend row: %w", err)
		}

		mt, exists := trendsMap[marker]
		if !exists {
			mt = &labs.MarkerTrend{Marker: marker}
			trendsMap[marker] = mt
			order = append(order, marker)
		}

		mt.DataPoints = append(mt.DataPoints, labs.TrendDataPoint{
			Date:  sampleDate,
			Value: value,
			Flag:  flag,
		})

		// Always update reference info from the latest row (rows are ordered by sample_date ASC)
		mt.Unit = unit
		mt.ReferenceLow = refLow
		mt.ReferenceHigh = refHigh
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate lab trend rows: %w", err)
	}

	// Build result, filtering out markers with < 2 data points
	var results []labs.MarkerTrend
	for _, marker := range order {
		mt := trendsMap[marker]
		if len(mt.DataPoints) >= 2 {
			results = append(results, *mt)
		}
	}

	return results, nil
}
