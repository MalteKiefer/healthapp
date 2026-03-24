package calendar

import (
	"time"

	"github.com/google/uuid"
)

// Feed represents a user's ICS calendar feed configuration.
type Feed struct {
	ID                  uuid.UUID `json:"id"`
	UserID              uuid.UUID `json:"user_id"`
	Name                string    `json:"name"`
	TokenHash           string    `json:"-"`
	ProfileIDs          []uuid.UUID `json:"profile_ids"`
	IncludeAppointments bool      `json:"include_appointments"`
	IncludeTasks        bool      `json:"include_tasks"`
	IncludeVaccinations bool      `json:"include_vaccinations"`
	IncludeMedications  bool      `json:"include_medications"`
	IncludeLabs         bool      `json:"include_labs"`
	VerboseMode         bool      `json:"verbose_mode"`
	LastPolledAt        *time.Time `json:"last_polled_at,omitempty"`
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`
}

// FeedWithToken includes the plaintext token (only returned on creation).
type FeedWithToken struct {
	Feed
	Token string `json:"token"`
	URL   string `json:"url"`
}

// CalendarEvent represents a single event to render in ICS output.
type CalendarEvent struct {
	UID         string
	Summary     string
	Description string
	Location    string
	Start       time.Time
	End         *time.Time
	AllDay      bool
	Alarms      []Alarm
	IsTodo      bool
	Priority    int
	Status      string
}

// Alarm represents a VALARM in an ICS event.
type Alarm struct {
	TriggerBefore time.Duration
	Description   string
}
