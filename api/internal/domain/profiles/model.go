package profiles

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// Profile represents a health profile managed by a user.
type Profile struct {
	ID                    uuid.UUID        `json:"id"`
	OwnerUserID           uuid.UUID        `json:"owner_user_id"`
	DisplayName           string           `json:"display_name"`
	DateOfBirth           *time.Time       `json:"date_of_birth,omitempty"`
	BiologicalSex         string           `json:"biological_sex"`
	BloodType             *string          `json:"blood_type,omitempty"`
	RhesusFactor          *string          `json:"rhesus_factor,omitempty"`
	AvatarColor           string           `json:"avatar_color"`
	AvatarImageEnc        []byte           `json:"avatar_image_enc,omitempty"`
	ArchivedAt            *time.Time       `json:"archived_at,omitempty"`
	OnboardingCompletedAt *time.Time       `json:"onboarding_completed_at,omitempty"`
	RotationState         string           `json:"rotation_state"`
	RotationStartedAt     *time.Time       `json:"rotation_started_at,omitempty"`
	RotationProgress      json.RawMessage  `json:"rotation_progress,omitempty"`
	CreatedAt             time.Time        `json:"created_at"`
	UpdatedAt             time.Time        `json:"updated_at"`
}

