package calendar

import (
	"context"

	"github.com/google/uuid"
)

type Repository interface {
	Create(ctx context.Context, f *Feed) error
	GetByID(ctx context.Context, id uuid.UUID) (*Feed, error)
	GetByTokenHash(ctx context.Context, tokenHash string) (*Feed, error)
	ListByUserID(ctx context.Context, userID uuid.UUID) ([]Feed, error)
	Update(ctx context.Context, f *Feed) error
	Delete(ctx context.Context, id uuid.UUID) error
	UpdateLastPolled(ctx context.Context, id uuid.UUID) error
	SetContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error
}
