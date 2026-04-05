package diary

import (
	"time"

	"github.com/google/uuid"
)

// EventType enumerates the kinds of health diary events.
type EventType string

const (
	EventTypeAccident         EventType = "accident"
	EventTypeIllness          EventType = "illness"
	EventTypeSurgery          EventType = "surgery"
	EventTypeHospitalStay     EventType = "hospital_stay"
	EventTypeEmergency        EventType = "emergency"
	EventTypeDoctorVisit      EventType = "doctor_visit"
	EventTypeVaccination      EventType = "vaccination"
	EventTypeMedicationChange EventType = "medication_change"
	EventTypeSymptom          EventType = "symptom"
	EventTypeOther            EventType = "other"
)

// DiaryEvent represents a single health diary entry with versioning support.
type DiaryEvent struct {
	ID          uuid.UUID  `json:"id"`
	ProfileID   uuid.UUID  `json:"profile_id"`
	Title       string     `json:"title"`
	EventType   EventType  `json:"event_type"`
	StartedAt   time.Time  `json:"started_at"`
	EndedAt     *time.Time `json:"ended_at,omitempty"`
	Description *string    `json:"description,omitempty"`
	Severity    *int       `json:"severity,omitempty"`
	Location    *string    `json:"location,omitempty"`
	Outcome     *string    `json:"outcome,omitempty"`
	Version     int        `json:"version"`
	PreviousID  *uuid.UUID `json:"previous_id,omitempty"`
	IsCurrent   bool       `json:"is_current"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	DeletedAt   *time.Time `json:"-"`
	// ContentEnc holds the AES-GCM-encrypted JSON blob of all sensitive fields
	// (produced client-side with the profile key). During Stage 2 lazy
	// migration it lives alongside the plaintext columns; Stage 2.4 drops
	// the plaintext columns and enforces NOT NULL.
	ContentEnc *string `json:"content_enc,omitempty"`
}

// ListFilter defines query parameters for listing diary events.
type ListFilter struct {
	ProfileID uuid.UUID
	EventType *EventType
	From      *time.Time
	To        *time.Time
	Limit     int
	Offset    int
}
