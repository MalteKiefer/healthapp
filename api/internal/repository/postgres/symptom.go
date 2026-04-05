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
		INSERT INTO symptom_records (id, profile_id, recorded_at, trigger_factors, notes, linked_vital_id, created_at, updated_at, content_enc)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
		s.ID, s.ProfileID, s.RecordedAt, s.TriggerFactors, s.Notes, s.LinkedVitalID, s.CreatedAt, s.UpdatedAt, s.ContentEnc)
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
			INSERT INTO symptom_entries (id, symptom_record_id, symptom_type, custom_label, intensity, body_region, duration_minutes, content_enc)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
			e.ID, e.SymptomRecordID, e.SymptomType, e.CustomLabel, e.Intensity, e.BodyRegion, e.DurationMinutes, e.ContentEnc)
		if err != nil {
			return fmt.Errorf("insert symptom entry: %w", err)
		}
	}

	return tx.Commit(ctx)
}

func (r *SymptomRepo) GetByID(ctx context.Context, id uuid.UUID) (*symptoms.SymptomRecord, error) {
	var s symptoms.SymptomRecord
	err := r.db.QueryRow(ctx, `
		SELECT id, profile_id, recorded_at, trigger_factors, notes, linked_vital_id, created_at, updated_at, deleted_at, content_enc
		FROM symptom_records WHERE id = $1 AND deleted_at IS NULL`, id).Scan(
		&s.ID, &s.ProfileID, &s.RecordedAt, &s.TriggerFactors, &s.Notes, &s.LinkedVitalID, &s.CreatedAt, &s.UpdatedAt, &s.DeletedAt, &s.ContentEnc)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan symptom record: %w", err)
	}

	// Load entries
	rows, err := r.db.Query(ctx, `
		SELECT id, symptom_record_id, symptom_type, custom_label, intensity, body_region, duration_minutes, content_enc
		FROM symptom_entries WHERE symptom_record_id = $1`, id)
	if err != nil {
		return nil, fmt.Errorf("query entries: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var e symptoms.SymptomEntry
		if err := rows.Scan(&e.ID, &e.SymptomRecordID, &e.SymptomType, &e.CustomLabel, &e.Intensity, &e.BodyRegion, &e.DurationMinutes, &e.ContentEnc); err != nil {
			return nil, fmt.Errorf("scan symptom entry row: %w", err)
		}
		s.Entries = append(s.Entries, e)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}

	return &s, nil
}

func (r *SymptomRepo) List(ctx context.Context, profileID uuid.UUID, limit, offset int) ([]symptoms.SymptomRecord, int, error) {
	var total int
	err := r.db.QueryRow(ctx, "SELECT COUNT(*) FROM symptom_records WHERE profile_id = $1 AND deleted_at IS NULL", profileID).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("count symptom records: %w", err)
	}

	rows, err := r.db.Query(ctx, `
		SELECT id, profile_id, recorded_at, trigger_factors, notes, linked_vital_id, created_at, updated_at, deleted_at, content_enc
		FROM symptom_records WHERE profile_id = $1 AND deleted_at IS NULL
		ORDER BY recorded_at DESC LIMIT $2 OFFSET $3`, profileID, limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("query symptom records: %w", err)
	}
	defer rows.Close()

	var result []symptoms.SymptomRecord
	for rows.Next() {
		var s symptoms.SymptomRecord
		if err := rows.Scan(&s.ID, &s.ProfileID, &s.RecordedAt, &s.TriggerFactors, &s.Notes, &s.LinkedVitalID, &s.CreatedAt, &s.UpdatedAt, &s.DeletedAt, &s.ContentEnc); err != nil {
			return nil, 0, fmt.Errorf("scan symptom record row: %w", err)
		}
		result = append(result, s)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate rows: %w", err)
	}

	return result, total, nil
}

func (r *SymptomRepo) Update(ctx context.Context, s *symptoms.SymptomRecord) error {
	s.UpdatedAt = time.Now().UTC()
	_, err := r.db.Exec(ctx, `
		UPDATE symptom_records SET recorded_at=$2, trigger_factors=$3, notes=$4, linked_vital_id=$5, updated_at=$6, content_enc=$7
		WHERE id=$1 AND deleted_at IS NULL`,
		s.ID, s.RecordedAt, s.TriggerFactors, s.Notes, s.LinkedVitalID, s.UpdatedAt, s.ContentEnc)
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

// SetSymptomRecordContentEnc populates content_enc only if currently NULL
// (idempotent lazy-migration path).
func (r *SymptomRepo) SetSymptomRecordContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error {
	_, err := r.db.Exec(ctx,
		"UPDATE symptom_records SET content_enc = $2 WHERE id = $1 AND content_enc IS NULL AND deleted_at IS NULL",
		id, contentEnc,
	)
	if err != nil {
		return fmt.Errorf("set content_enc: %w", err)
	}
	return nil
}

// SetSymptomEntryContentEnc populates content_enc only if currently NULL
// (idempotent lazy-migration path). symptom_entries has no deleted_at column.
func (r *SymptomRepo) SetSymptomEntryContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error {
	_, err := r.db.Exec(ctx,
		"UPDATE symptom_entries SET content_enc = $2 WHERE id = $1 AND content_enc IS NULL",
		id, contentEnc,
	)
	if err != nil {
		return fmt.Errorf("set content_enc: %w", err)
	}
	return nil
}
