package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/medications"
)

type MedicationRepo struct {
	db *pgxpool.Pool
}

func NewMedicationRepo(db *pgxpool.Pool) *MedicationRepo {
	return &MedicationRepo{db: db}
}

func (r *MedicationRepo) Create(ctx context.Context, m *medications.Medication) error {
	if m.ID == uuid.Nil {
		m.ID = uuid.New()
	}
	now := time.Now().UTC()
	m.CreatedAt = now
	m.UpdatedAt = now
	m.Version = 1
	m.IsCurrent = true

	query := `
		INSERT INTO medications (
			id, profile_id, name, dosage, unit, frequency, route,
			started_at, ended_at, prescribed_by, reason, notes,
			related_diagnosis_id, version, previous_id, is_current,
			created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)`

	_, err := r.db.Exec(ctx, query,
		m.ID, m.ProfileID, m.Name, m.Dosage, m.Unit, m.Frequency, m.Route,
		m.StartedAt, m.EndedAt, m.PrescribedBy, m.Reason, m.Notes,
		m.RelatedDiagnosisID, m.Version, m.PreviousID, m.IsCurrent,
		m.CreatedAt, m.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert medication: %w", err)
	}
	return nil
}

func (r *MedicationRepo) GetByID(ctx context.Context, id uuid.UUID) (*medications.Medication, error) {
	query := `
		SELECT id, profile_id, name, dosage, unit, frequency, route,
			started_at, ended_at, prescribed_by, reason, notes,
			related_diagnosis_id, version, previous_id, is_current,
			created_at, updated_at, deleted_at
		FROM medications WHERE id = $1 AND deleted_at IS NULL`

	return r.scanMedication(r.db.QueryRow(ctx, query, id))
}

func (r *MedicationRepo) List(ctx context.Context, filter medications.ListFilter) ([]medications.Medication, int, error) {
	countQuery := "SELECT COUNT(*) FROM medications WHERE profile_id = $1 AND deleted_at IS NULL AND is_current = TRUE"
	args := []interface{}{filter.ProfileID}

	if filter.ActiveOnly {
		countQuery += " AND ended_at IS NULL"
	}

	var total int
	if err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count medications: %w", err)
	}

	query := `
		SELECT id, profile_id, name, dosage, unit, frequency, route,
			started_at, ended_at, prescribed_by, reason, notes,
			related_diagnosis_id, version, previous_id, is_current,
			created_at, updated_at, deleted_at
		FROM medications WHERE profile_id = $1 AND deleted_at IS NULL AND is_current = TRUE`

	listArgs := []interface{}{filter.ProfileID}
	listIdx := 2

	if filter.ActiveOnly {
		query += " AND ended_at IS NULL"
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
		return nil, 0, fmt.Errorf("query medications: %w", err)
	}
	defer rows.Close()

	var result []medications.Medication
	for rows.Next() {
		m, err := r.scanMedicationRow(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, *m)
	}

	return result, total, nil
}

// Update implements versioned update: inserts a new row with version+1 and marks the old row as not current.
func (r *MedicationRepo) Update(ctx context.Context, m *medications.Medication) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Mark old row as not current
	_, err = tx.Exec(ctx,
		"UPDATE medications SET is_current = FALSE, updated_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		m.ID, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("mark old version: %w", err)
	}

	// Insert new version
	previousID := m.ID
	m.PreviousID = &previousID
	m.ID = uuid.New()
	m.Version++
	m.IsCurrent = true
	now := time.Now().UTC()
	m.CreatedAt = now
	m.UpdatedAt = now

	query := `
		INSERT INTO medications (
			id, profile_id, name, dosage, unit, frequency, route,
			started_at, ended_at, prescribed_by, reason, notes,
			related_diagnosis_id, version, previous_id, is_current,
			created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)`

	_, err = tx.Exec(ctx, query,
		m.ID, m.ProfileID, m.Name, m.Dosage, m.Unit, m.Frequency, m.Route,
		m.StartedAt, m.EndedAt, m.PrescribedBy, m.Reason, m.Notes,
		m.RelatedDiagnosisID, m.Version, m.PreviousID, m.IsCurrent,
		m.CreatedAt, m.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert new medication version: %w", err)
	}

	return tx.Commit(ctx)
}

func (r *MedicationRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE medications SET deleted_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		id, time.Now().UTC(),
	)
	return err
}

func (r *MedicationRepo) GetActive(ctx context.Context, profileID uuid.UUID) ([]medications.Medication, error) {
	query := `
		SELECT id, profile_id, name, dosage, unit, frequency, route,
			started_at, ended_at, prescribed_by, reason, notes,
			related_diagnosis_id, version, previous_id, is_current,
			created_at, updated_at, deleted_at
		FROM medications
		WHERE profile_id = $1 AND deleted_at IS NULL AND is_current = TRUE AND ended_at IS NULL
		ORDER BY created_at DESC`

	rows, err := r.db.Query(ctx, query, profileID)
	if err != nil {
		return nil, fmt.Errorf("query active medications: %w", err)
	}
	defer rows.Close()

	var result []medications.Medication
	for rows.Next() {
		m, err := r.scanMedicationRow(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, *m)
	}

	return result, nil
}

func (r *MedicationRepo) CreateIntake(ctx context.Context, intake *medications.MedicationIntake) error {
	if intake.ID == uuid.Nil {
		intake.ID = uuid.New()
	}
	intake.CreatedAt = time.Now().UTC()

	query := `
		INSERT INTO medication_intakes (
			id, medication_id, profile_id, scheduled_at, taken_at,
			dose_taken, skipped_reason, notes, created_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`

	_, err := r.db.Exec(ctx, query,
		intake.ID, intake.MedicationID, intake.ProfileID, intake.ScheduledAt,
		intake.TakenAt, intake.DoseTaken, intake.SkippedReason, intake.Notes,
		intake.CreatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert medication intake: %w", err)
	}
	return nil
}

func (r *MedicationRepo) ListIntake(ctx context.Context, medicationID uuid.UUID, limit, offset int) ([]medications.MedicationIntake, int, error) {
	var total int
	if err := r.db.QueryRow(ctx,
		"SELECT COUNT(*) FROM medication_intakes WHERE medication_id = $1",
		medicationID,
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count intakes: %w", err)
	}

	query := `
		SELECT id, medication_id, profile_id, scheduled_at, taken_at,
			dose_taken, skipped_reason, notes, created_at
		FROM medication_intakes WHERE medication_id = $1
		ORDER BY created_at DESC`

	args := []interface{}{medicationID}
	argIdx := 2

	if limit > 0 {
		query += fmt.Sprintf(" LIMIT $%d", argIdx)
		args = append(args, limit)
		argIdx++
	}
	if offset > 0 {
		query += fmt.Sprintf(" OFFSET $%d", argIdx)
		args = append(args, offset)
	}

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("query intakes: %w", err)
	}
	defer rows.Close()

	var result []medications.MedicationIntake
	for rows.Next() {
		var intake medications.MedicationIntake
		if err := rows.Scan(
			&intake.ID, &intake.MedicationID, &intake.ProfileID,
			&intake.ScheduledAt, &intake.TakenAt, &intake.DoseTaken,
			&intake.SkippedReason, &intake.Notes, &intake.CreatedAt,
		); err != nil {
			return nil, 0, fmt.Errorf("scan intake row: %w", err)
		}
		result = append(result, intake)
	}

	return result, total, nil
}

func (r *MedicationRepo) GetAdherence(ctx context.Context, medicationID uuid.UUID, from, to *time.Time) (*medications.AdherenceSummary, error) {
	query := `
		SELECT
			COUNT(*) AS total_scheduled,
			COUNT(*) FILTER (WHERE taken_at IS NOT NULL) AS total_taken,
			COUNT(*) FILTER (WHERE taken_at IS NULL AND skipped_reason IS NOT NULL) AS total_skipped
		FROM medication_intakes
		WHERE medication_id = $1`

	args := []interface{}{medicationID}
	argIdx := 2

	if from != nil {
		query += fmt.Sprintf(" AND created_at >= $%d", argIdx)
		args = append(args, *from)
		argIdx++
	}
	if to != nil {
		query += fmt.Sprintf(" AND created_at <= $%d", argIdx)
		args = append(args, *to)
	}

	var summary medications.AdherenceSummary
	summary.MedicationID = medicationID

	if err := r.db.QueryRow(ctx, query, args...).Scan(
		&summary.TotalScheduled, &summary.TotalTaken, &summary.TotalSkipped,
	); err != nil {
		return nil, fmt.Errorf("query adherence: %w", err)
	}

	if summary.TotalScheduled > 0 {
		summary.AdherenceRate = float64(summary.TotalTaken) / float64(summary.TotalScheduled) * 100
	}

	return &summary, nil
}

func (r *MedicationRepo) scanMedication(row pgx.Row) (*medications.Medication, error) {
	var m medications.Medication
	err := row.Scan(
		&m.ID, &m.ProfileID, &m.Name, &m.Dosage, &m.Unit, &m.Frequency, &m.Route,
		&m.StartedAt, &m.EndedAt, &m.PrescribedBy, &m.Reason, &m.Notes,
		&m.RelatedDiagnosisID, &m.Version, &m.PreviousID, &m.IsCurrent,
		&m.CreatedAt, &m.UpdatedAt, &m.DeletedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan medication: %w", err)
	}
	return &m, nil
}

func (r *MedicationRepo) scanMedicationRow(rows pgx.Rows) (*medications.Medication, error) {
	var m medications.Medication
	err := rows.Scan(
		&m.ID, &m.ProfileID, &m.Name, &m.Dosage, &m.Unit, &m.Frequency, &m.Route,
		&m.StartedAt, &m.EndedAt, &m.PrescribedBy, &m.Reason, &m.Notes,
		&m.RelatedDiagnosisID, &m.Version, &m.PreviousID, &m.IsCurrent,
		&m.CreatedAt, &m.UpdatedAt, &m.DeletedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("scan medication row: %w", err)
	}
	return &m, nil
}
