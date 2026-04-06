package handlers

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/go-pdf/fpdf"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
)

// PDFHandler generates doctor-ready PDF reports.
type PDFHandler struct {
	db          *pgxpool.Pool
	profileRepo profiles.Repository
	logger      *zap.Logger
}

// NewPDFHandler creates a new PDFHandler.
func NewPDFHandler(db *pgxpool.Pool, pr profiles.Repository, logger *zap.Logger) *PDFHandler {
	return &PDFHandler{db: db, profileRepo: pr, logger: logger}
}

// HandleDoctorReport is deprecated — PDF reports are now generated client-side.
func (h *PDFHandler) HandleDoctorReport(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{
		"error":   "endpoint_removed",
		"message": "This endpoint has been removed. Use client-side rendering instead.",
	})
}

// ── PDF helpers ─────────────────────────────────────────────────────

func (h *PDFHandler) pdfSectionHeader(pdf *fpdf.Fpdf, number, title string) {
	pdf.SetFont("Helvetica", "B", 13)
	pdf.SetTextColor(33, 37, 41)
	pdf.CellFormat(0, 9, number+". "+title, "", 1, "L", false, 0, "")
	pdf.Ln(1)
}

func (h *PDFHandler) pdfTableHeader(pdf *fpdf.Fpdf, headers []string, widths []float64) {
	pdf.SetFont("Helvetica", "B", 9)
	pdf.SetFillColor(240, 240, 240)
	pdf.SetTextColor(33, 37, 41)
	for i, header := range headers {
		pdf.CellFormat(widths[i], 7, header, "1", 0, "L", true, 0, "")
	}
	pdf.Ln(-1)
}

func (h *PDFHandler) pdfTableRow(pdf *fpdf.Fpdf, cells []string, widths []float64) {
	pdf.SetFont("Helvetica", "", 9)
	pdf.SetTextColor(60, 60, 60)
	for i, cell := range cells {
		pdf.CellFormat(widths[i], 6, cell, "1", 0, "L", false, 0, "")
	}
	pdf.Ln(-1)
}

// ── Data types for PDF content ──────────────────────────────────────

type pdfProfile struct {
	displayName   string
	dateOfBirth   *time.Time
	biologicalSex string
	bloodType     *string
	rhesusFactor  *string
}

type pdfMedication struct {
	name      string
	dosage    string
	frequency string
}

type pdfAllergy struct {
	name     string
	category string
	severity string
}

type pdfDiagnosis struct {
	name    string
	icdCode string
	status  string
}

type pdfVital struct {
	date   string
	bp     string
	pulse  string
	weight string
	temp   string
	spo2   string
}

type pdfContact struct {
	name  string
	phone string
}

// ── Data loaders ────────────────────────────────────────────────────

func (h *PDFHandler) loadProfile(ctx context.Context, profileID uuid.UUID) (*pdfProfile, error) {
	var p pdfProfile
	err := h.db.QueryRow(ctx,
		`SELECT display_name, date_of_birth, biological_sex, blood_type, rhesus_factor
		FROM profiles WHERE id = $1 AND deleted_at IS NULL`,
		profileID).Scan(&p.displayName, &p.dateOfBirth, &p.biologicalSex, &p.bloodType, &p.rhesusFactor)
	if err != nil {
		return nil, fmt.Errorf("query profile: %w", err)
	}
	return &p, nil
}

func (h *PDFHandler) loadActiveMedications(ctx context.Context, profileID uuid.UUID) ([]pdfMedication, error) {
	rows, err := h.db.Query(ctx,
		`SELECT name, dosage, frequency
		FROM medications
		WHERE profile_id = $1 AND ended_at IS NULL AND deleted_at IS NULL AND is_current = TRUE
		ORDER BY name`, profileID)
	if err != nil {
		return nil, fmt.Errorf("query medications: %w", err)
	}
	defer rows.Close()

	var result []pdfMedication
	for rows.Next() {
		var (
			name      string
			dosage    *string
			frequency *string
		)
		if err := rows.Scan(&name, &dosage, &frequency); err != nil {
			continue
		}
		result = append(result, pdfMedication{
			name:      name,
			dosage:    ptrStr(dosage),
			frequency: ptrStr(frequency),
		})
	}
	return result, nil
}

func (h *PDFHandler) loadActiveAllergies(ctx context.Context, profileID uuid.UUID) ([]pdfAllergy, error) {
	rows, err := h.db.Query(ctx,
		`SELECT name, category, severity
		FROM allergies
		WHERE profile_id = $1 AND status = 'active' AND deleted_at IS NULL AND is_current = TRUE
		ORDER BY name`, profileID)
	if err != nil {
		return nil, fmt.Errorf("query allergies: %w", err)
	}
	defer rows.Close()

	var result []pdfAllergy
	for rows.Next() {
		var (
			name     string
			category *string
			severity *string
		)
		if err := rows.Scan(&name, &category, &severity); err != nil {
			continue
		}
		result = append(result, pdfAllergy{
			name:     name,
			category: ptrStr(category),
			severity: ptrStr(severity),
		})
	}
	return result, nil
}

func (h *PDFHandler) loadActiveDiagnoses(ctx context.Context, profileID uuid.UUID) ([]pdfDiagnosis, error) {
	rows, err := h.db.Query(ctx,
		`SELECT name, icd10_code, status
		FROM diagnoses
		WHERE profile_id = $1 AND status IN ('active', 'chronic') AND deleted_at IS NULL AND is_current = TRUE
		ORDER BY name`, profileID)
	if err != nil {
		return nil, fmt.Errorf("query diagnoses: %w", err)
	}
	defer rows.Close()

	var result []pdfDiagnosis
	for rows.Next() {
		var (
			name    string
			icdCode *string
			status  string
		)
		if err := rows.Scan(&name, &icdCode, &status); err != nil {
			continue
		}
		result = append(result, pdfDiagnosis{
			name:    name,
			icdCode: ptrStr(icdCode),
			status:  status,
		})
	}
	return result, nil
}

func (h *PDFHandler) loadRecentVitals(ctx context.Context, profileID uuid.UUID) ([]pdfVital, error) {
	rows, err := h.db.Query(ctx,
		`SELECT measured_at,
			blood_pressure_systolic, blood_pressure_diastolic,
			pulse, weight, body_temperature, oxygen_saturation
		FROM vitals
		WHERE profile_id = $1 AND deleted_at IS NULL
		ORDER BY measured_at DESC
		LIMIT 10`, profileID)
	if err != nil {
		return nil, fmt.Errorf("query vitals: %w", err)
	}
	defer rows.Close()

	var result []pdfVital
	for rows.Next() {
		var (
			measuredAt time.Time
			systolic   *int
			diastolic  *int
			pulse      *int
			weight     *float64
			temp       *float64
			spo2       *float64
		)
		if err := rows.Scan(&measuredAt, &systolic, &diastolic, &pulse, &weight, &temp, &spo2); err != nil {
			continue
		}

		bp := "-"
		if systolic != nil && diastolic != nil {
			bp = fmt.Sprintf("%d/%d", *systolic, *diastolic)
		}
		pulseStr := "-"
		if pulse != nil {
			pulseStr = fmt.Sprintf("%d", *pulse)
		}
		weightStr := "-"
		if weight != nil {
			weightStr = fmt.Sprintf("%.1f kg", *weight)
		}
		tempStr := "-"
		if temp != nil {
			tempStr = fmt.Sprintf("%.1f C", *temp)
		}
		spo2Str := "-"
		if spo2 != nil {
			spo2Str = fmt.Sprintf("%.0f%%", *spo2)
		}

		result = append(result, pdfVital{
			date:   measuredAt.Format("2006-01-02"),
			bp:     bp,
			pulse:  pulseStr,
			weight: weightStr,
			temp:   tempStr,
			spo2:   spo2Str,
		})
	}
	return result, nil
}

func (h *PDFHandler) loadEmergencyContacts(ctx context.Context, profileID uuid.UUID) ([]pdfContact, error) {
	rows, err := h.db.Query(ctx,
		`SELECT name, phone
		FROM medical_contacts
		WHERE profile_id = $1 AND is_emergency_contact = TRUE AND deleted_at IS NULL
		ORDER BY name`, profileID)
	if err != nil {
		return nil, fmt.Errorf("query emergency contacts: %w", err)
	}
	defer rows.Close()

	var result []pdfContact
	for rows.Next() {
		var (
			name  string
			phone *string
		)
		if err := rows.Scan(&name, &phone); err != nil {
			continue
		}
		result = append(result, pdfContact{
			name:  name,
			phone: ptrStr(phone),
		})
	}
	return result, nil
}

// ptrStr safely dereferences a *string, returning "-" if nil.
func ptrStr(s *string) string {
	if s == nil {
		return "-"
	}
	return *s
}
