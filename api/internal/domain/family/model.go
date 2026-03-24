package family

import (
	"time"

	"github.com/google/uuid"
)

// Family represents a family group in HealthVault.
type Family struct {
	ID          uuid.UUID  `json:"id"`
	Name        string     `json:"name"`
	CreatedBy   uuid.UUID  `json:"created_by"`
	DissolvedAt *time.Time `json:"dissolved_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// FamilyMembership represents a user's membership in a family.
type FamilyMembership struct {
	ID       uuid.UUID  `json:"id"`
	UserID   uuid.UUID  `json:"user_id"`
	FamilyID uuid.UUID  `json:"family_id"`
	Role     string     `json:"role"` // "owner", "admin", "member"
	JoinedAt time.Time  `json:"joined_at"`
	LeftAt   *time.Time `json:"left_at,omitempty"`
}

// FamilyInvite represents an invitation to join a family.
type FamilyInvite struct {
	ID        uuid.UUID  `json:"id"`
	FamilyID  uuid.UUID  `json:"family_id"`
	Token     string     `json:"token"`
	CreatedBy uuid.UUID  `json:"created_by"`
	ExpiresAt time.Time  `json:"expires_at"`
	UsedAt    *time.Time `json:"used_at,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
}
