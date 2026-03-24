package handlers

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
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

// HandleDoctorReport generates a medical summary PDF for a profile.
// GET /profiles/{profileID}/export/pdf
func (h *PDFHandler) HandleDoctorReport(w http.ResponseWriter, r *http.Request) {
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

	hasAccess, err := h.profileRepo.HasAccess(r.Context(), profileID, claims.UserID)
	if err != nil || !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	ctx := r.Context()

	// Load profile info
	profile, err := h.loadProfile(ctx, profileID)
	if err != nil {
		h.logger.Error("load profile for pdf", zap.Error(err))
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}

	// Load all data
	medications, err := h.loadActiveMedications(ctx, profileID)
	if err != nil {
		h.logger.Error("load medications for pdf", zap.Error(err))
	}

	allergies, err := h.loadActiveAllergies(ctx, profileID)
	if err != nil {
		h.logger.Error("load allergies for pdf", zap.Error(err))
	}

	diagnoses, err := h.loadActiveDiagnoses(ctx, profileID)
	if err != nil {
		h.logger.Error("load diagnoses for pdf", zap.Error(err))
	}

	vitals, err := h.loadRecentVitals(ctx, profileID)
	if err != nil {
		h.logger.Error("load vitals for pdf", zap.Error(err))
	}

	contacts, err := h.loadEmergencyContacts(ctx, profileID)
	if err != nil {
		h.logger.Error("load emergency contacts for pdf", zap.Error(err))
	}

	// Generate PDF
	now := time.Now().UTC()
	pdf := fpdf.New("P", "mm", "A4", "")
	pdf.SetAutoPageBreak(true, 25)

	// Footer function
	pdf.SetFooterFunc(func() {
		pdf.SetY(-20)
		pdf.SetFont("Helvetica", "I", 8)
		pdf.SetTextColor(128, 128, 128)
		footer := fmt.Sprintf("Generated from HealthVault \u00b7 %s \u00b7 Page %d",
			now.Format("2006-01-02"), pdf.PageNo())
		pdf.CellFormat(0, 10, footer, "", 0, "C", false, 0, "")
	})

	pdf.AddPage()

	// ── Header ──────────────────────────────────────────────────────
	pdf.SetFont("Helvetica", "B", 18)
	pdf.SetTextColor(33, 37, 41)
	pdf.CellFormat(0, 12, "HealthVault", "", 1, "L", false, 0, "")
	pdf.SetFont("Helvetica", "", 12)
	pdf.SetTextColor(100, 100, 100)
	pdf.CellFormat(0, 7, "Medical Summary Report", "", 1, "L", false, 0, "")
	pdf.SetFont("Helvetica", "", 9)
	pdf.CellFormat(0, 5, "Generated: "+now.Format("2006-01-02 15:04 UTC"), "", 1, "L", false, 0, "")
	pdf.Ln(2)

	// Divider
	pdf.SetDrawColor(200, 200, 200)
	pdf.Line(10, pdf.GetY(), 200, pdf.GetY())
	pdf.Ln(6)

	// ── Section 1: Patient Information ──────────────────────────────
	h.pdfSectionHeader(pdf, "1", "Patient Information")

	dob := "N/A"
	if profile.dateOfBirth != nil {
		dob = profile.dateOfBirth.Format("2006-01-02")
	}
	bloodType := "N/A"
	if profile.bloodType != nil {
		bt := *profile.bloodType
		if profile.rhesusFactor != nil {
			bt += *profile.rhesusFactor
		}
		bloodType = bt
	}

	infoData := [][]string{
		{"Name", profile.displayName},
		{"Date of Birth", dob},
		{"Biological Sex", profile.biologicalSex},
		{"Blood Type", bloodType},
	}

	pdf.SetFont("Helvetica", "", 10)
	pdf.SetTextColor(33, 37, 41)
	for _, row := range infoData {
		pdf.SetFont("Helvetica", "B", 10)
		pdf.CellFormat(45, 7, row[0]+":", "", 0, "L", false, 0, "")
		pdf.SetFont("Helvetica", "", 10)
		pdf.CellFormat(0, 7, row[1], "", 1, "L", false, 0, "")
	}
	pdf.Ln(4)

	// ── Section 2: Active Medications ───────────────────────────────
	h.pdfSectionHeader(pdf, "2", "Active Medications")

	if len(medications) == 0 {
		pdf.SetFont("Helvetica", "I", 10)
		pdf.SetTextColor(128, 128, 128)
		pdf.CellFormat(0, 7, "No active medications on record.", "", 1, "L", false, 0, "")
	} else {
		colWidths := []float64{70, 50, 70}
		h.pdfTableHeader(pdf, []string{"Medication", "Dosage", "Frequency"}, colWidths)
		for _, m := range medications {
			h.pdfTableRow(pdf, []string{m.name, m.dosage, m.frequency}, colWidths)
		}
	}
	pdf.Ln(4)

	// ── Section 3: Allergies ────────────────────────────────────────
	h.pdfSectionHeader(pdf, "3", "Allergies")

	if len(allergies) == 0 {
		pdf.SetFont("Helvetica", "I", 10)
		pdf.SetTextColor(128, 128, 128)
		pdf.CellFormat(0, 7, "No active allergies on record.", "", 1, "L", false, 0, "")
	} else {
		colWidths := []float64{70, 60, 60}
		h.pdfTableHeader(pdf, []string{"Allergen", "Category", "Severity"}, colWidths)
		for _, a := range allergies {
			h.pdfTableRow(pdf, []string{a.name, a.category, a.severity}, colWidths)
		}
	}
	pdf.Ln(4)

	// ── Section 4: Active Diagnoses ─────────────────────────────────
	h.pdfSectionHeader(pdf, "4", "Active Diagnoses")

	if len(diagnoses) == 0 {
		pdf.SetFont("Helvetica", "I", 10)
		pdf.SetTextColor(128, 128, 128)
		pdf.CellFormat(0, 7, "No active diagnoses on record.", "", 1, "L", false, 0, "")
	} else {
		colWidths := []float64{80, 50, 60}
		h.pdfTableHeader(pdf, []string{"Diagnosis", "ICD-10", "Status"}, colWidths)
		for _, d := range diagnoses {
			h.pdfTableRow(pdf, []string{d.name, d.icdCode, d.status}, colWidths)
		}
	}
	pdf.Ln(4)

	// ── Section 5: Recent Vitals ────────────────────────────────────
	h.pdfSectionHeader(pdf, "5", "Recent Vitals")

	if len(vitals) == 0 {
		pdf.SetFont("Helvetica", "I", 10)
		pdf.SetTextColor(128, 128, 128)
		pdf.CellFormat(0, 7, "No vitals recorded.", "", 1, "L", false, 0, "")
	} else {
		colWidths := []float64{30, 35, 25, 30, 30, 40}
		h.pdfTableHeader(pdf, []string{"Date", "Blood Pressure", "Pulse", "Weight", "Temp", "SpO2"}, colWidths)
		for _, v := range vitals {
			h.pdfTableRow(pdf, []string{v.date, v.bp, v.pulse, v.weight, v.temp, v.spo2}, colWidths)
		}
	}
	pdf.Ln(4)

	// ── Section 6: Emergency Contacts ───────────────────────────────
	h.pdfSectionHeader(pdf, "6", "Emergency Contacts")

	if len(contacts) == 0 {
		pdf.SetFont("Helvetica", "I", 10)
		pdf.SetTextColor(128, 128, 128)
		pdf.CellFormat(0, 7, "No emergency contacts on record.", "", 1, "L", false, 0, "")
	} else {
		colWidths := []float64{95, 95}
		h.pdfTableHeader(pdf, []string{"Name", "Phone"}, colWidths)
		for _, c := range contacts {
			h.pdfTableRow(pdf, []string{c.name, c.phone}, colWidths)
		}
	}

	// Write PDF to response
	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Disposition",
		fmt.Sprintf("attachment; filename=\"healthvault-report-%s.pdf\"", now.Format("2006-01-02")))

	if err := pdf.Output(w); err != nil {
		h.logger.Error("write pdf output", zap.Error(err))
		return
	}
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
