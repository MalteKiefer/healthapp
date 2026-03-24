package symptoms

import (
	"time"

	"github.com/google/uuid"
)

type SymptomRecord struct {
	ID             uuid.UUID      `json:"id"`
	ProfileID      uuid.UUID      `json:"profile_id"`
	RecordedAt     time.Time      `json:"recorded_at"`
	Entries        []SymptomEntry `json:"entries"`
	TriggerFactors []string       `json:"trigger_factors,omitempty"`
	Notes          *string        `json:"notes,omitempty"`
	LinkedVitalID  *uuid.UUID     `json:"linked_vital_id,omitempty"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      *time.Time     `json:"-"`
}

type SymptomEntry struct {
	ID              uuid.UUID `json:"id"`
	SymptomRecordID uuid.UUID `json:"symptom_record_id"`
	SymptomType     string    `json:"symptom_type"`
	CustomLabel     *string   `json:"custom_label,omitempty"`
	Intensity       int       `json:"intensity"`
	BodyRegion      *string   `json:"body_region,omitempty"`
	DurationMinutes *int      `json:"duration_minutes,omitempty"`
}
