package appointments

import (
	"time"

	"github.com/google/uuid"
)

type Appointment struct {
	ID                  uuid.UUID  `json:"id"`
	ProfileID           uuid.UUID  `json:"profile_id"`
	Title               string     `json:"title"`
	AppointmentType     string     `json:"appointment_type"`
	ScheduledAt         time.Time  `json:"scheduled_at"`
	DurationMinutes     *int       `json:"duration_minutes,omitempty"`
	DoctorID            *uuid.UUID `json:"doctor_id,omitempty"`
	Location            *string    `json:"location,omitempty"`
	PreparationNotes    *string    `json:"preparation_notes,omitempty"`
	ReminderDaysBefore  []int      `json:"reminder_days_before,omitempty"`
	Status              string     `json:"status"`
	LinkedDiaryEventID  *uuid.UUID `json:"linked_diary_event_id,omitempty"`
	Recurrence          string     `json:"recurrence"`
	CreatedAt           time.Time  `json:"created_at"`
	UpdatedAt           time.Time  `json:"updated_at"`
	// ContentEnc holds the AES-GCM-encrypted JSON blob of all sensitive fields
	// (produced client-side with the profile key). During Stage 2 lazy
	// migration it lives alongside the plaintext columns; Stage 2.4 drops
	// the plaintext columns and enforces NOT NULL.
	ContentEnc          *string    `json:"content_enc,omitempty"`
}
