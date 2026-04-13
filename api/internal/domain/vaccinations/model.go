package vaccinations

import (
	"time"

	"github.com/google/uuid"
)

// Vaccination represents a single vaccination record.
type Vaccination struct {
	ID        uuid.UUID `json:"id"`
	ProfileID uuid.UUID `json:"profile_id"`

	VaccineName    string  `json:"vaccine_name"`
	TradeName      *string `json:"trade_name,omitempty"`
	Manufacturer   *string `json:"manufacturer,omitempty"`
	LotNumber      *string `json:"lot_number,omitempty"`
	DoseNumber     *int    `json:"dose_number,omitempty"`
	AdministeredBy *string `json:"administered_by,omitempty"`
	Site           *string `json:"site,omitempty"`
	Notes          *string `json:"notes,omitempty"`

	AdministeredAt time.Time  `json:"administered_at"`
	NextDueAt      *time.Time `json:"next_due_at,omitempty"`
	DocumentID     *uuid.UUID `json:"document_id,omitempty"`
	Version        int        `json:"version"`
	PreviousID     *uuid.UUID `json:"previous_id,omitempty"`
	IsCurrent      bool       `json:"is_current"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
	DeletedAt      *time.Time `json:"-"`
}

// ListFilter defines query parameters for listing vaccinations.
type ListFilter struct {
	ProfileID uuid.UUID
	Limit     int
	Offset    int
}
