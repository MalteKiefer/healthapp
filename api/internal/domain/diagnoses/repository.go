package diagnoses

import (
	"context"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for diagnoses.
type Repository interface {
	Create(ctx context.Context, d *Diagnosis) error
	GetByID(ctx context.Context, id uuid.UUID) (*Diagnosis, error)
	List(ctx context.Context, filter ListFilter) ([]Diagnosis, int, error)
	Update(ctx context.Context, d *Diagnosis) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
}
