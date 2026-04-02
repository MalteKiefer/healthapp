package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/vaccinations"
)

type VaccinationRepo struct {
	db *pgxpool.Pool
}

func NewVaccinationRepo(db *pgxpool.Pool) *VaccinationRepo {
	return &VaccinationRepo{db: db}
}

func (r *VaccinationRepo) Create(ctx context.Context, v *vaccinations.Vaccination) error {
	if v.ID == uuid.Nil {
		v.ID = uuid.New()
	}
	now := time.Now().UTC()
	v.CreatedAt = now
	v.UpdatedAt = now
	v.Version = 1
	v.IsCurrent = true

	query := `
		INSERT INTO vaccinations (
			id, profile_id, vaccine_name, trade_name, manufacturer,
			lot_number, dose_number, administered_at, administered_by,
			next_due_at, site, notes, document_id,
			version, previous_id, is_current,
			created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)`

	_, err := r.db.Exec(ctx, query,
		v.ID, v.ProfileID, v.VaccineName, v.TradeName, v.Manufacturer,
		v.LotNumber, v.DoseNumber, v.AdministeredAt, v.AdministeredBy,
		v.NextDueAt, v.Site, v.Notes, v.DocumentID,
		v.Version, v.PreviousID, v.IsCurrent,
		v.CreatedAt, v.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert vaccination: %w", err)
	}
	return nil
}

func (r *VaccinationRepo) GetByID(ctx context.Context, id uuid.UUID) (*vaccinations.Vaccination, error) {
	query := `
		SELECT id, profile_id, vaccine_name, trade_name, manufacturer,
			lot_number, dose_number, administered_at, administered_by,
			next_due_at, site, notes, document_id,
			version, previous_id, is_current,
			created_at, updated_at, deleted_at
		FROM vaccinations WHERE id = $1 AND deleted_at IS NULL AND is_current = TRUE`

	return r.scanVaccination(r.db.QueryRow(ctx, query, id))
}

func (r *VaccinationRepo) List(ctx context.Context, filter vaccinations.ListFilter) ([]vaccinations.Vaccination, int, error) {
	countQuery := "SELECT COUNT(*) FROM vaccinations WHERE profile_id = $1 AND deleted_at IS NULL AND is_current = TRUE"
	args := []interface{}{filter.ProfileID}

	var total int
	if err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count vaccinations: %w", err)
	}

	query := `
		SELECT id, profile_id, vaccine_name, trade_name, manufacturer,
			lot_number, dose_number, administered_at, administered_by,
			next_due_at, site, notes, document_id,
			version, previous_id, is_current,
			created_at, updated_at, deleted_at
		FROM vaccinations WHERE profile_id = $1 AND deleted_at IS NULL AND is_current = TRUE`

	listArgs := []interface{}{filter.ProfileID}
	listIdx := 2

	query += " ORDER BY administered_at DESC"

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
		return nil, 0, fmt.Errorf("query vaccinations: %w", err)
	}
	defer rows.Close()

	var result []vaccinations.Vaccination
	for rows.Next() {
		v, err := r.scanVaccinationRow(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, *v)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate rows: %w", err)
	}

	return result, total, nil
}

// Update performs a versioned update: inserts a new row with version+1 and marks the old row as not current.
func (r *VaccinationRepo) Update(ctx context.Context, v *vaccinations.Vaccination) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Mark old version as not current
	_, err = tx.Exec(ctx,
		"UPDATE vaccinations SET is_current = FALSE, updated_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		v.ID, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("mark old version: %w", err)
	}

	// Insert new version
	previousID := v.ID
	v.PreviousID = &previousID
	v.ID = uuid.New()
	v.Version++
	v.IsCurrent = true
	now := time.Now().UTC()
	v.CreatedAt = now
	v.UpdatedAt = now

	query := `
		INSERT INTO vaccinations (
			id, profile_id, vaccine_name, trade_name, manufacturer,
			lot_number, dose_number, administered_at, administered_by,
			next_due_at, site, notes, document_id,
			version, previous_id, is_current,
			created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)`

	_, err = tx.Exec(ctx, query,
		v.ID, v.ProfileID, v.VaccineName, v.TradeName, v.Manufacturer,
		v.LotNumber, v.DoseNumber, v.AdministeredAt, v.AdministeredBy,
		v.NextDueAt, v.Site, v.Notes, v.DocumentID,
		v.Version, v.PreviousID, v.IsCurrent,
		v.CreatedAt, v.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert new version: %w", err)
	}

	return tx.Commit(ctx)
}

func (r *VaccinationRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE vaccinations SET deleted_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		id, time.Now().UTC(),
	)
	return err
}

// GetDue returns vaccinations where next_due_at is in the future or within the past 30 days.
func (r *VaccinationRepo) GetDue(ctx context.Context, profileID uuid.UUID) ([]vaccinations.Vaccination, error) {
	query := `
		SELECT id, profile_id, vaccine_name, trade_name, manufacturer,
			lot_number, dose_number, administered_at, administered_by,
			next_due_at, site, notes, document_id,
			version, previous_id, is_current,
			created_at, updated_at, deleted_at
		FROM vaccinations
		WHERE profile_id = $1
		  AND deleted_at IS NULL
		  AND is_current = TRUE
		  AND next_due_at IS NOT NULL
		  AND next_due_at >= NOW() - INTERVAL '30 days'
		ORDER BY next_due_at ASC`

	rows, err := r.db.Query(ctx, query, profileID)
	if err != nil {
		return nil, fmt.Errorf("query due vaccinations: %w", err)
	}
	defer rows.Close()

	var result []vaccinations.Vaccination
	for rows.Next() {
		v, err := r.scanVaccinationRow(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, *v)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}

	return result, nil
}

func (r *VaccinationRepo) scanVaccination(row pgx.Row) (*vaccinations.Vaccination, error) {
	var v vaccinations.Vaccination
	err := row.Scan(
		&v.ID, &v.ProfileID, &v.VaccineName, &v.TradeName, &v.Manufacturer,
		&v.LotNumber, &v.DoseNumber, &v.AdministeredAt, &v.AdministeredBy,
		&v.NextDueAt, &v.Site, &v.Notes, &v.DocumentID,
		&v.Version, &v.PreviousID, &v.IsCurrent,
		&v.CreatedAt, &v.UpdatedAt, &v.DeletedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan vaccination: %w", err)
	}
	return &v, nil
}

func (r *VaccinationRepo) scanVaccinationRow(rows pgx.Rows) (*vaccinations.Vaccination, error) {
	var v vaccinations.Vaccination
	err := rows.Scan(
		&v.ID, &v.ProfileID, &v.VaccineName, &v.TradeName, &v.Manufacturer,
		&v.LotNumber, &v.DoseNumber, &v.AdministeredAt, &v.AdministeredBy,
		&v.NextDueAt, &v.Site, &v.Notes, &v.DocumentID,
		&v.Version, &v.PreviousID, &v.IsCurrent,
		&v.CreatedAt, &v.UpdatedAt, &v.DeletedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("scan vaccination row: %w", err)
	}
	return &v, nil
}
