package symptoms

import (
	"time"

	"github.com/google/uuid"
)

type SymptomRecord struct {
	ID        uuid.UUID `json:"id"`
	ProfileID uuid.UUID `json:"profile_id"`

	// --- Fields below come from content_enc decryption on the client, not from DB columns ---
	RecordedAt     time.Time      `json:"recorded_at"`
	TriggerFactors []string       `json:"trigger_factors,omitempty"`
	Notes          *string        `json:"notes,omitempty"`
	// --- End content_enc-only fields ---

	Entries       []SymptomEntry `json:"entries"`
	LinkedVitalID *uuid.UUID     `json:"linked_vital_id,omitempty"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     *time.Time     `json:"-"`
	// ContentEnc holds the AES-GCM-encrypted JSON blob of all health fields
	// (produced client-side with the profile key). The plaintext DB columns
	// were dropped in Stage 2.4; this is now the sole source of health data.
	ContentEnc *string `json:"content_enc,omitempty"`
}

type SymptomEntry struct {
	ID              uuid.UUID `json:"id"`
	SymptomRecordID uuid.UUID `json:"symptom_record_id"`

	// --- Fields below come from content_enc decryption on the client, not from DB columns ---
	SymptomType     string  `json:"symptom_type"`
	CustomLabel     *string `json:"custom_label,omitempty"`
	Intensity       int     `json:"intensity"`
	BodyRegion      *string `json:"body_region,omitempty"`
	DurationMinutes *int    `json:"duration_minutes,omitempty"`
	// --- End content_enc-only fields ---

	// ContentEnc holds the AES-GCM-encrypted JSON blob of all health fields
	// (produced client-side with the profile key). The plaintext DB columns
	// were dropped in Stage 2.4; this is now the sole source of health data.
	ContentEnc *string `json:"content_enc,omitempty"`
}
