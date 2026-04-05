package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/allergies"
)

type AllergyRepo struct {
	db *pgxpool.Pool
}

func NewAllergyRepo(db *pgxpool.Pool) *AllergyRepo {
	return &AllergyRepo{db: db}
}

func (r *AllergyRepo) Create(ctx context.Context, a *allergies.Allergy) error {
	if a.ID == uuid.Nil {
		a.ID = uuid.New()
	}
	now := time.Now().UTC()
	a.CreatedAt = now
	a.UpdatedAt = now
	a.Version = 1
	a.IsCurrent = true

	query := `
		INSERT INTO allergies (
			id, profile_id, name, category, reaction_type, severity,
			onset_date, diagnosed_by, notes, status,
			version, previous_id, is_current, created_at, updated_at, content_enc
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)`

	_, err := r.db.Exec(ctx, query,
		a.ID, a.ProfileID, a.Name, a.Category, a.ReactionType, a.Severity,
		a.OnsetDate, a.DiagnosedBy, a.Notes, a.Status,
		a.Version, a.PreviousID, a.IsCurrent, a.CreatedAt, a.UpdatedAt, a.ContentEnc,
	)
	if err != nil {
		return fmt.Errorf("insert allergy: %w", err)
	}
	return nil
}

func (r *AllergyRepo) GetByID(ctx context.Context, id uuid.UUID) (*allergies.Allergy, error) {
	query := `
		SELECT id, profile_id, name, category, reaction_type, severity,
			onset_date, diagnosed_by, notes, status,
			version, previous_id, is_current, created_at, updated_at, deleted_at, content_enc
		FROM allergies WHERE id = $1 AND deleted_at IS NULL`

	return r.scanAllergy(r.db.QueryRow(ctx, query, id))
}

func (r *AllergyRepo) List(ctx context.Context, filter allergies.ListFilter) ([]allergies.Allergy, int, error) {
	countQuery := "SELECT COUNT(*) FROM allergies WHERE profile_id = $1 AND deleted_at IS NULL AND is_current = TRUE"
	args := []interface{}{filter.ProfileID}

	var total int
	if err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count allergies: %w", err)
	}

	query := `
		SELECT id, profile_id, name, category, reaction_type, severity,
			onset_date, diagnosed_by, notes, status,
			version, previous_id, is_current, created_at, updated_at, deleted_at, content_enc
		FROM allergies WHERE profile_id = $1 AND deleted_at IS NULL AND is_current = TRUE`

	listArgs := []interface{}{filter.ProfileID}
	listIdx := 2

	query += " ORDER BY created_at DESC"

	if filter.Limit > 0 {
		query += fmt.Sprintf(" LIMIT $%d", listIdx)
		listArgs = append(listArgs, filter.Limit)
		listIdx++
	}
	if filter.Offset > 0 {
		query += fmt.Sprintf(" OFFSET $%d", listIdx)
		listArgs = append(listArgs, filter.Offset)
	}

	rows, err := r.db.Query(ctx, query, listArgs...)
	if err != nil {
		return nil, 0, fmt.Errorf("query allergies: %w", err)
	}
	defer rows.Close()

	var result []allergies.Allergy
	for rows.Next() {
		a, err := r.scanAllergyRow(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, *a)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate rows: %w", err)
	}

	return result, total, nil
}

// Update implements versioned update: inserts a new row with version+1 and marks the old row as not current.
func (r *AllergyRepo) Update(ctx context.Context, a *allergies.Allergy) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Mark old row as not current
	_, err = tx.Exec(ctx,
		"UPDATE allergies SET is_current = FALSE, updated_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		a.ID, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("mark old version: %w", err)
	}

	// Insert new version
	previousID := a.ID
	a.PreviousID = &previousID
	a.ID = uuid.New()
	a.Version++
	a.IsCurrent = true
	now := time.Now().UTC()
	a.CreatedAt = now
	a.UpdatedAt = now

	query := `
		INSERT INTO allergies (
			id, profile_id, name, category, reaction_type, severity,
			onset_date, diagnosed_by, notes, status,
			version, previous_id, is_current, created_at, updated_at, content_enc
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)`

	_, err = tx.Exec(ctx, query,
		a.ID, a.ProfileID, a.Name, a.Category, a.ReactionType, a.Severity,
		a.OnsetDate, a.DiagnosedBy, a.Notes, a.Status,
		a.Version, a.PreviousID, a.IsCurrent, a.CreatedAt, a.UpdatedAt, a.ContentEnc,
	)
	if err != nil {
		return fmt.Errorf("insert new allergy version: %w", err)
	}

	return tx.Commit(ctx)
}

func (r *AllergyRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE allergies SET deleted_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		id, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("soft delete allergy: %w", err)
	}
	return nil
}

func (r *AllergyRepo) scanAllergy(row pgx.Row) (*allergies.Allergy, error) {
	var a allergies.Allergy
	err := row.Scan(
		&a.ID, &a.ProfileID, &a.Name, &a.Category, &a.ReactionType, &a.Severity,
		&a.OnsetDate, &a.DiagnosedBy, &a.Notes, &a.Status,
		&a.Version, &a.PreviousID, &a.IsCurrent, &a.CreatedAt, &a.UpdatedAt, &a.DeletedAt, &a.ContentEnc,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan allergy: %w", err)
	}
	return &a, nil
}

// SetContentEnc populates content_enc only if currently NULL (idempotent
// lazy-migration path — safe to call concurrently from multiple clients).
// Versioned table: no deleted_at filter so historical rows can also migrate.
func (r *AllergyRepo) SetContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error {
	_, err := r.db.Exec(ctx,
		"UPDATE allergies SET content_enc = $2 WHERE id = $1 AND content_enc IS NULL",
		id, contentEnc,
	)
	if err != nil {
		return fmt.Errorf("set content_enc: %w", err)
	}
	return nil
}

func (r *AllergyRepo) scanAllergyRow(rows pgx.Rows) (*allergies.Allergy, error) {
	var a allergies.Allergy
	err := rows.Scan(
		&a.ID, &a.ProfileID, &a.Name, &a.Category, &a.ReactionType, &a.Severity,
		&a.OnsetDate, &a.DiagnosedBy, &a.Notes, &a.Status,
		&a.Version, &a.PreviousID, &a.IsCurrent, &a.CreatedAt, &a.UpdatedAt, &a.DeletedAt, &a.ContentEnc,
	)
	if err != nil {
		return nil, fmt.Errorf("scan allergy row: %w", err)
	}
	return &a, nil
}
