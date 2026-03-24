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

func (r *DiaryRepo) Create(ctx context.Context, e *diary.DiaryEvent) error {
	if e.ID == uuid.Nil {
		e.ID = uuid.New()
	}
	now := time.Now().UTC()
	e.CreatedAt = now
	e.UpdatedAt = now
	e.Version = 1
	e.IsCurrent = true

	query := `
		INSERT INTO diary_events (
			id, profile_id, title, event_type, started_at, ended_at,
			description, severity, location, outcome,
			version, previous_id, is_current, created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`

	_, err := r.db.Exec(ctx, query,
		e.ID, e.ProfileID, e.Title, e.EventType, e.StartedAt, e.EndedAt,
		e.Description, e.Severity, e.Location, e.Outcome,
		e.Version, e.PreviousID, e.IsCurrent, e.CreatedAt, e.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert diary event: %w", err)
	}
	return nil
}

func (r *DiaryRepo) GetByID(ctx context.Context, id uuid.UUID) (*diary.DiaryEvent, error) {
	query := `
		SELECT id, profile_id, title, event_type, started_at, ended_at,
			description, severity, location, outcome,
			version, previous_id, is_current, created_at, updated_at, deleted_at
		FROM diary_events WHERE id = $1 AND deleted_at IS NULL`

	return r.scanEvent(r.db.QueryRow(ctx, query, id))
}

func (r *DiaryRepo) List(ctx context.Context, filter diary.ListFilter) ([]diary.DiaryEvent, int, error) {
	countQuery := "SELECT COUNT(*) FROM diary_events WHERE profile_id = $1 AND is_current = TRUE AND deleted_at IS NULL"
	args := []interface{}{filter.ProfileID}
	argIdx := 2

	if filter.EventType != nil {
		countQuery += fmt.Sprintf(" AND event_type = $%d", argIdx)
		args = append(args, *filter.EventType)
		argIdx++
	}
	if filter.From != nil {
		countQuery += fmt.Sprintf(" AND started_at >= $%d", argIdx)
		args = append(args, *filter.From)
		argIdx++
	}
	if filter.To != nil {
		countQuery += fmt.Sprintf(" AND started_at <= $%d", argIdx)
		args = append(args, *filter.To)
		argIdx++
	}

	var total int
	if err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count diary events: %w", err)
	}

	query := `
		SELECT id, profile_id, title, event_type, started_at, ended_at,
			description, severity, location, outcome,
			version, previous_id, is_current, created_at, updated_at, deleted_at
		FROM diary_events WHERE profile_id = $1 AND is_current = TRUE AND deleted_at IS NULL`

	listArgs := []interface{}{filter.ProfileID}
	listIdx := 2

	if filter.EventType != nil {
		query += fmt.Sprintf(" AND event_type = $%d", listIdx)
		listArgs = append(listArgs, *filter.EventType)
		listIdx++
	}
	if filter.From != nil {
		query += fmt.Sprintf(" AND started_at >= $%d", listIdx)
		listArgs = append(listArgs, *filter.From)
		listIdx++
	}
	if filter.To != nil {
		query += fmt.Sprintf(" AND started_at <= $%d", listIdx)
		listArgs = append(listArgs, *filter.To)
		listIdx++
	}

	query += " ORDER BY started_at DESC"

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

	return result, total, nil
}

// Update implements versioned updates: inserts a new row with version+1 and
// marks the old row as no longer current within a transaction.
func (r *DiaryRepo) Update(ctx context.Context, e *diary.DiaryEvent) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Mark old row as not current.
	_, err = tx.Exec(ctx,
		"UPDATE diary_events SET is_current = FALSE, updated_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		e.ID, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("mark old version: %w", err)
	}

	// Insert new versioned row.
	previousID := e.ID
	e.PreviousID = &previousID
	e.ID = uuid.New()
	e.Version++
	e.IsCurrent = true
	now := time.Now().UTC()
	e.CreatedAt = now
	e.UpdatedAt = now

	query := `
		INSERT INTO diary_events (
			id, profile_id, title, event_type, started_at, ended_at,
			description, severity, location, outcome,
			version, previous_id, is_current, created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`

	_, err = tx.Exec(ctx, query,
		e.ID, e.ProfileID, e.Title, e.EventType, e.StartedAt, e.EndedAt,
		e.Description, e.Severity, e.Location, e.Outcome,
		e.Version, e.PreviousID, e.IsCurrent, e.CreatedAt, e.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert new version: %w", err)
	}

	return tx.Commit(ctx)
}

func (r *DiaryRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE diary_events SET deleted_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		id, time.Now().UTC(),
	)
	return err
}

func (r *DiaryRepo) scanEvent(row pgx.Row) (*diary.DiaryEvent, error) {
	var e diary.DiaryEvent
	err := row.Scan(
		&e.ID, &e.ProfileID, &e.Title, &e.EventType, &e.StartedAt, &e.EndedAt,
		&e.Description, &e.Severity, &e.Location, &e.Outcome,
		&e.Version, &e.PreviousID, &e.IsCurrent, &e.CreatedAt, &e.UpdatedAt, &e.DeletedAt,
	)
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
	err := rows.Scan(
		&e.ID, &e.ProfileID, &e.Title, &e.EventType, &e.StartedAt, &e.EndedAt,
		&e.Description, &e.Severity, &e.Location, &e.Outcome,
		&e.Version, &e.PreviousID, &e.IsCurrent, &e.CreatedAt, &e.UpdatedAt, &e.DeletedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("scan diary event row: %w", err)
	}
	return &e, nil
}
