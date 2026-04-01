package contacts

import (
	"strings"
	"time"

	"github.com/google/uuid"
)

type Contact struct {
	ID                 uuid.UUID  `json:"id"`
	ProfileID          uuid.UUID  `json:"profile_id"`
	ContactType        string     `json:"contact_type"`
	Name               string     `json:"name"`
	Specialty          *string    `json:"specialty,omitempty"`
	Facility           *string    `json:"facility,omitempty"`
	Phone              *string    `json:"phone,omitempty"`
	Email              *string    `json:"email,omitempty"`
	Street             *string    `json:"street,omitempty"`
	PostalCode         *string    `json:"postal_code,omitempty"`
	City               *string    `json:"city,omitempty"`
	Country            *string    `json:"country,omitempty"`
	Latitude           *float64   `json:"latitude,omitempty"`
	Longitude          *float64   `json:"longitude,omitempty"`
	Address            *string    `json:"address,omitempty"`
	Notes              *string    `json:"notes,omitempty"`
	IsEmergencyContact bool       `json:"is_emergency_contact"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
	DeletedAt          *time.Time `json:"-"`
}

func (c *Contact) ComputeAddress() {
	var parts []string
	if c.Street != nil && *c.Street != "" {
		parts = append(parts, *c.Street)
	}
	if c.PostalCode != nil && *c.PostalCode != "" {
		parts = append(parts, *c.PostalCode)
	}
	if c.City != nil && *c.City != "" {
		parts = append(parts, *c.City)
	}
	if c.Country != nil && *c.Country != "" {
		parts = append(parts, *c.Country)
	}
	if len(parts) > 0 {
		addr := strings.Join(parts, ", ")
		c.Address = &addr
	} else {
		c.Address = nil
	}
}
