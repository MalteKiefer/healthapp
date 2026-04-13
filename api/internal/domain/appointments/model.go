package appointments

import (
	"time"

	"github.com/google/uuid"
)

type Appointment struct {
	ID        uuid.UUID `json:"id"`
	ProfileID uuid.UUID `json:"profile_id"`

	Title              string `json:"title"`
	AppointmentType    string `json:"appointment_type"`
	Location           *string `json:"location,omitempty"`
	PreparationNotes   *string `json:"preparation_notes,omitempty"`
	ReminderDaysBefore []int   `json:"reminder_days_before,omitempty"`
	Recurrence         string  `json:"recurrence"`

	ScheduledAt        time.Time  `json:"scheduled_at"`
	DurationMinutes    *int       `json:"duration_minutes,omitempty"`
	DoctorID           *uuid.UUID `json:"doctor_id,omitempty"`
	Status             string     `json:"status"`
	LinkedDiaryEventID *uuid.UUID `json:"linked_diary_event_id,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
}
