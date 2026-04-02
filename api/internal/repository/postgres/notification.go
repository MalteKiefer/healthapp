package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/notifications"
)

type NotificationRepo struct {
	db *pgxpool.Pool
}

func NewNotificationRepo(db *pgxpool.Pool) *NotificationRepo {
	return &NotificationRepo{db: db}
}

func (r *NotificationRepo) Create(ctx context.Context, n *notifications.Notification) error {
	if n.ID == uuid.Nil {
		n.ID = uuid.New()
	}
	n.CreatedAt = time.Now().UTC()

	metadataJSON, err := json.Marshal(n.Metadata)
	if err != nil {
		return fmt.Errorf("marshal metadata: %w", err)
	}

	_, err = r.db.Exec(ctx, `
		INSERT INTO notifications (id, user_id, type, title, body, metadata, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		n.ID, n.UserID, n.Type, n.Title, n.Body, metadataJSON, n.CreatedAt)
	if err != nil {
		return fmt.Errorf("insert notification: %w", err)
	}
	return nil
}

func (r *NotificationRepo) List(ctx context.Context, filter notifications.ListFilter) ([]notifications.Notification, int, error) {
	var total int
	if err := r.db.QueryRow(ctx,
		"SELECT COUNT(*) FROM notifications WHERE user_id = $1",
		filter.UserID,
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count notifications: %w", err)
	}

	query := `
		SELECT id, user_id, type, title, body, metadata, read_at, created_at
		FROM notifications
		WHERE user_id = $1
		ORDER BY (read_at IS NULL) DESC, created_at DESC`

	args := []interface{}{filter.UserID}
	idx := 2

	if filter.Limit > 0 {
		query += fmt.Sprintf(" LIMIT $%d", idx)
		args = append(args, filter.Limit)
		idx++
	}
	if filter.Offset > 0 {
		query += fmt.Sprintf(" OFFSET $%d", idx)
		args = append(args, filter.Offset)
	}

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("query notifications: %w", err)
	}
	defer rows.Close()

	var result []notifications.Notification
	for rows.Next() {
		n, err := r.scanNotificationRow(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, *n)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate rows: %w", err)
	}

	return result, total, nil
}

func (r *NotificationRepo) MarkRead(ctx context.Context, id uuid.UUID, userID uuid.UUID) error {
	tag, err := r.db.Exec(ctx,
		"UPDATE notifications SET read_at = $2 WHERE id = $1 AND user_id = $3 AND read_at IS NULL",
		id, time.Now().UTC(), userID)
	if err != nil {
		return fmt.Errorf("mark notification read: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *NotificationRepo) MarkAllRead(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE notifications SET read_at = $2 WHERE user_id = $1 AND read_at IS NULL",
		userID, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("mark all notifications read: %w", err)
	}
	return nil
}

func (r *NotificationRepo) Delete(ctx context.Context, id uuid.UUID, userID uuid.UUID) error {
	tag, err := r.db.Exec(ctx, "DELETE FROM notifications WHERE id = $1 AND user_id = $2", id, userID)
	if err != nil {
		return fmt.Errorf("delete notification: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *NotificationRepo) GetPreferences(ctx context.Context, userID uuid.UUID) (*notifications.NotificationPreferences, error) {
	var p notifications.NotificationPreferences
	err := r.db.QueryRow(ctx, `
		SELECT user_id, vaccination_due, vaccination_due_days, medication_reminder,
			lab_result_abnormal, emergency_access, export_ready, family_invite,
			key_rotation_required, session_new, storage_quota_warning
		FROM notification_preferences WHERE user_id = $1`, userID).Scan(
		&p.UserID, &p.VaccinationDue, &p.VaccinationDueDays, &p.MedicationReminder,
		&p.LabResultAbnormal, &p.EmergencyAccess, &p.ExportReady, &p.FamilyInvite,
		&p.KeyRotationRequired, &p.SessionNew, &p.StorageQuotaWarning)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan notification preferences: %w", err)
	}
	return &p, nil
}

func (r *NotificationRepo) UpsertPreferences(ctx context.Context, prefs *notifications.NotificationPreferences) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO notification_preferences (
			user_id, vaccination_due, vaccination_due_days, medication_reminder,
			lab_result_abnormal, emergency_access, export_ready, family_invite,
			key_rotation_required, session_new, storage_quota_warning
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		ON CONFLICT (user_id) DO UPDATE SET
			vaccination_due = EXCLUDED.vaccination_due,
			vaccination_due_days = EXCLUDED.vaccination_due_days,
			medication_reminder = EXCLUDED.medication_reminder,
			lab_result_abnormal = EXCLUDED.lab_result_abnormal,
			emergency_access = EXCLUDED.emergency_access,
			export_ready = EXCLUDED.export_ready,
			family_invite = EXCLUDED.family_invite,
			key_rotation_required = EXCLUDED.key_rotation_required,
			session_new = EXCLUDED.session_new,
			storage_quota_warning = EXCLUDED.storage_quota_warning`,
		prefs.UserID, prefs.VaccinationDue, prefs.VaccinationDueDays, prefs.MedicationReminder,
		prefs.LabResultAbnormal, prefs.EmergencyAccess, prefs.ExportReady, prefs.FamilyInvite,
		prefs.KeyRotationRequired, prefs.SessionNew, prefs.StorageQuotaWarning)
	if err != nil {
		return fmt.Errorf("upsert notification preferences: %w", err)
	}
	return nil
}

func (r *NotificationRepo) scanNotificationRow(rows pgx.Rows) (*notifications.Notification, error) {
	var n notifications.Notification
	var metadataJSON []byte
	err := rows.Scan(
		&n.ID, &n.UserID, &n.Type, &n.Title, &n.Body,
		&metadataJSON, &n.ReadAt, &n.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("scan notification row: %w", err)
	}
	if metadataJSON != nil {
		if err := json.Unmarshal(metadataJSON, &n.Metadata); err != nil {
			return nil, fmt.Errorf("unmarshal metadata: %w", err)
		}
	}
	return &n, nil
}
