package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/symptoms"
)

type SymptomRepo struct{ db *pgxpool.Pool }

func NewSymptomRepo(db *pgxpool.Pool) *SymptomRepo { return &SymptomRepo{db: db} }

func (r *SymptomRepo) Create(ctx context.Context, s *symptoms.SymptomRecord) error {
	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	now := time.Now().UTC()
	s.CreatedAt = now
	s.UpdatedAt = now

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO symptom_records (id, profile_id, recorded_at, trigger_factors, notes, linked_vital_id, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
		s.ID, s.ProfileID, s.RecordedAt, s.TriggerFactors, s.Notes, s.LinkedVitalID, s.CreatedAt, s.UpdatedAt)
	if err != nil {
		return fmt.Errorf("insert symptom record: %w", err)
	}

	for i := range s.Entries {
		e := &s.Entries[i]
		if e.ID == uuid.Nil {
			e.ID = uuid.New()
		}
		e.SymptomRecordID = s.ID
		_, err = tx.Exec(ctx, `
			INSERT INTO symptom_entries (id, symptom_record_id, symptom_type, custom_label, intensity, body_region, duration_minutes)
			VALUES ($1,$2,$3,$4,$5,$6,$7)`,
			e.ID, e.SymptomRecordID, e.SymptomType, e.CustomLabel, e.Intensity, e.BodyRegion, e.DurationMinutes)
		if err != nil {
			return fmt.Errorf("insert symptom entry: %w", err)
		}
	}

	return tx.Commit(ctx)
}

func (r *SymptomRepo) GetByID(ctx context.Context, id uuid.UUID) (*symptoms.SymptomRecord, error) {
	var s symptoms.SymptomRecord
	err := r.db.QueryRow(ctx, `
		SELECT id, profile_id, recorded_at, trigger_factors, notes, linked_vital_id, created_at, updated_at, deleted_at
		FROM symptom_records WHERE id = $1 AND deleted_at IS NULL`, id).Scan(
		&s.ID, &s.ProfileID, &s.RecordedAt, &s.TriggerFactors, &s.Notes, &s.LinkedVitalID, &s.CreatedAt, &s.UpdatedAt, &s.DeletedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan symptom record: %w", err)
	}

	rows, err := r.db.Query(ctx, `
		SELECT id, symptom_record_id, symptom_type, custom_label, intensity, body_region, duration_minutes
		FROM symptom_entries WHERE symptom_record_id = $1`, id)
	if err != nil {
		return nil, fmt.Errorf("query entries: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var e symptoms.SymptomEntry
		if err := rows.Scan(&e.ID, &e.SymptomRecordID, &e.SymptomType, &e.CustomLabel, &e.Intensity, &e.BodyRegion, &e.DurationMinutes); err != nil {
			return nil, fmt.Errorf("scan symptom entry row: %w", err)
		}
		s.Entries = append(s.Entries, e)
	}
	return &s, rows.Err()
}

func (r *SymptomRepo) List(ctx context.Context, profileID uuid.UUID, limit, offset int) ([]symptoms.SymptomRecord, int, error) {
	var total int
	if err := r.db.QueryRow(ctx, "SELECT COUNT(*) FROM symptom_records WHERE profile_id = $1 AND deleted_at IS NULL", profileID).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count symptom records: %w", err)
	}

	rows, err := r.db.Query(ctx, `
		SELECT id, profile_id, recorded_at, trigger_factors, notes, linked_vital_id, created_at, updated_at, deleted_at
		FROM symptom_records WHERE profile_id = $1 AND deleted_at IS NULL
		ORDER BY created_at DESC LIMIT $2 OFFSET $3`, profileID, limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("query symptom records: %w", err)
	}
	defer rows.Close()

	var result []symptoms.SymptomRecord
	for rows.Next() {
		var s symptoms.SymptomRecord
		if err := rows.Scan(&s.ID, &s.ProfileID, &s.RecordedAt, &s.TriggerFactors, &s.Notes, &s.LinkedVitalID, &s.CreatedAt, &s.UpdatedAt, &s.DeletedAt); err != nil {
			return nil, 0, fmt.Errorf("scan symptom record row: %w", err)
		}
		result = append(result, s)
	}
	return result, total, rows.Err()
}

func (r *SymptomRepo) Update(ctx context.Context, s *symptoms.SymptomRecord) error {
	s.UpdatedAt = time.Now().UTC()
	_, err := r.db.Exec(ctx, `
		UPDATE symptom_records SET recorded_at=$2, trigger_factors=$3, notes=$4, linked_vital_id=$5, updated_at=$6
		WHERE id=$1 AND deleted_at IS NULL`,
		s.ID, s.RecordedAt, s.TriggerFactors, s.Notes, s.LinkedVitalID, s.UpdatedAt)
	if err != nil {
		return fmt.Errorf("update symptom record: %w", err)
	}
	return nil
}

func (r *SymptomRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "UPDATE symptom_records SET deleted_at=$2 WHERE id=$1 AND deleted_at IS NULL", id, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("soft delete symptom record: %w", err)
	}
	return nil
}
