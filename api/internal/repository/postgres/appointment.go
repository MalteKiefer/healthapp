package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/appointments"
)

type AppointmentRepo struct{ db *pgxpool.Pool }

func NewAppointmentRepo(db *pgxpool.Pool) *AppointmentRepo { return &AppointmentRepo{db: db} }

const apptColumns = `id, profile_id, title, appointment_type, location, preparation_notes,
	reminder_days_before, recurrence, scheduled_at, duration_minutes, doctor_id, status,
	linked_diary_event_id, created_at, updated_at`

func (r *AppointmentRepo) Create(ctx context.Context, a *appointments.Appointment) error {
	if a.ID == uuid.Nil {
		a.ID = uuid.New()
	}
	now := time.Now().UTC()
	a.CreatedAt = now
	a.UpdatedAt = now
	if a.Status == "" {
		a.Status = "scheduled"
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO appointments (id, profile_id, title, appointment_type, location, preparation_notes,
			reminder_days_before, recurrence, scheduled_at, duration_minutes, doctor_id, status, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)`,
		a.ID, a.ProfileID, a.Title, a.AppointmentType, a.Location, a.PreparationNotes,
		a.ReminderDaysBefore, a.Recurrence, a.ScheduledAt, a.DurationMinutes,
		a.DoctorID, a.Status, a.CreatedAt, a.UpdatedAt)
	if err != nil {
		return fmt.Errorf("create appointment: %w", err)
	}
	return nil
}

func (r *AppointmentRepo) GetByID(ctx context.Context, id uuid.UUID) (*appointments.Appointment, error) {
	var a appointments.Appointment
	err := r.db.QueryRow(ctx, `SELECT `+apptColumns+` FROM appointments WHERE id = $1`, id).Scan(
		&a.ID, &a.ProfileID, &a.Title, &a.AppointmentType, &a.Location, &a.PreparationNotes,
		&a.ReminderDaysBefore, &a.Recurrence, &a.ScheduledAt, &a.DurationMinutes,
		&a.DoctorID, &a.Status, &a.LinkedDiaryEventID, &a.CreatedAt, &a.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan appointment: %w", err)
	}
	return &a, nil
}

func (r *AppointmentRepo) List(ctx context.Context, profileID uuid.UUID) ([]appointments.Appointment, error) {
	return r.queryAppointments(ctx, `SELECT `+apptColumns+`
		FROM appointments WHERE profile_id = $1 ORDER BY scheduled_at DESC`, profileID)
}

func (r *AppointmentRepo) GetUpcoming(ctx context.Context, profileID uuid.UUID) ([]appointments.Appointment, error) {
	return r.queryAppointments(ctx, `SELECT `+apptColumns+`
		FROM appointments WHERE profile_id = $1 AND status = 'scheduled' AND scheduled_at >= NOW()
		ORDER BY scheduled_at ASC`, profileID)
}

func (r *AppointmentRepo) Update(ctx context.Context, a *appointments.Appointment) error {
	a.UpdatedAt = time.Now().UTC()
	_, err := r.db.Exec(ctx, `
		UPDATE appointments SET title=$2, appointment_type=$3, location=$4, preparation_notes=$5,
			reminder_days_before=$6, recurrence=$7, scheduled_at=$8, duration_minutes=$9,
			doctor_id=$10, status=$11, updated_at=$12
		WHERE id=$1`,
		a.ID, a.Title, a.AppointmentType, a.Location, a.PreparationNotes,
		a.ReminderDaysBefore, a.Recurrence, a.ScheduledAt, a.DurationMinutes,
		a.DoctorID, a.Status, a.UpdatedAt)
	if err != nil {
		return fmt.Errorf("update appointment: %w", err)
	}
	return nil
}

func (r *AppointmentRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "DELETE FROM appointments WHERE id=$1", id)
	if err != nil {
		return fmt.Errorf("delete appointment: %w", err)
	}
	return nil
}

func (r *AppointmentRepo) Complete(ctx context.Context, id uuid.UUID, diaryEventID *uuid.UUID) error {
	_, err := r.db.Exec(ctx, `
		UPDATE appointments SET status='completed', linked_diary_event_id=$2, updated_at=$3
		WHERE id=$1`, id, diaryEventID, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("complete appointment: %w", err)
	}
	return nil
}

func (r *AppointmentRepo) queryAppointments(ctx context.Context, query string, args ...interface{}) ([]appointments.Appointment, error) {
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("query appointments: %w", err)
	}
	defer rows.Close()
	var result []appointments.Appointment
	for rows.Next() {
		var a appointments.Appointment
		if err := rows.Scan(&a.ID, &a.ProfileID, &a.Title, &a.AppointmentType, &a.Location, &a.PreparationNotes,
			&a.ReminderDaysBefore, &a.Recurrence, &a.ScheduledAt, &a.DurationMinutes,
			&a.DoctorID, &a.Status, &a.LinkedDiaryEventID, &a.CreatedAt, &a.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan appointment row: %w", err)
		}
		result = append(result, a)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}
	return result, nil
}
