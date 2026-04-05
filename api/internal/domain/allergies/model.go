package allergies

import (
	"time"

	"github.com/google/uuid"
)

// Allergy represents a recorded allergy or intolerance.
type Allergy struct {
	ID           uuid.UUID  `json:"id"`
	ProfileID    uuid.UUID  `json:"profile_id"`
	Name         string     `json:"name"`
	Category     *string    `json:"category,omitempty"`
	ReactionType *string    `json:"reaction_type,omitempty"`
	Severity     *string    `json:"severity,omitempty"`
	OnsetDate    *time.Time `json:"onset_date,omitempty"`
	DiagnosedBy  *string    `json:"diagnosed_by,omitempty"`
	Notes        *string    `json:"notes,omitempty"`
	Status       *string    `json:"status,omitempty"`
	Version      int        `json:"version"`
	PreviousID   *uuid.UUID `json:"previous_id,omitempty"`
	IsCurrent    bool       `json:"is_current"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
	DeletedAt    *time.Time `json:"-"`
	// ContentEnc holds the AES-GCM-encrypted JSON blob of all sensitive fields
	// (produced client-side with the profile key). During Stage 2 lazy
	// migration it lives alongside the plaintext columns; Stage 2.4 drops
	// the plaintext columns and enforces NOT NULL.
	ContentEnc *string `json:"content_enc,omitempty"`
}

// ListFilter defines query parameters for listing allergies.
type ListFilter struct {
	ProfileID uuid.UUID
	Limit     int
	Offset    int
}
