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

type acceptConsentRequest struct {
	DocumentID string `json:"document_id"`
}

// HandleAcceptConsent records the authenticated user's acceptance of a specific
// legal document identified by document_id in the request body. Each document
// type (privacy_policy, terms_of_service) must be accepted separately to
// satisfy GDPR requirements for purpose-specific consent.
// POST /api/v1/legal/accept
func (h *LegalHandler) HandleAcceptConsent(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	var req acceptConsentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.DocumentID == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("document_id_required"))
		return
	}

	docID, err := uuid.Parse(req.DocumentID)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_document_id"))
		return
	}

	// Verify the document exists and is currently effective.
	var docType string
	err = h.db.QueryRow(r.Context(),
		`SELECT document_type FROM instance_legal_documents WHERE id = $1 AND effective_from <= NOW()`,
		docID,
	).Scan(&docType)
	if err != nil {
		h.logger.Error("verify legal document", zap.Error(err))
		writeJSON(w, http.StatusNotFound, errorResponse("document_not_found"))
		return
	}

	ip := r.RemoteAddr
	ua := r.UserAgent()

	_, err = h.db.Exec(r.Context(),
		`INSERT INTO user_consent_records (document_id, user_id, ip_address, user_agent, accepted_at)
		 VALUES ($1, $2, $3::inet, $4, NOW())
		 ON CONFLICT DO NOTHING`,
		docID, claims.UserID, ip, ua,
	)
	if err != nil {
		h.logger.Error("insert consent record", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"accepted":      true,
		"document_id":   docID,
		"document_type": docType,
	})
}

// HandlePendingConsent returns the list of legal documents that the
// authenticated user has not yet accepted. Clients use this to display the
// correct acceptance prompts.
// GET /api/v1/legal/pending
func (h *LegalHandler) HandlePendingConsent(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	rows, err := h.db.Query(r.Context(),
		`SELECT d.id, d.document_type, d.version, d.effective_from
		 FROM instance_legal_documents d
		 INNER JOIN (
		     SELECT document_type, MAX(effective_from) AS max_ef
		     FROM instance_legal_documents
		     WHERE effective_from <= NOW()
		     GROUP BY document_type
		 ) latest ON d.document_type = latest.document_type AND d.effective_from = latest.max_ef
		 WHERE d.document_type IN ('privacy_policy', 'terms_of_service')
		   AND NOT EXISTS (
		       SELECT 1 FROM user_consent_records ucr
		       WHERE ucr.document_id = d.id AND ucr.user_id = $1
		   )`,
		claims.UserID,
	)
	if err != nil {
		h.logger.Error("query pending consent", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	type pendingDoc struct {
		ID            uuid.UUID `json:"id"`
		DocumentType  string    `json:"document_type"`
		Version       string    `json:"version"`
		EffectiveFrom time.Time `json:"effective_from"`
	}

	var pending []pendingDoc
	for rows.Next() {
		var d pendingDoc
		if err := rows.Scan(&d.ID, &d.DocumentType, &d.Version, &d.EffectiveFrom); err != nil {
			h.logger.Error("scan pending consent", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		pending = append(pending, d)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate pending consent", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if pending == nil {
		pending = []pendingDoc{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"pending": pending,
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
