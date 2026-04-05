package labs

import (
	"time"

	"github.com/google/uuid"
)

// LabResult represents a set of laboratory test results for a profile.
type LabResult struct {
	ID         uuid.UUID  `json:"id"`
	ProfileID  uuid.UUID  `json:"profile_id"`
	LabName    *string    `json:"lab_name,omitempty"`
	OrderedBy  *string    `json:"ordered_by,omitempty"`
	SampleDate time.Time  `json:"sample_date"`
	ResultDate *time.Time `json:"result_date,omitempty"`
	Notes      *string    `json:"notes,omitempty"`
	Values     []LabValue `json:"values"`
	Version    int        `json:"version"`
	PreviousID *uuid.UUID `json:"-"`
	IsCurrent  bool       `json:"-"`
	CreatedAt  time.Time  `json:"created_at"`
	UpdatedAt  time.Time  `json:"updated_at"`
	DeletedAt  *time.Time `json:"-"`
	// ContentEnc holds the AES-GCM-encrypted JSON blob of all health fields
	// (produced client-side with the profile key). During Stage 2 lazy
	// migration it lives alongside the plaintext columns; Stage 2.4 drops
	// the plaintext columns and enforces NOT NULL.
	ContentEnc *string `json:"content_enc,omitempty"`
}

// LabValue represents a single marker measurement within a lab result.
type LabValue struct {
	ID            uuid.UUID `json:"id"`
	LabResultID   uuid.UUID `json:"lab_result_id"`
	Marker        string    `json:"marker"`
	Value         *float64  `json:"value,omitempty"`
	ValueText     *string   `json:"value_text,omitempty"`
	Unit          *string   `json:"unit,omitempty"`
	ReferenceLow  *float64  `json:"reference_low,omitempty"`
	ReferenceHigh *float64  `json:"reference_high,omitempty"`
	Flag          *string   `json:"flag,omitempty"`
	// ContentEnc holds the AES-GCM-encrypted JSON blob of all health fields
	// (produced client-side with the profile key). During Stage 2 lazy
	// migration it lives alongside the plaintext columns; Stage 2.4 drops
	// the plaintext columns and enforces NOT NULL.
	ContentEnc *string `json:"content_enc,omitempty"`
}

// TrendDataPoint represents a single measurement of a marker over time.
type TrendDataPoint struct {
	Date  time.Time `json:"date"`
	Value float64   `json:"value"`
	Flag  *string   `json:"flag,omitempty"`
}

// MarkerTrend represents the time series for a single lab marker.
type MarkerTrend struct {
	Marker        string           `json:"marker"`
	Unit          *string          `json:"unit,omitempty"`
	ReferenceLow  *float64         `json:"reference_low,omitempty"`
	ReferenceHigh *float64         `json:"reference_high,omitempty"`
	DataPoints    []TrendDataPoint `json:"data_points"`
}
