package tasks

import (
	"time"

	"github.com/google/uuid"
)

type Task struct {
	ID                    uuid.UUID  `json:"id"`
	ProfileID             uuid.UUID  `json:"profile_id"`
	Title                 string     `json:"title"`
	DueDate               *time.Time `json:"due_date,omitempty"`
	Priority              string     `json:"priority"`
	Status                string     `json:"status"`
	DoneAt                *time.Time `json:"done_at,omitempty"`
	RelatedDiaryEventID   *uuid.UUID `json:"related_diary_event_id,omitempty"`
	RelatedAppointmentID  *uuid.UUID `json:"related_appointment_id,omitempty"`
	Notes                 *string    `json:"notes,omitempty"`
	CreatedByUserID       uuid.UUID  `json:"created_by_user_id"`
	CreatedAt             time.Time  `json:"created_at"`
	UpdatedAt             time.Time  `json:"updated_at"`
	// ContentEnc holds the AES-GCM-encrypted JSON blob of all sensitive fields
	// (produced client-side with the profile key). During Stage 2 lazy
	// migration it lives alongside the plaintext columns; Stage 2.4 drops
	// the plaintext columns and enforces NOT NULL.
	ContentEnc            *string    `json:"content_enc,omitempty"`
}
