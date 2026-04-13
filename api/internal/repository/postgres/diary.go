package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/diary"
)

type DiaryRepo struct {
	db *pgxpool.Pool
}

func NewDiaryRepo(db *pgxpool.Pool) *DiaryRepo {
	return &DiaryRepo{db: db}
}

const diaryColumns = `id, profile_id, title, event_type, started_at, ended_at, description, severity, location, outcome,
	version, previous_id, is_current, created_at, updated_at, deleted_at`

func (r *DiaryRepo) Create(ctx context.Context, e *diary.DiaryEvent) error {
	if e.ID == uuid.Nil {
		e.ID = uuid.New()
	}
	now := time.Now().UTC()
	e.CreatedAt = now
	e.UpdatedAt = now
	e.Version = 1
	e.IsCurrent = true

	_, err := r.db.Exec(ctx, `
		INSERT INTO diary_events (id, profile_id, title, event_type, started_at, ended_at, description, severity, location, outcome,
			version, previous_id, is_current, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`,
		e.ID, e.ProfileID, e.Title, e.EventType, e.StartedAt, e.EndedAt, e.Description, e.Severity, e.Location, e.Outcome,
		e.Version, e.PreviousID, e.IsCurrent, e.CreatedAt, e.UpdatedAt)
	if err != nil {
		return fmt.Errorf("insert diary event: %w", err)
	}
	return nil
}

func (r *DiaryRepo) GetByID(ctx context.Context, id uuid.UUID) (*diary.DiaryEvent, error) {
	return r.scanEvent(r.db.QueryRow(ctx,
		`SELECT `+diaryColumns+` FROM diary_events WHERE id = $1 AND deleted_at IS NULL`, id))
}

func (r *DiaryRepo) List(ctx context.Context, filter diary.ListFilter) ([]diary.DiaryEvent, int, error) {
	countQuery := "SELECT COUNT(*) FROM diary_events WHERE profile_id = $1 AND is_current = TRUE AND deleted_at IS NULL"
	var total int
	if err := r.db.QueryRow(ctx, countQuery, filter.ProfileID).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count diary events: %w", err)
	}

	query := `SELECT ` + diaryColumns + ` FROM diary_events WHERE profile_id = $1 AND is_current = TRUE AND deleted_at IS NULL ORDER BY created_at DESC`
	listArgs := []interface{}{filter.ProfileID}
	listIdx := 2
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
		return nil, 0, fmt.Errorf("query diary events: %w", err)
	}
	defer rows.Close()

	var result []diary.DiaryEvent
	for rows.Next() {
		e, err := r.scanEventRow(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, *e)
	}
	return result, total, rows.Err()
}

func (r *DiaryRepo) Update(ctx context.Context, e *diary.DiaryEvent) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, "UPDATE diary_events SET is_current = FALSE, updated_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		e.ID, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("mark old version: %w", err)
	}

	previousID := e.ID
	e.PreviousID = &previousID
	e.ID = uuid.New()
	e.Version++
	e.IsCurrent = true
	now := time.Now().UTC()
	e.CreatedAt = now
	e.UpdatedAt = now

	_, err = tx.Exec(ctx, `
		INSERT INTO diary_events (id, profile_id, title, event_type, started_at, ended_at, description, severity, location, outcome,
			version, previous_id, is_current, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`,
		e.ID, e.ProfileID, e.Title, e.EventType, e.StartedAt, e.EndedAt, e.Description, e.Severity, e.Location, e.Outcome,
		e.Version, e.PreviousID, e.IsCurrent, e.CreatedAt, e.UpdatedAt)
	if err != nil {
		return fmt.Errorf("insert new version: %w", err)
	}
	return tx.Commit(ctx)
}

func (r *DiaryRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "UPDATE diary_events SET deleted_at = $2 WHERE id = $1 AND deleted_at IS NULL", id, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("soft delete diary event: %w", err)
	}
	return nil
}

func (r *DiaryRepo) scanEvent(row pgx.Row) (*diary.DiaryEvent, error) {
	var e diary.DiaryEvent
	err := row.Scan(&e.ID, &e.ProfileID, &e.Title, &e.EventType, &e.StartedAt, &e.EndedAt, &e.Description, &e.Severity, &e.Location, &e.Outcome,
		&e.Version, &e.PreviousID, &e.IsCurrent, &e.CreatedAt, &e.UpdatedAt, &e.DeletedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan diary event: %w", err)
	}
	return &e, nil
}

func (r *DiaryRepo) scanEventRow(rows pgx.Rows) (*diary.DiaryEvent, error) {
	var e diary.DiaryEvent
	err := rows.Scan(&e.ID, &e.ProfileID, &e.Title, &e.EventType, &e.StartedAt, &e.EndedAt, &e.Description, &e.Severity, &e.Location, &e.Outcome,
		&e.Version, &e.PreviousID, &e.IsCurrent, &e.CreatedAt, &e.UpdatedAt, &e.DeletedAt)
	if err != nil {
		return nil, fmt.Errorf("scan diary event row: %w", err)
	}
	return &e, nil
}
