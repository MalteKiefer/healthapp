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
}

// ReferenceRange holds standard reference range information for a lab marker.
type ReferenceRange struct {
	Low    float64 `json:"low"`
	High   float64 `json:"high"`
	Unit   string  `json:"unit"`
	Source string  `json:"source"`
	Notes  string  `json:"notes"`
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
