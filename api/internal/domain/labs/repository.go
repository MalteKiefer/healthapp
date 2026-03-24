package labs

import (
	"context"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for lab results.
type Repository interface {
	Create(ctx context.Context, lr *LabResult) error
	GetByID(ctx context.Context, id uuid.UUID) (*LabResult, error)
	List(ctx context.Context, profileID uuid.UUID, limit, offset int) ([]LabResult, int, error)
	Update(ctx context.Context, lr *LabResult) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
	CheckDuplicate(ctx context.Context, lr *LabResult) (*uuid.UUID, error)
}
