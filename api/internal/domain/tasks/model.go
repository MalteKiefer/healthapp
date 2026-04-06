package tasks

import (
	"time"

	"github.com/google/uuid"
)

type Task struct {
	ID        uuid.UUID `json:"id"`
	ProfileID uuid.UUID `json:"profile_id"`

	// --- Fields below come from content_enc decryption on the client, not from DB columns ---
	Title    string  `json:"title"`
	Priority string  `json:"priority"`
	Notes    *string `json:"notes,omitempty"`
	// --- End content_enc-only fields ---

	DueDate              *time.Time `json:"due_date,omitempty"`
	Status               string     `json:"status"`
	DoneAt               *time.Time `json:"done_at,omitempty"`
	RelatedDiaryEventID  *uuid.UUID `json:"related_diary_event_id,omitempty"`
	RelatedAppointmentID *uuid.UUID `json:"related_appointment_id,omitempty"`
	CreatedByUserID      uuid.UUID  `json:"created_by_user_id"`
	CreatedAt            time.Time  `json:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at"`
	// ContentEnc holds the AES-GCM-encrypted JSON blob of all sensitive fields
	// (produced client-side with the profile key). The plaintext DB columns
	// were dropped in Stage 2.4; this is now the sole source of health data.
	ContentEnc *string `json:"content_enc,omitempty"`
}
