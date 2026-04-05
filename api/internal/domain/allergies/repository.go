package allergies

import (
	"context"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for allergies.
type Repository interface {
	Create(ctx context.Context, a *Allergy) error
	GetByID(ctx context.Context, id uuid.UUID) (*Allergy, error)
	List(ctx context.Context, filter ListFilter) ([]Allergy, int, error)
	Update(ctx context.Context, a *Allergy) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
	SetContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error
}
