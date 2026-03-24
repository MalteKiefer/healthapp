package vitals

import (
	"time"

	"github.com/google/uuid"
)

// Vital represents a single vital signs measurement.
type Vital struct {
	ID                     uuid.UUID  `json:"id"`
	ProfileID              uuid.UUID  `json:"profile_id"`
	BloodPressureSystolic  *int       `json:"blood_pressure_systolic,omitempty"`
	BloodPressureDiastolic *int       `json:"blood_pressure_diastolic,omitempty"`
	Pulse                  *int       `json:"pulse,omitempty"`
	OxygenSaturation       *float64   `json:"oxygen_saturation,omitempty"`
	Weight                 *float64   `json:"weight,omitempty"`
	Height                 *float64   `json:"height,omitempty"`
	BodyTemperature        *float64   `json:"body_temperature,omitempty"`
	BloodGlucose           *float64   `json:"blood_glucose,omitempty"`
	RespiratoryRate        *int       `json:"respiratory_rate,omitempty"`
	WaistCircumference     *float64   `json:"waist_circumference,omitempty"`
	HipCircumference       *float64   `json:"hip_circumference,omitempty"`
	BodyFatPercentage      *float64   `json:"body_fat_percentage,omitempty"`
	BMI                    *float64   `json:"bmi,omitempty"`
	SleepDurationMinutes   *int       `json:"sleep_duration_minutes,omitempty"`
	SleepQuality           *int       `json:"sleep_quality,omitempty"`
	MeasuredAt             time.Time  `json:"measured_at"`
	Device                 *string    `json:"device,omitempty"`
	Notes                  *string    `json:"notes,omitempty"`
	CreatedAt              time.Time  `json:"created_at"`
	UpdatedAt              time.Time  `json:"updated_at"`
	DeletedAt              *time.Time `json:"-"`
}

// CalculateBMI computes BMI from weight (kg) and height (cm) if both are present.
func (v *Vital) CalculateBMI() {
	if v.Weight != nil && v.Height != nil && *v.Height > 0 {
		heightM := *v.Height / 100.0
		bmi := *v.Weight / (heightM * heightM)
		// Round to 1 decimal
		rounded := float64(int(bmi*10)) / 10
		v.BMI = &rounded
	}
}

// ChartPoint is a time-series data point for chart aggregation.
type ChartPoint struct {
	MeasuredAt time.Time              `json:"measured_at"`
	Values     map[string]interface{} `json:"values"`
}

// ListFilter defines query parameters for listing vitals.
type ListFilter struct {
	ProfileID uuid.UUID
	From      *time.Time
	To        *time.Time
	Limit     int
	Offset    int
}
