package contacts

import (
	"time"

	"github.com/google/uuid"
)

type Contact struct {
	ID                 uuid.UUID  `json:"id"`
	ProfileID          uuid.UUID  `json:"profile_id"`
	Name               string     `json:"name"`
	Specialty          *string    `json:"specialty,omitempty"`
	Facility           *string    `json:"facility,omitempty"`
	Phone              *string    `json:"phone,omitempty"`
	Email              *string    `json:"email,omitempty"`
	Address            *string    `json:"address,omitempty"`
	Notes              *string    `json:"notes,omitempty"`
	IsEmergencyContact bool       `json:"is_emergency_contact"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
	DeletedAt          *time.Time `json:"-"`
}
