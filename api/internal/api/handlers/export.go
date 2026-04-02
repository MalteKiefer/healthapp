package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// ExportHandler handles data export and import endpoints.
type ExportHandler struct {
	db     *pgxpool.Pool
	logger *zap.Logger
}

func NewExportHandler(db *pgxpool.Pool, logger *zap.Logger) *ExportHandler {
	return &ExportHandler{db: db, logger: logger}
}

// HandleExportFHIR exports profile data as a FHIR R4 Bundle.
// GET /profiles/{profileID}/export/fhir
func (h *ExportHandler) HandleExportFHIR(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	profileID, err := uuid.Parse(chi.URLParam(r, "profileID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_profile_id"))
		return
	}

	// Check access via direct DB query (no profile repo dependency)
	var hasAccess bool
	err = h.db.QueryRow(r.Context(),
		`SELECT EXISTS(
			SELECT 1 FROM profiles WHERE id = $1 AND owner_user_id = $2
			UNION ALL
			SELECT 1 FROM profile_key_grants WHERE profile_id = $1 AND grantee_user_id = $2 AND revoked_at IS NULL
		)`, profileID, claims.UserID).Scan(&hasAccess)
	if err != nil || !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	// Load profile metadata
	var displayName string
	var dateOfBirth *time.Time
	var biologicalSex string
	err = h.db.QueryRow(r.Context(),
		`SELECT display_name, date_of_birth, biological_sex FROM profiles WHERE id = $1 AND deleted_at IS NULL`,
		profileID).Scan(&displayName, &dateOfBirth, &biologicalSex)
	if err != nil {
		h.logger.Error("load profile for fhir export", zap.Error(err))
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}

	// Build FHIR Bundle
	bundle := map[string]interface{}{
		"resourceType": "Bundle",
		"type":         "collection",
		"timestamp":    time.Now().UTC().Format(time.RFC3339),
		"entry":        []interface{}{},
	}

	entries := []interface{}{}

	// Patient resource
	patient := map[string]interface{}{
		"resourceType": "Patient",
		"id":           profileID.String(),
		"name":         []map[string]interface{}{{"text": displayName}},
		"gender":       fhirGender(biologicalSex),
	}
	if dateOfBirth != nil {
		patient["birthDate"] = dateOfBirth.Format("2006-01-02")
	}
	entries = append(entries, map[string]interface{}{
		"resource": patient,
	})

	// Vitals as Observation resources
	vitalEntries, err := h.buildVitalObservations(r.Context(), profileID)
	if err != nil {
		h.logger.Error("build vital observations", zap.Error(err))
	} else {
		entries = append(entries, vitalEntries...)
	}

	// Medications as MedicationStatement resources
	medEntries, err := h.buildMedicationStatements(r.Context(), profileID)
	if err != nil {
		h.logger.Error("build medication statements", zap.Error(err))
	} else {
		entries = append(entries, medEntries...)
	}

	// Allergies as AllergyIntolerance resources
	allergyEntries, err := h.buildAllergyIntolerances(r.Context(), profileID)
	if err != nil {
		h.logger.Error("build allergy intolerances", zap.Error(err))
	} else {
		entries = append(entries, allergyEntries...)
	}

	// Diagnoses as Condition resources
	conditionEntries, err := h.buildConditions(r.Context(), profileID)
	if err != nil {
		h.logger.Error("build conditions", zap.Error(err))
	} else {
		entries = append(entries, conditionEntries...)
	}

	bundle["entry"] = entries

	w.Header().Set("Content-Type", "application/fhir+json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(bundle)
}

// HandleImportFHIR is a stub for FHIR import.
// POST /profiles/{profileID}/import/fhir
func (h *ExportHandler) HandleImportFHIR(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, errorResponse("not_implemented"))
}

// HandleExportICS is a stub for ICS calendar export.
// GET /profiles/{profileID}/export/ics
func (h *ExportHandler) HandleExportICS(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, errorResponse("not_implemented"))
}

// HandleExport is a stub for generic export.
// POST /export
func (h *ExportHandler) HandleExport(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, errorResponse("not_implemented"))
}

// HandleScheduleExport is a stub for scheduled export.
// POST /export/schedule
func (h *ExportHandler) HandleScheduleExport(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, errorResponse("not_implemented"))
}

// ── FHIR Resource Builders ──────────────────────────────────────────

func (h *ExportHandler) buildVitalObservations(ctx context.Context, profileID uuid.UUID) ([]interface{}, error) {
	rows, err := h.db.Query(ctx,
		`SELECT id, measured_at,
			blood_pressure_systolic, blood_pressure_diastolic,
			pulse, oxygen_saturation, body_temperature,
			weight, height, blood_glucose, respiratory_rate
		FROM vitals
		WHERE profile_id = $1 AND deleted_at IS NULL
		ORDER BY measured_at DESC
		LIMIT 500`, profileID)
	if err != nil {
		return nil, fmt.Errorf("query vitals: %w", err)
	}
	defer rows.Close()

	var entries []interface{}
	for rows.Next() {
		var (
			id          uuid.UUID
			measuredAt  time.Time
			systolic    *float64
			diastolic   *float64
			pulse       *float64
			spo2        *float64
			temperature *float64
			weight      *float64
			height      *float64
			glucose     *float64
			respRate    *float64
		)
		if err := rows.Scan(&id, &measuredAt, &systolic, &diastolic,
			&pulse, &spo2, &temperature, &weight, &height, &glucose, &respRate); err != nil {
			continue
		}

		addObs := func(code, display, unit string, value *float64) {
			if value == nil {
				return
			}
			obs := map[string]interface{}{
				"resourceType": "Observation",
				"id":           id.String() + "-" + code,
				"status":       "final",
				"code": map[string]interface{}{
					"coding": []map[string]interface{}{
						{"system": "http://loinc.org", "code": code, "display": display},
					},
				},
				"effectiveDateTime": measuredAt.Format(time.RFC3339),
				"subject":           map[string]string{"reference": "Patient/" + profileID.String()},
				"valueQuantity": map[string]interface{}{
					"value": *value,
					"unit":  unit,
				},
			}
			entries = append(entries, map[string]interface{}{"resource": obs})
		}

		addObs("8480-6", "Systolic blood pressure", "mmHg", systolic)
		addObs("8462-4", "Diastolic blood pressure", "mmHg", diastolic)
		addObs("8867-4", "Heart rate", "/min", pulse)
		addObs("2708-6", "Oxygen saturation", "%", spo2)
		addObs("8310-5", "Body temperature", "Cel", temperature)
		addObs("29463-7", "Body weight", "kg", weight)
		addObs("8302-2", "Body height", "cm", height)
		addObs("2339-0", "Glucose", "mmol/L", glucose)
		addObs("9279-1", "Respiratory rate", "/min", respRate)
	}

	return entries, nil
}

func (h *ExportHandler) buildMedicationStatements(ctx context.Context, profileID uuid.UUID) ([]interface{}, error) {
	rows, err := h.db.Query(ctx,
		`SELECT id, name, dosage, frequency, started_at, ended_at, notes
		FROM medications
		WHERE profile_id = $1 AND deleted_at IS NULL
		ORDER BY started_at DESC
		LIMIT 500`, profileID)
	if err != nil {
		return nil, fmt.Errorf("query medications: %w", err)
	}
	defer rows.Close()

	var entries []interface{}
	for rows.Next() {
		var (
			id        uuid.UUID
			name      string
			dosage    *string
			frequency *string
			startedAt *time.Time
			endedAt   *time.Time
			notes     *string
		)
		if err := rows.Scan(&id, &name, &dosage, &frequency, &startedAt, &endedAt, &notes); err != nil {
			continue
		}

		status := "active"
		if endedAt != nil {
			status = "completed"
		}

		stmt := map[string]interface{}{
			"resourceType": "MedicationStatement",
			"id":           id.String(),
			"status":       status,
			"medicationCodeableConcept": map[string]interface{}{
				"text": name,
			},
			"subject": map[string]string{"reference": "Patient/" + profileID.String()},
		}

		if dosage != nil {
			stmt["dosage"] = []map[string]interface{}{
				{"text": *dosage},
			}
		}
		if startedAt != nil {
			period := map[string]string{"start": startedAt.Format("2006-01-02")}
			if endedAt != nil {
				period["end"] = endedAt.Format("2006-01-02")
			}
			stmt["effectivePeriod"] = period
		}
		if notes != nil {
			stmt["note"] = []map[string]string{{"text": *notes}}
		}

		entries = append(entries, map[string]interface{}{"resource": stmt})
	}

	return entries, nil
}

func (h *ExportHandler) buildAllergyIntolerances(ctx context.Context, profileID uuid.UUID) ([]interface{}, error) {
	rows, err := h.db.Query(ctx,
		`SELECT id, allergen, reaction, severity, diagnosed_at, notes
		FROM allergies
		WHERE profile_id = $1 AND deleted_at IS NULL
		ORDER BY diagnosed_at DESC NULLS LAST
		LIMIT 500`, profileID)
	if err != nil {
		return nil, fmt.Errorf("query allergies: %w", err)
	}
	defer rows.Close()

	var entries []interface{}
	for rows.Next() {
		var (
			id          uuid.UUID
			allergen    string
			reaction    *string
			severity    *string
			diagnosedAt *time.Time
			notes       *string
		)
		if err := rows.Scan(&id, &allergen, &reaction, &severity, &diagnosedAt, &notes); err != nil {
			continue
		}

		ai := map[string]interface{}{
			"resourceType":   "AllergyIntolerance",
			"id":             id.String(),
			"clinicalStatus": map[string]interface{}{"coding": []map[string]string{{"code": "active"}}},
			"code":           map[string]interface{}{"text": allergen},
			"patient":        map[string]string{"reference": "Patient/" + profileID.String()},
		}

		if reaction != nil {
			reactionEntry := map[string]interface{}{
				"manifestation": []map[string]interface{}{
					{"text": *reaction},
				},
			}
			if severity != nil {
				reactionEntry["severity"] = *severity
			}
			ai["reaction"] = []interface{}{reactionEntry}
		}
		if diagnosedAt != nil {
			ai["onsetDateTime"] = diagnosedAt.Format("2006-01-02")
		}
		if notes != nil {
			ai["note"] = []map[string]string{{"text": *notes}}
		}

		entries = append(entries, map[string]interface{}{"resource": ai})
	}

	return entries, nil
}

func (h *ExportHandler) buildConditions(ctx context.Context, profileID uuid.UUID) ([]interface{}, error) {
	rows, err := h.db.Query(ctx,
		`SELECT id, name, icd_code, status, diagnosed_at, resolved_at, notes
		FROM diagnoses
		WHERE profile_id = $1 AND deleted_at IS NULL
		ORDER BY diagnosed_at DESC NULLS LAST
		LIMIT 500`, profileID)
	if err != nil {
		return nil, fmt.Errorf("query diagnoses: %w", err)
	}
	defer rows.Close()

	var entries []interface{}
	for rows.Next() {
		var (
			id          uuid.UUID
			name        string
			icdCode     *string
			status      *string
			diagnosedAt *time.Time
			resolvedAt  *time.Time
			notes       *string
		)
		if err := rows.Scan(&id, &name, &icdCode, &status, &diagnosedAt, &resolvedAt, &notes); err != nil {
			continue
		}

		clinicalStatus := "active"
		if resolvedAt != nil {
			clinicalStatus = "resolved"
		} else if status != nil {
			clinicalStatus = *status
		}

		cond := map[string]interface{}{
			"resourceType":   "Condition",
			"id":             id.String(),
			"clinicalStatus": map[string]interface{}{"coding": []map[string]string{{"code": clinicalStatus}}},
			"code":           map[string]interface{}{"text": name},
			"subject":        map[string]string{"reference": "Patient/" + profileID.String()},
		}

		if icdCode != nil {
			cond["code"] = map[string]interface{}{
				"coding": []map[string]interface{}{
					{"system": "http://hl7.org/fhir/sid/icd-10", "code": *icdCode, "display": name},
				},
				"text": name,
			}
		}
		if diagnosedAt != nil {
			cond["onsetDateTime"] = diagnosedAt.Format("2006-01-02")
		}
		if resolvedAt != nil {
			cond["abatementDateTime"] = resolvedAt.Format("2006-01-02")
		}
		if notes != nil {
			cond["note"] = []map[string]string{{"text": *notes}}
		}

		entries = append(entries, map[string]interface{}{"resource": cond})
	}

	return entries, nil
}

func fhirGender(biologicalSex string) string {
	switch biologicalSex {
	case "male":
		return "male"
	case "female":
		return "female"
	case "other":
		return "other"
	default:
		return "unknown"
	}
}
