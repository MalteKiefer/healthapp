package notifications

import (
	"time"

	"github.com/google/uuid"
)

// Notification represents a single notification sent to a user.
type Notification struct {
	ID        uuid.UUID              `json:"id"`
	UserID    uuid.UUID              `json:"user_id"`
	Type      string                 `json:"type"`
	Title     string                 `json:"title"`
	Body      string                 `json:"body"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
	ReadAt    *time.Time             `json:"read_at,omitempty"`
	CreatedAt time.Time              `json:"created_at"`
}

// NotificationPreferences controls which notification types a user receives.
type NotificationPreferences struct {
	UserID               uuid.UUID `json:"user_id"`
	VaccinationDue       bool      `json:"vaccination_due"`
	VaccinationDueDays   int       `json:"vaccination_due_days"`
	MedicationReminder   bool      `json:"medication_reminder"`
	LabResultAbnormal    bool      `json:"lab_result_abnormal"`
	EmergencyAccess      bool      `json:"emergency_access"`
	ExportReady          bool      `json:"export_ready"`
	FamilyInvite         bool      `json:"family_invite"`
	KeyRotationRequired  bool      `json:"key_rotation_required"`
	SessionNew           bool      `json:"session_new"`
	StorageQuotaWarning  bool      `json:"storage_quota_warning"`
}

// ListFilter defines query parameters for listing notifications.
type ListFilter struct {
	UserID uuid.UUID
	Limit  int
	Offset int
}
