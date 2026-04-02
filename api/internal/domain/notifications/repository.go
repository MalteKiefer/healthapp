package notifications

import (
	"context"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for notifications.
type Repository interface {
	Create(ctx context.Context, n *Notification) error
	List(ctx context.Context, filter ListFilter) ([]Notification, int, error)
	MarkRead(ctx context.Context, id uuid.UUID, userID uuid.UUID) error
	MarkAllRead(ctx context.Context, userID uuid.UUID) error
	Delete(ctx context.Context, id uuid.UUID, userID uuid.UUID) error
	GetPreferences(ctx context.Context, userID uuid.UUID) (*NotificationPreferences, error)
	UpsertPreferences(ctx context.Context, prefs *NotificationPreferences) error
}
