package documents

import (
	"context"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for health documents.
type Repository interface {
	Create(ctx context.Context, d *Document) error
	GetByID(ctx context.Context, id uuid.UUID) (*Document, error)
	List(ctx context.Context, filter ListFilter) ([]Document, int, error)
	Update(ctx context.Context, d *Document) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
}
