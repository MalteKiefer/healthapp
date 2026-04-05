package vitals

import (
	"context"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for vital signs.
type Repository interface {
	Create(ctx context.Context, v *Vital) error
	GetByID(ctx context.Context, id uuid.UUID) (*Vital, error)
	List(ctx context.Context, filter ListFilter) ([]Vital, int, error)
	Update(ctx context.Context, v *Vital) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
	CheckDuplicate(ctx context.Context, v *Vital) (*uuid.UUID, error)
	GetChartData(ctx context.Context, profileID uuid.UUID, metric string, from, to *string) ([]ChartPoint, error)
	SetContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error
}
