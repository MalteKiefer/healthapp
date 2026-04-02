package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/diagnoses"
)

type DiagnosisRepo struct {
	db *pgxpool.Pool
}

func NewDiagnosisRepo(db *pgxpool.Pool) *DiagnosisRepo {
	return &DiagnosisRepo{db: db}
}

func (r *DiagnosisRepo) Create(ctx context.Context, d *diagnoses.Diagnosis) error {
	if d.ID == uuid.Nil {
		d.ID = uuid.New()
	}
	now := time.Now().UTC()
	d.CreatedAt = now
	d.UpdatedAt = now
	d.Version = 1
	d.IsCurrent = true

	query := `
		INSERT INTO diagnoses (
			id, profile_id, name, icd10_code, status,
			diagnosed_at, diagnosed_by, resolved_at, notes,
			version, previous_id, is_current,
			created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)`

	_, err := r.db.Exec(ctx, query,
		d.ID, d.ProfileID, d.Name, d.ICD10Code, d.Status,
		d.DiagnosedAt, d.DiagnosedBy, d.ResolvedAt, d.Notes,
		d.Version, d.PreviousID, d.IsCurrent,
		d.CreatedAt, d.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert diagnosis: %w", err)
	}
	return nil
}

func (r *DiagnosisRepo) GetByID(ctx context.Context, id uuid.UUID) (*diagnoses.Diagnosis, error) {
	query := `
		SELECT id, profile_id, name, icd10_code, status,
			diagnosed_at, diagnosed_by, resolved_at, notes,
			version, previous_id, is_current,
			created_at, updated_at, deleted_at
		FROM diagnoses WHERE id = $1 AND deleted_at IS NULL AND is_current = TRUE`

	return r.scanDiagnosis(r.db.QueryRow(ctx, query, id))
}

func (r *DiagnosisRepo) List(ctx context.Context, filter diagnoses.ListFilter) ([]diagnoses.Diagnosis, int, error) {
	countQuery := "SELECT COUNT(*) FROM diagnoses WHERE profile_id = $1 AND deleted_at IS NULL AND is_current = TRUE"
	args := []interface{}{filter.ProfileID}
	argIdx := 2

	if filter.Status != nil {
		countQuery += fmt.Sprintf(" AND status = $%d", argIdx)
		args = append(args, *filter.Status)
		argIdx++
	}

	var total int
	if err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count diagnoses: %w", err)
	}

	query := `
		SELECT id, profile_id, name, icd10_code, status,
			diagnosed_at, diagnosed_by, resolved_at, notes,
			version, previous_id, is_current,
			created_at, updated_at, deleted_at
		FROM diagnoses WHERE profile_id = $1 AND deleted_at IS NULL AND is_current = TRUE`

	listArgs := []interface{}{filter.ProfileID}
	listIdx := 2

	if filter.Status != nil {
		query += fmt.Sprintf(" AND status = $%d", listIdx)
		listArgs = append(listArgs, *filter.Status)
		listIdx++
	}

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
		return nil, 0, fmt.Errorf("query diagnoses: %w", err)
	}
	defer rows.Close()

	var result []diagnoses.Diagnosis
	for rows.Next() {
		d, err := r.scanDiagnosisRow(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, *d)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate rows: %w", err)
	}

	return result, total, nil
}

// Update performs a versioned update: inserts a new row with version+1 and marks the old row as not current.
func (r *DiagnosisRepo) Update(ctx context.Context, d *diagnoses.Diagnosis) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Mark old version as not current
	_, err = tx.Exec(ctx,
		"UPDATE diagnoses SET is_current = FALSE, updated_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		d.ID, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("mark old version: %w", err)
	}

	// Insert new version
	previousID := d.ID
	d.PreviousID = &previousID
	d.ID = uuid.New()
	d.Version++
	d.IsCurrent = true
	now := time.Now().UTC()
	d.CreatedAt = now
	d.UpdatedAt = now

	query := `
		INSERT INTO diagnoses (
			id, profile_id, name, icd10_code, status,
			diagnosed_at, diagnosed_by, resolved_at, notes,
			version, previous_id, is_current,
			created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)`

	_, err = tx.Exec(ctx, query,
		d.ID, d.ProfileID, d.Name, d.ICD10Code, d.Status,
		d.DiagnosedAt, d.DiagnosedBy, d.ResolvedAt, d.Notes,
		d.Version, d.PreviousID, d.IsCurrent,
		d.CreatedAt, d.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert new version: %w", err)
	}

	return tx.Commit(ctx)
}

func (r *DiagnosisRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE diagnoses SET deleted_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		id, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("soft delete diagnosis: %w", err)
	}
	return nil
}

func (r *DiagnosisRepo) scanDiagnosis(row pgx.Row) (*diagnoses.Diagnosis, error) {
	var d diagnoses.Diagnosis
	err := row.Scan(
		&d.ID, &d.ProfileID, &d.Name, &d.ICD10Code, &d.Status,
		&d.DiagnosedAt, &d.DiagnosedBy, &d.ResolvedAt, &d.Notes,
		&d.Version, &d.PreviousID, &d.IsCurrent,
		&d.CreatedAt, &d.UpdatedAt, &d.DeletedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan diagnosis: %w", err)
	}
	return &d, nil
}

func (r *DiagnosisRepo) scanDiagnosisRow(rows pgx.Rows) (*diagnoses.Diagnosis, error) {
	var d diagnoses.Diagnosis
	err := rows.Scan(
		&d.ID, &d.ProfileID, &d.Name, &d.ICD10Code, &d.Status,
		&d.DiagnosedAt, &d.DiagnosedBy, &d.ResolvedAt, &d.Notes,
		&d.Version, &d.PreviousID, &d.IsCurrent,
		&d.CreatedAt, &d.UpdatedAt, &d.DeletedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("scan diagnosis row: %w", err)
	}
	return &d, nil
}
