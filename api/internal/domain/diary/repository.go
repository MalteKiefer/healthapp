package diary

import (
	"context"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for health diary events.
type Repository interface {
	Create(ctx context.Context, e *DiaryEvent) error
	GetByID(ctx context.Context, id uuid.UUID) (*DiaryEvent, error)
	List(ctx context.Context, filter ListFilter) ([]DiaryEvent, int, error)
	Update(ctx context.Context, e *DiaryEvent) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
}
