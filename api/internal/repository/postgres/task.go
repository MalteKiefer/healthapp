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
		INSERT INTO tasks (id, profile_id, title, due_date, priority, status, related_diary_event_id, related_appointment_id, notes, created_by_user_id, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
		t.ID, t.ProfileID, t.Title, t.DueDate, t.Priority, t.Status,
		t.RelatedDiaryEventID, t.RelatedAppointmentID, t.Notes, t.CreatedByUserID, t.CreatedAt, t.UpdatedAt)
	return err
}

func (r *TaskRepo) GetByID(ctx context.Context, id uuid.UUID) (*tasks.Task, error) {
	var t tasks.Task
	err := r.db.QueryRow(ctx, `
		SELECT id, profile_id, title, due_date, priority, status, done_at, related_diary_event_id, related_appointment_id, notes, created_by_user_id, created_at, updated_at
		FROM tasks WHERE id = $1`, id).Scan(
		&t.ID, &t.ProfileID, &t.Title, &t.DueDate, &t.Priority, &t.Status, &t.DoneAt,
		&t.RelatedDiaryEventID, &t.RelatedAppointmentID, &t.Notes, &t.CreatedByUserID, &t.CreatedAt, &t.UpdatedAt)
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
		SELECT id, profile_id, title, due_date, priority, status, done_at, related_diary_event_id, related_appointment_id, notes, created_by_user_id, created_at, updated_at
		FROM tasks WHERE profile_id = $1 ORDER BY due_date ASC NULLS LAST`, profileID)
}

func (r *TaskRepo) GetOpen(ctx context.Context, profileID uuid.UUID) ([]tasks.Task, error) {
	return r.queryTasks(ctx, `
		SELECT id, profile_id, title, due_date, priority, status, done_at, related_diary_event_id, related_appointment_id, notes, created_by_user_id, created_at, updated_at
		FROM tasks WHERE profile_id = $1 AND status = 'open' ORDER BY due_date ASC NULLS LAST`, profileID)
}

func (r *TaskRepo) Update(ctx context.Context, t *tasks.Task) error {
	t.UpdatedAt = time.Now().UTC()
	if t.Status == "done" && t.DoneAt == nil {
		now := time.Now().UTC()
		t.DoneAt = &now
	}
	_, err := r.db.Exec(ctx, `
		UPDATE tasks SET title=$2, due_date=$3, priority=$4, status=$5, done_at=$6, notes=$7, updated_at=$8
		WHERE id=$1`,
		t.ID, t.Title, t.DueDate, t.Priority, t.Status, t.DoneAt, t.Notes, t.UpdatedAt)
	return err
}

func (r *TaskRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "DELETE FROM tasks WHERE id=$1", id)
	return err
}

func (r *TaskRepo) queryTasks(ctx context.Context, query string, args ...interface{}) ([]tasks.Task, error) {
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []tasks.Task
	for rows.Next() {
		var t tasks.Task
		if err := rows.Scan(&t.ID, &t.ProfileID, &t.Title, &t.DueDate, &t.Priority, &t.Status, &t.DoneAt,
			&t.RelatedDiaryEventID, &t.RelatedAppointmentID, &t.Notes, &t.CreatedByUserID, &t.CreatedAt, &t.UpdatedAt); err != nil {
			return nil, err
		}
		result = append(result, t)
	}
	return result, nil
}
