package handlers

import (
	"net/http"
)

// ReferenceRangeHandler serves hardcoded reference ranges for common lab markers.
type ReferenceRangeHandler struct{}

func NewReferenceRangeHandler() *ReferenceRangeHandler {
	return &ReferenceRangeHandler{}
}

type referenceRange struct {
	Marker string  `json:"marker"`
	Unit   string  `json:"unit"`
	Low    float64 `json:"low"`
	High   float64 `json:"high"`
	Notes  string  `json:"notes,omitempty"`
}

// HandleList returns hardcoded reference ranges for common markers.
// GET /reference-ranges
func (h *ReferenceRangeHandler) HandleList(w http.ResponseWriter, r *http.Request) {
	ranges := []referenceRange{
		{Marker: "Hemoglobin", Unit: "g/dL", Low: 12.0, High: 17.5, Notes: "Adult range; varies by sex"},
		{Marker: "Glucose (fasting)", Unit: "mg/dL", Low: 70, High: 100},
		{Marker: "Total Cholesterol", Unit: "mg/dL", Low: 0, High: 200, Notes: "Desirable < 200"},
		{Marker: "LDL Cholesterol", Unit: "mg/dL", Low: 0, High: 100, Notes: "Optimal < 100"},
		{Marker: "HDL Cholesterol", Unit: "mg/dL", Low: 40, High: 60, Notes: "> 60 considered protective"},
		{Marker: "Triglycerides", Unit: "mg/dL", Low: 0, High: 150, Notes: "Normal < 150"},
		{Marker: "Creatinine", Unit: "mg/dL", Low: 0.6, High: 1.2, Notes: "Adult range; varies by sex"},
		{Marker: "TSH", Unit: "mIU/L", Low: 0.4, High: 4.0},
		{Marker: "HbA1c", Unit: "%", Low: 4.0, High: 5.6, Notes: "Normal < 5.7; prediabetes 5.7-6.4"},
		{Marker: "White Blood Cell Count", Unit: "x10^3/uL", Low: 4.5, High: 11.0},
		{Marker: "Platelet Count", Unit: "x10^3/uL", Low: 150, High: 400},
		{Marker: "ALT", Unit: "U/L", Low: 7, High: 56},
		{Marker: "AST", Unit: "U/L", Low: 10, High: 40},
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": ranges,
	})
}
