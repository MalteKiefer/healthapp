package medications

import (
	"time"

	"github.com/google/uuid"
)

// Medication represents a prescribed or self-reported medication.
type Medication struct {
	ID        uuid.UUID `json:"id"`
	ProfileID uuid.UUID `json:"profile_id"`

	// --- Fields below come from content_enc decryption on the client, not from DB columns ---
	Name         string  `json:"name"`
	Dosage       *string `json:"dosage,omitempty"`
	Unit         *string `json:"unit,omitempty"`
	Frequency    *string `json:"frequency,omitempty"`
	Route        *string `json:"route,omitempty"`
	PrescribedBy *string `json:"prescribed_by,omitempty"`
	Reason       *string `json:"reason,omitempty"`
	Notes        *string `json:"notes,omitempty"`
	// --- End content_enc-only fields ---

	StartedAt          *time.Time `json:"started_at,omitempty"`
	EndedAt            *time.Time `json:"ended_at,omitempty"`
	RelatedDiagnosisID *uuid.UUID `json:"related_diagnosis_id,omitempty"`
	Version            int        `json:"version"`
	PreviousID         *uuid.UUID `json:"previous_id,omitempty"`
	IsCurrent          bool       `json:"is_current"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
	DeletedAt          *time.Time `json:"-"`
	// ContentEnc holds the AES-GCM-encrypted JSON blob of all health fields
	// (produced client-side with the profile key). The plaintext DB columns
	// were dropped in Stage 2.4; this is now the sole source of health data.
	ContentEnc *string `json:"content_enc,omitempty"`
}

// MedicationIntake records when a medication dose was taken or skipped.
type MedicationIntake struct {
	ID           uuid.UUID  `json:"id"`
	MedicationID uuid.UUID  `json:"medication_id"`
	ProfileID    uuid.UUID  `json:"profile_id"`
	ScheduledAt  *time.Time `json:"scheduled_at,omitempty"`
	TakenAt      *time.Time `json:"taken_at,omitempty"`

	// --- Fields below come from content_enc decryption on the client, not from DB columns ---
	DoseTaken     *string `json:"dose_taken,omitempty"`
	SkippedReason *string `json:"skipped_reason,omitempty"`
	Notes         *string `json:"notes,omitempty"`
	// --- End content_enc-only fields ---

	CreatedAt time.Time `json:"created_at"`
	// ContentEnc holds the AES-GCM-encrypted JSON blob of all health fields
	// (produced client-side with the profile key). The plaintext DB columns
	// were dropped in Stage 2.4; this is now the sole source of health data.
	ContentEnc *string `json:"content_enc,omitempty"`
}

// ListFilter defines query parameters for listing medications.
type ListFilter struct {
	ProfileID  uuid.UUID
	ActiveOnly bool
	Limit      int
	Offset     int
}

// AdherenceSummary provides adherence statistics for a medication.
type AdherenceSummary struct {
	MedicationID   uuid.UUID `json:"medication_id"`
	TotalScheduled int       `json:"total_scheduled"`
	TotalTaken     int       `json:"total_taken"`
	TotalSkipped   int       `json:"total_skipped"`
	AdherenceRate  float64   `json:"adherence_rate"`
}
