package vaccinations

import (
	"context"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for vaccinations.
type Repository interface {
	Create(ctx context.Context, v *Vaccination) error
	GetByID(ctx context.Context, id uuid.UUID) (*Vaccination, error)
	List(ctx context.Context, filter ListFilter) ([]Vaccination, int, error)
	Update(ctx context.Context, v *Vaccination) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
	GetDue(ctx context.Context, profileID uuid.UUID) ([]Vaccination, error)
}
