package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/tasks"
)

type TaskRepo struct{ db *pgxpool.Pool }

func NewTaskRepo(db *pgxpool.Pool) *TaskRepo { return &TaskRepo{db: db} }

func (r *TaskRepo) Create(ctx context.Context, t *tasks.Task) error {
	if t.ID == uuid.Nil {
		t.ID = uuid.New()
	}
	now := time.Now().UTC()
	t.CreatedAt = now
	t.UpdatedAt = now

	_, err := r.db.Exec(ctx, `
		INSERT INTO tasks (id, profile_id, due_date, status, related_diary_event_id, related_appointment_id, created_by_user_id, created_at, updated_at, content_enc)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
		t.ID, t.ProfileID, t.DueDate, t.Status,
		t.RelatedDiaryEventID, t.RelatedAppointmentID, t.CreatedByUserID, t.CreatedAt, t.UpdatedAt, t.ContentEnc)
	if err != nil {
		return fmt.Errorf("create task: %w", err)
	}
	return nil
}

func (r *TaskRepo) GetByID(ctx context.Context, id uuid.UUID) (*tasks.Task, error) {
	var t tasks.Task
	err := r.db.QueryRow(ctx, `
		SELECT id, profile_id, due_date, status, done_at, related_diary_event_id, related_appointment_id, created_by_user_id, created_at, updated_at, content_enc
		FROM tasks WHERE id = $1`, id).Scan(
		&t.ID, &t.ProfileID, &t.DueDate, &t.Status, &t.DoneAt,
		&t.RelatedDiaryEventID, &t.RelatedAppointmentID, &t.CreatedByUserID, &t.CreatedAt, &t.UpdatedAt, &t.ContentEnc)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan task: %w", err)
	}
	return &t, nil
}

func (r *TaskRepo) List(ctx context.Context, profileID uuid.UUID) ([]tasks.Task, error) {
	return r.queryTasks(ctx, `
		SELECT id, profile_id, due_date, status, done_at, related_diary_event_id, related_appointment_id, created_by_user_id, created_at, updated_at, content_enc
		FROM tasks WHERE profile_id = $1 ORDER BY due_date ASC NULLS LAST`, profileID)
}

func (r *TaskRepo) GetOpen(ctx context.Context, profileID uuid.UUID) ([]tasks.Task, error) {
	return r.queryTasks(ctx, `
		SELECT id, profile_id, due_date, status, done_at, related_diary_event_id, related_appointment_id, created_by_user_id, created_at, updated_at, content_enc
		FROM tasks WHERE profile_id = $1 AND status = 'open' ORDER BY due_date ASC NULLS LAST`, profileID)
}

func (r *TaskRepo) Update(ctx context.Context, t *tasks.Task) error {
	t.UpdatedAt = time.Now().UTC()
	if t.Status == "done" && t.DoneAt == nil {
		now := time.Now().UTC()
		t.DoneAt = &now
	}
	_, err := r.db.Exec(ctx, `
		UPDATE tasks SET due_date=$2, status=$3, done_at=$4, updated_at=$5, content_enc=$6
		WHERE id=$1`,
		t.ID, t.DueDate, t.Status, t.DoneAt, t.UpdatedAt, t.ContentEnc)
	if err != nil {
		return fmt.Errorf("update task: %w", err)
	}
	return nil
}

func (r *TaskRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "DELETE FROM tasks WHERE id=$1", id)
	if err != nil {
		return fmt.Errorf("delete task: %w", err)
	}
	return nil
}

// SetContentEnc populates content_enc only if currently NULL (idempotent
// lazy-migration path — safe to call concurrently from multiple clients).
// The tasks table has no soft-delete column.
func (r *TaskRepo) SetContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error {
	_, err := r.db.Exec(ctx,
		"UPDATE tasks SET content_enc = $2 WHERE id = $1 AND content_enc IS NULL",
		id, contentEnc,
	)
	if err != nil {
		return fmt.Errorf("set content_enc: %w", err)
	}
	return nil
}

func (r *TaskRepo) queryTasks(ctx context.Context, query string, args ...interface{}) ([]tasks.Task, error) {
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("query tasks: %w", err)
	}
	defer rows.Close()
	var result []tasks.Task
	for rows.Next() {
		var t tasks.Task
		if err := rows.Scan(&t.ID, &t.ProfileID, &t.DueDate, &t.Status, &t.DoneAt,
			&t.RelatedDiaryEventID, &t.RelatedAppointmentID, &t.CreatedByUserID, &t.CreatedAt, &t.UpdatedAt, &t.ContentEnc); err != nil {
			return nil, fmt.Errorf("scan task row: %w", err)
		}
		result = append(result, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}
	return result, nil
}
