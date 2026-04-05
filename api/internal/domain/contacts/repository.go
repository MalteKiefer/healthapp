package contacts

import (
	"context"

	"github.com/google/uuid"
)

type Repository interface {
	Create(ctx context.Context, c *Contact) error
	GetByID(ctx context.Context, id uuid.UUID) (*Contact, error)
	List(ctx context.Context, profileID uuid.UUID) ([]Contact, error)
	Update(ctx context.Context, c *Contact) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
	SetContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error
}
