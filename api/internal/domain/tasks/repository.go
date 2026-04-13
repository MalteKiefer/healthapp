package tasks

import (
	"context"

	"github.com/google/uuid"
)

type Repository interface {
	Create(ctx context.Context, t *Task) error
	GetByID(ctx context.Context, id uuid.UUID) (*Task, error)
	List(ctx context.Context, profileID uuid.UUID) ([]Task, error)
	GetOpen(ctx context.Context, profileID uuid.UUID) ([]Task, error)
	Update(ctx context.Context, t *Task) error
	Delete(ctx context.Context, id uuid.UUID) error
}
