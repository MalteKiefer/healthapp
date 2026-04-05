package medications

import (
	"context"
	"time"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for medications.
type Repository interface {
	Create(ctx context.Context, m *Medication) error
	GetByID(ctx context.Context, id uuid.UUID) (*Medication, error)
	List(ctx context.Context, filter ListFilter) ([]Medication, int, error)
	Update(ctx context.Context, m *Medication) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
	GetActive(ctx context.Context, profileID uuid.UUID) ([]Medication, error)

	CreateIntake(ctx context.Context, intake *MedicationIntake) error
	GetIntakeByID(ctx context.Context, id uuid.UUID) (*MedicationIntake, error)
	UpdateIntake(ctx context.Context, intake *MedicationIntake) error
	DeleteIntake(ctx context.Context, id uuid.UUID) error
	ListIntake(ctx context.Context, medicationID uuid.UUID, limit, offset int) ([]MedicationIntake, int, error)
	GetAdherence(ctx context.Context, medicationID uuid.UUID, from, to *time.Time) (*AdherenceSummary, error)

	SetMedicationContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error
	SetMedicationIntakeContentEnc(ctx context.Context, id uuid.UUID, contentEnc string) error
}
