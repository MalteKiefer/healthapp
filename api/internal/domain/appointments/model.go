package appointments

import (
	"time"

	"github.com/google/uuid"
)

type Appointment struct {
	ID        uuid.UUID `json:"id"`
	ProfileID uuid.UUID `json:"profile_id"`

	// --- Fields below come from content_enc decryption on the client, not from DB columns ---
	Title              string `json:"title"`
	AppointmentType    string `json:"appointment_type"`
	Location           *string `json:"location,omitempty"`
	PreparationNotes   *string `json:"preparation_notes,omitempty"`
	ReminderDaysBefore []int   `json:"reminder_days_before,omitempty"`
	Recurrence         string  `json:"recurrence"`
	// --- End content_enc-only fields ---

	ScheduledAt        time.Time  `json:"scheduled_at"`
	DurationMinutes    *int       `json:"duration_minutes,omitempty"`
	DoctorID           *uuid.UUID `json:"doctor_id,omitempty"`
	Status             string     `json:"status"`
	LinkedDiaryEventID *uuid.UUID `json:"linked_diary_event_id,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
	// ContentEnc holds the AES-GCM-encrypted JSON blob of all sensitive fields
	// (produced client-side with the profile key). The plaintext DB columns
	// were dropped in Stage 2.4; this is now the sole source of health data.
	ContentEnc *string `json:"content_enc,omitempty"`
}
