package user

import (
	"time"

	"github.com/google/uuid"
)

// User represents a HealthVault user account.
type User struct {
	ID                   uuid.UUID  `json:"id"`
	Email                string     `json:"email"`
	DisplayName          string     `json:"display_name"`
	AuthHash             string     `json:"-"`
	PEKSalt              string     `json:"-"`
	AuthSalt             string     `json:"-"`
	IdentityPubkey       string     `json:"identity_pubkey"`
	IdentityPrivkeyEnc   string     `json:"-"`
	SigningPubkey         string     `json:"signing_pubkey"`
	SigningPrivkeyEnc    string     `json:"-"`
	Role                 string     `json:"role"`
	IsDisabled           bool       `json:"is_disabled"`
	TOTPSecretEnc        *string    `json:"-"`
	TOTPEnabled          bool       `json:"totp_enabled"`
	OnboardingCompletedAt *time.Time `json:"onboarding_completed_at,omitempty"`
	CreatedAt            time.Time  `json:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at"`
}

// Session represents an active user session.
type Session struct {
	ID           uuid.UUID  `json:"id"`
	UserID       uuid.UUID  `json:"user_id"`
	JTI          string     `json:"-"`
	DeviceHint   string     `json:"device_hint"`
	IPAddress    string     `json:"ip_address"`
	CreatedAt    time.Time  `json:"created_at"`
	LastActiveAt time.Time  `json:"last_active_at"`
	ExpiresAt    time.Time  `json:"expires_at"`
	RevokedAt    *time.Time `json:"revoked_at,omitempty"`
}

// RecoveryCode represents a single-use account recovery code.
type RecoveryCode struct {
	ID        uuid.UUID  `json:"id"`
	UserID    uuid.UUID  `json:"user_id"`
	CodeHash  string     `json:"-"`
	UsedAt    *time.Time `json:"used_at,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
}

// Preferences holds per-user display and unit preferences.
type Preferences struct {
	UserID           uuid.UUID `json:"user_id"`
	Language         string    `json:"language"`
	DateFormat       string    `json:"date_format"`
	WeightUnit       string    `json:"weight_unit"`
	HeightUnit       string    `json:"height_unit"`
	TemperatureUnit  string    `json:"temperature_unit"`
	BloodGlucoseUnit string   `json:"blood_glucose_unit"`
	WeekStart        string    `json:"week_start"`
	Timezone         string    `json:"timezone"`
}

// StorageInfo holds storage quota information.
type StorageInfo struct {
	UserID           uuid.UUID `json:"user_id"`
	UsedBytes        int64     `json:"used_bytes"`
	QuotaBytes       int64     `json:"quota_bytes"`
	LastCalculatedAt time.Time `json:"last_calculated_at"`
}
