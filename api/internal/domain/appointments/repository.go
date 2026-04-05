package appointments

import (
	"context"

	"github.com/google/uuid"
)

type Repository interface {
	Create(ctx context.Context, a *Appointment) error
	GetByID(ctx context.Context, id uuid.UUID) (*Appointment, error)
	List(ctx context.Context, profileID uuid.UUID) ([]Appointment, error)
	GetUpcoming(ctx context.Context, profileID uuid.UUID) ([]Appointment, error)
	Update(ctx context.Context, a *Appointment) error
	Delete(ctx context.Context, id uuid.UUID) error
	Complete(ctx context.Context, id uuid.UUID, diaryEventID *uuid.UUID) error
	SetContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error
}
