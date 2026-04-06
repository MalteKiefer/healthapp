package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/calendar"
)

type CalendarRepo struct{ db *pgxpool.Pool }

func NewCalendarRepo(db *pgxpool.Pool) *CalendarRepo { return &CalendarRepo{db: db} }

func (r *CalendarRepo) Create(ctx context.Context, f *calendar.Feed) error {
	if f.ID == uuid.Nil {
		f.ID = uuid.New()
	}
	now := time.Now().UTC()
	f.CreatedAt = now
	f.UpdatedAt = now

	_, err := r.db.Exec(ctx, `
		INSERT INTO calendar_feeds (id, user_id, name, token_hash, profile_ids,
			include_appointments, include_tasks, include_vaccinations,
			include_medications, include_labs, verbose_mode, content_enc, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)`,
		f.ID, f.UserID, f.Name, f.TokenHash, f.ProfileIDs,
		f.IncludeAppointments, f.IncludeTasks, f.IncludeVaccinations,
		f.IncludeMedications, f.IncludeLabs, f.VerboseMode, f.ContentEnc, f.CreatedAt, f.UpdatedAt)
	if err != nil {
		return fmt.Errorf("create calendar feed: %w", err)
	}
	return nil
}

func (r *CalendarRepo) GetByID(ctx context.Context, id uuid.UUID) (*calendar.Feed, error) {
	var f calendar.Feed
	err := r.db.QueryRow(ctx, `
		SELECT id, user_id, name, token_hash, profile_ids,
			include_appointments, include_tasks, include_vaccinations,
			include_medications, include_labs, verbose_mode,
			content_enc, last_polled_at, created_at, updated_at
		FROM calendar_feeds WHERE id = $1`, id).Scan(
		&f.ID, &f.UserID, &f.Name, &f.TokenHash, &f.ProfileIDs,
		&f.IncludeAppointments, &f.IncludeTasks, &f.IncludeVaccinations,
		&f.IncludeMedications, &f.IncludeLabs, &f.VerboseMode,
		&f.ContentEnc, &f.LastPolledAt, &f.CreatedAt, &f.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan calendar feed: %w", err)
	}
	return &f, nil
}

func (r *CalendarRepo) GetByTokenHash(ctx context.Context, tokenHash string) (*calendar.Feed, error) {
	var f calendar.Feed
	err := r.db.QueryRow(ctx, `
		SELECT id, user_id, name, token_hash, profile_ids,
			include_appointments, include_tasks, include_vaccinations,
			include_medications, include_labs, verbose_mode,
			content_enc, last_polled_at, created_at, updated_at
		FROM calendar_feeds WHERE token_hash = $1`, tokenHash).Scan(
		&f.ID, &f.UserID, &f.Name, &f.TokenHash, &f.ProfileIDs,
		&f.IncludeAppointments, &f.IncludeTasks, &f.IncludeVaccinations,
		&f.IncludeMedications, &f.IncludeLabs, &f.VerboseMode,
		&f.ContentEnc, &f.LastPolledAt, &f.CreatedAt, &f.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan calendar feed: %w", err)
	}
	return &f, nil
}

func (r *CalendarRepo) ListByUserID(ctx context.Context, userID uuid.UUID) ([]calendar.Feed, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, user_id, name, token_hash, profile_ids,
			include_appointments, include_tasks, include_vaccinations,
			include_medications, include_labs, verbose_mode,
			content_enc, last_polled_at, created_at, updated_at
		FROM calendar_feeds WHERE user_id = $1 ORDER BY created_at`, userID)
	if err != nil {
		return nil, fmt.Errorf("query calendar feeds: %w", err)
	}
	defer rows.Close()
	var feeds []calendar.Feed
	for rows.Next() {
		var f calendar.Feed
		if err := rows.Scan(&f.ID, &f.UserID, &f.Name, &f.TokenHash, &f.ProfileIDs,
			&f.IncludeAppointments, &f.IncludeTasks, &f.IncludeVaccinations,
			&f.IncludeMedications, &f.IncludeLabs, &f.VerboseMode,
			&f.ContentEnc, &f.LastPolledAt, &f.CreatedAt, &f.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan calendar feed row: %w", err)
		}
		feeds = append(feeds, f)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}
	return feeds, nil
}

func (r *CalendarRepo) Update(ctx context.Context, f *calendar.Feed) error {
	f.UpdatedAt = time.Now().UTC()
	_, err := r.db.Exec(ctx, `
		UPDATE calendar_feeds SET name=$2, profile_ids=$3,
			include_appointments=$4, include_tasks=$5, include_vaccinations=$6,
			include_medications=$7, include_labs=$8, verbose_mode=$9, content_enc=$10, updated_at=$11
		WHERE id=$1`,
		f.ID, f.Name, f.ProfileIDs,
		f.IncludeAppointments, f.IncludeTasks, f.IncludeVaccinations,
		f.IncludeMedications, f.IncludeLabs, f.VerboseMode, f.ContentEnc, f.UpdatedAt)
	if err != nil {
		return fmt.Errorf("update calendar feed: %w", err)
	}
	return nil
}

func (r *CalendarRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "DELETE FROM calendar_feeds WHERE id = $1", id)
	if err != nil {
		return fmt.Errorf("delete calendar feed: %w", err)
	}
	return nil
}

func (r *CalendarRepo) UpdateLastPolled(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "UPDATE calendar_feeds SET last_polled_at = $2 WHERE id = $1", id, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("update last polled: %w", err)
	}
	return nil
}

func (r *CalendarRepo) SetContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error {
	_, err := r.db.Exec(ctx,
		"UPDATE calendar_feeds SET content_enc = $2, updated_at = $3 WHERE id = $1 AND content_enc IS NULL",
		id, contentEnc, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("set content_enc: %w", err)
	}
	return nil
}
