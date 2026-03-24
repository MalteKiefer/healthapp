package diagnoses

import (
	"time"

	"github.com/google/uuid"
)

// DiagnosisStatus represents the current status of a diagnosis.
type DiagnosisStatus string

const (
	StatusActive      DiagnosisStatus = "active"
	StatusResolved    DiagnosisStatus = "resolved"
	StatusChronic     DiagnosisStatus = "chronic"
	StatusInRemission DiagnosisStatus = "in_remission"
	StatusSuspected   DiagnosisStatus = "suspected"
)

// ValidStatuses contains all allowed diagnosis statuses.
var ValidStatuses = map[DiagnosisStatus]bool{
	StatusActive:      true,
	StatusResolved:    true,
	StatusChronic:     true,
	StatusInRemission: true,
	StatusSuspected:   true,
}

// Diagnosis represents a medical diagnosis record.
type Diagnosis struct {
	ID          uuid.UUID       `json:"id"`
	ProfileID   uuid.UUID       `json:"profile_id"`
	Name        string          `json:"name"`
	ICD10Code   *string         `json:"icd10_code,omitempty"`
	Status      DiagnosisStatus `json:"status"`
	DiagnosedAt *time.Time      `json:"diagnosed_at,omitempty"`
	DiagnosedBy *string         `json:"diagnosed_by,omitempty"`
	ResolvedAt  *time.Time      `json:"resolved_at,omitempty"`
	Notes       *string         `json:"notes,omitempty"`
	Version     int             `json:"version"`
	PreviousID  *uuid.UUID      `json:"previous_id,omitempty"`
	IsCurrent   bool            `json:"is_current"`
	CreatedAt   time.Time       `json:"created_at"`
	UpdatedAt   time.Time       `json:"updated_at"`
	DeletedAt   *time.Time      `json:"-"`
}

// ListFilter defines query parameters for listing diagnoses.
type ListFilter struct {
	ProfileID uuid.UUID
	Status    *DiagnosisStatus
	Limit     int
	Offset    int
}
