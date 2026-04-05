package symptoms

import (
	"context"

	"github.com/google/uuid"
)

type Repository interface {
	Create(ctx context.Context, s *SymptomRecord) error
	GetByID(ctx context.Context, id uuid.UUID) (*SymptomRecord, error)
	List(ctx context.Context, profileID uuid.UUID, limit, offset int) ([]SymptomRecord, int, error)
	Update(ctx context.Context, s *SymptomRecord) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
	SetSymptomRecordContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error
	SetSymptomEntryContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error
}
