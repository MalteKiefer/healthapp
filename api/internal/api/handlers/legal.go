package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// LegalHandler handles admin legal document and consent endpoints.
type LegalHandler struct {
	db     *pgxpool.Pool
	logger *zap.Logger
}

// NewLegalHandler creates a new LegalHandler.
func NewLegalHandler(db *pgxpool.Pool, logger *zap.Logger) *LegalHandler {
	return &LegalHandler{db: db, logger: logger}
}

// ── Response / Request Types ────────────────────────────────────────

type legalDocument struct {
	ID            uuid.UUID `json:"id"`
	DocumentType  string    `json:"document_type"`
	Version       string    `json:"version"`
	ContentHTML   string    `json:"content_html"`
	EffectiveFrom time.Time `json:"effective_from"`
	CreatedAt     time.Time `json:"created_at"`
}

type consentRecord struct {
	ID         uuid.UUID `json:"id"`
	UserID     uuid.UUID `json:"user_id"`
	DocumentID uuid.UUID `json:"document_id"`
	AcceptedAt time.Time `json:"accepted_at"`
	IPAddress  *string   `json:"ip_address,omitempty"`
	UserAgent  *string   `json:"user_agent,omitempty"`
}

type createLegalDocumentRequest struct {
	DocumentType  string `json:"document_type"`
	Version       string `json:"version"`
	ContentHTML   string `json:"content_html"`
	EffectiveFrom string `json:"effective_from,omitempty"`
}

// ── Handlers ────────────────────────────────────────────────────────

// HandleListDocuments returns all legal documents.
// GET /admin/legal
func (h *LegalHandler) HandleListDocuments(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	rows, err := h.db.Query(r.Context(),
		`SELECT id, document_type, version, content_html, effective_from, created_at
		 FROM instance_legal_documents
		 ORDER BY created_at DESC`,
	)
	if err != nil {
		h.logger.Error("list legal documents", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	var docs []legalDocument
	for rows.Next() {
		var d legalDocument
		if err := rows.Scan(&d.ID, &d.DocumentType, &d.Version, &d.ContentHTML, &d.EffectiveFrom, &d.CreatedAt); err != nil {
			h.logger.Error("scan legal document", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		docs = append(docs, d)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate legal documents", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if docs == nil {
		docs = []legalDocument{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": docs,
	})
}

// HandleCreateDocument inserts a new legal document version.
// POST /admin/legal
func (h *LegalHandler) HandleCreateDocument(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	var req createLegalDocumentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.DocumentType == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("document_type_required"))
		return
	}
	if req.DocumentType != "privacy_policy" && req.DocumentType != "terms_of_service" {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_document_type"))
		return
	}
	if req.Version == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("version_required"))
		return
	}
	if req.ContentHTML == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("content_html_required"))
		return
	}

	effectiveFrom := time.Now().UTC()
	if req.EffectiveFrom != "" {
		parsed, err := time.Parse(time.RFC3339, req.EffectiveFrom)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, errorResponse("invalid_effective_from"))
			return
		}
		effectiveFrom = parsed.UTC()
	}

	var id uuid.UUID
	err := h.db.QueryRow(r.Context(),
		`INSERT INTO instance_legal_documents (document_type, version, content_html, effective_from)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id`,
		req.DocumentType, req.Version, req.ContentHTML, effectiveFrom,
	).Scan(&id)
	if err != nil {
		h.logger.Error("create legal document", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{
		"id":             id,
		"document_type":  req.DocumentType,
		"version":        req.Version,
		"effective_from": effectiveFrom,
	})
}

// HandleListConsentRecords returns all user consent records.
// GET /admin/legal/consent-records
func (h *LegalHandler) HandleListConsentRecords(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	rows, err := h.db.Query(r.Context(),
		`SELECT id, user_id, document_id, accepted_at, ip_address::TEXT, user_agent
		 FROM user_consent_records
		 ORDER BY accepted_at DESC`,
	)
	if err != nil {
		h.logger.Error("list consent records", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	var records []consentRecord
	for rows.Next() {
		var cr consentRecord
		if err := rows.Scan(&cr.ID, &cr.UserID, &cr.DocumentID, &cr.AcceptedAt, &cr.IPAddress, &cr.UserAgent); err != nil {
			h.logger.Error("scan consent record", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		records = append(records, cr)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate consent records", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if records == nil {
		records = []consentRecord{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": records,
	})
}

// HandleGetUserConsent returns consent records for a specific user.
// GET /admin/legal/consent-records/{userID}
func (h *LegalHandler) HandleGetUserConsent(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	userID, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_user_id"))
		return
	}

	rows, err := h.db.Query(r.Context(),
		`SELECT id, user_id, document_id, accepted_at, ip_address::TEXT, user_agent
		 FROM user_consent_records
		 WHERE user_id = $1
		 ORDER BY accepted_at DESC`,
		userID,
	)
	if err != nil {
		h.logger.Error("query user consent", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	var records []consentRecord
	for rows.Next() {
		var cr consentRecord
		if err := rows.Scan(&cr.ID, &cr.UserID, &cr.DocumentID, &cr.AcceptedAt, &cr.IPAddress, &cr.UserAgent); err != nil {
			h.logger.Error("scan user consent record", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		records = append(records, cr)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate user consent", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if records == nil {
		records = []consentRecord{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items":   records,
		"user_id": userID,
	})
}
