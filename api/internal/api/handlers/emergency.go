package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// EmergencyHandler handles emergency access endpoints.
type EmergencyHandler struct {
	db     *pgxpool.Pool
	logger *zap.Logger
}

func NewEmergencyHandler(db *pgxpool.Pool, logger *zap.Logger) *EmergencyHandler {
	return &EmergencyHandler{db: db, logger: logger}
}

// ── Request/Response Types ──────────────────────────────────────────

type configureEmergencyAccessRequest struct {
	EmergencyContactUserID string   `json:"emergency_contact_user_id"`
	WaitHours              int      `json:"wait_hours"`
	DataFields             []string `json:"data_fields"`
	Message                string   `json:"message"`
}

type emergencyAccessConfig struct {
	ID                     uuid.UUID `json:"id"`
	ProfileID              uuid.UUID `json:"profile_id"`
	Enabled                bool      `json:"enabled"`
	EmergencyContactUserID uuid.UUID `json:"emergency_contact_user_id"`
	WaitHours              int       `json:"wait_hours"`
	DataFields             []string  `json:"data_fields"`
	Message                *string   `json:"message"`
	CreatedAt              time.Time `json:"created_at"`
	UpdatedAt              time.Time `json:"updated_at"`
}

type emergencyAccessRequest struct {
	ID            uuid.UUID  `json:"id"`
	ProfileID     uuid.UUID  `json:"profile_id"`
	RequesterID   uuid.UUID  `json:"requester_id"`
	Status        string     `json:"status"`
	RequestedAt   time.Time  `json:"requested_at"`
	ResolvedAt    *time.Time `json:"resolved_at,omitempty"`
	ExpiresAt     *time.Time `json:"expires_at,omitempty"`
	AutoApproveAt *time.Time `json:"auto_approve_at,omitempty"`
}

// ── Handlers ────────────────────────────────────────────────────────

// HandleGetEmergencyCard returns the emergency card data for a profile.
// GET /profiles/{profileID}/emergency-card
func (h *EmergencyHandler) HandleGetEmergencyCard(w http.ResponseWriter, r *http.Request) {
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

	// Verify the authenticated user owns or has been granted access to this profile
	var hasAccess bool
	err = h.db.QueryRow(r.Context(),
		`SELECT EXISTS (
			SELECT 1 FROM profiles WHERE id = $1 AND owner_user_id = $2
		)`,
		profileID, claims.UserID,
	).Scan(&hasAccess)
	if err != nil {
		h.logger.Error("check profile access", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	var (
		id      uuid.UUID
		enabled bool
		data    []byte
	)
	err = h.db.QueryRow(r.Context(),
		`SELECT id, enabled, data FROM emergency_cards WHERE profile_id = $1`,
		profileID,
	).Scan(&id, &enabled, &data)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeJSON(w, http.StatusNotFound, errorResponse("emergency_card_not_found"))
			return
		}
		h.logger.Error("get emergency card", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if !enabled {
		writeJSON(w, http.StatusNotFound, errorResponse("emergency_card_disabled"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"id":         id,
		"profile_id": profileID,
		"enabled":    enabled,
		"data":       json.RawMessage(data),
	})
}

// HandleConfigureEmergencyAccess creates or updates emergency access configuration.
// POST /profiles/{profileID}/emergency-access
func (h *EmergencyHandler) HandleConfigureEmergencyAccess(w http.ResponseWriter, r *http.Request) {
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

	// Verify profile ownership
	var ownerID uuid.UUID
	err = h.db.QueryRow(r.Context(),
		`SELECT owner_user_id FROM profiles WHERE id = $1`,
		profileID,
	).Scan(&ownerID)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
			return
		}
		h.logger.Error("check profile ownership", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if ownerID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	var req configureEmergencyAccessRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	// Determine emergency_contact_user_id: use provided value or default to self
	contactUserID := claims.UserID
	if req.EmergencyContactUserID != "" {
		parsed, parseErr := uuid.Parse(req.EmergencyContactUserID)
		if parseErr != nil {
			writeJSON(w, http.StatusBadRequest, errorResponse("invalid_emergency_contact_user_id"))
			return
		}
		contactUserID = parsed
	}

	// Default data_fields if empty
	dataFields := req.DataFields
	if len(dataFields) == 0 {
		dataFields = []string{"blood_type", "allergies", "medications", "diagnoses", "contacts"}
	}

	// Default wait_hours
	waitHours := req.WaitHours
	if waitHours <= 0 {
		waitHours = 48
	}

	now := time.Now().UTC()
	configID := uuid.New()

	var message *string
	if req.Message != "" {
		message = &req.Message
	}

	_, err = h.db.Exec(r.Context(),
		`INSERT INTO emergency_access_configs (id, profile_id, emergency_contact_user_id, wait_hours, data_fields, message, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		 ON CONFLICT (profile_id) DO UPDATE SET
		   emergency_contact_user_id = EXCLUDED.emergency_contact_user_id,
		   wait_hours = EXCLUDED.wait_hours,
		   data_fields = EXCLUDED.data_fields,
		   message = EXCLUDED.message,
		   updated_at = EXCLUDED.updated_at`,
		configID, profileID, contactUserID, waitHours, dataFields, message, now, now,
	)
	if err != nil {
		h.logger.Error("configure emergency access", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "configured"})
}

// HandleGetEmergencyAccessConfig returns the emergency access configuration for a profile.
// GET /profiles/{profileID}/emergency-access
func (h *EmergencyHandler) HandleGetEmergencyAccessConfig(w http.ResponseWriter, r *http.Request) {
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

	// Verify profile ownership
	var ownerID uuid.UUID
	err = h.db.QueryRow(r.Context(),
		`SELECT owner_user_id FROM profiles WHERE id = $1`,
		profileID,
	).Scan(&ownerID)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
			return
		}
		h.logger.Error("check profile ownership", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if ownerID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	var cfg emergencyAccessConfig
	err = h.db.QueryRow(r.Context(),
		`SELECT id, profile_id, emergency_contact_user_id, wait_hours, data_fields, message, created_at, updated_at
		 FROM emergency_access_configs WHERE profile_id = $1`,
		profileID,
	).Scan(&cfg.ID, &cfg.ProfileID, &cfg.EmergencyContactUserID, &cfg.WaitHours,
		&cfg.DataFields, &cfg.Message, &cfg.CreatedAt, &cfg.UpdatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			// No config row means emergency access is disabled
			writeJSON(w, http.StatusOK, emergencyAccessConfig{
				ProfileID: profileID,
				Enabled:   false,
			})
			return
		}
		h.logger.Error("get emergency access config", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Row exists means emergency access is enabled
	cfg.Enabled = true
	writeJSON(w, http.StatusOK, cfg)
}

// HandleDeleteEmergencyAccess removes emergency access configuration for a profile.
// DELETE /profiles/{profileID}/emergency-access
func (h *EmergencyHandler) HandleDeleteEmergencyAccess(w http.ResponseWriter, r *http.Request) {
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

	// Verify profile ownership
	var ownerID uuid.UUID
	err = h.db.QueryRow(r.Context(),
		`SELECT owner_user_id FROM profiles WHERE id = $1`,
		profileID,
	).Scan(&ownerID)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
			return
		}
		h.logger.Error("check profile ownership", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if ownerID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	tag, err := h.db.Exec(r.Context(),
		`DELETE FROM emergency_access_configs WHERE profile_id = $1`,
		profileID,
	)
	if err != nil {
		h.logger.Error("delete emergency access config", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusNotFound, errorResponse("config_not_found"))
		return
	}

	// Also remove the emergency card
	_, _ = h.db.Exec(r.Context(),
		`DELETE FROM emergency_cards WHERE profile_id = $1`,
		profileID,
	)

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// HandleRequestEmergencyAccess creates an emergency access request via token.
// POST /emergency/request/{token}
func (h *EmergencyHandler) HandleRequestEmergencyAccess(w http.ResponseWriter, r *http.Request) {
	token := chi.URLParam(r, "token")
	if token == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("token_required"))
		return
	}

	// Look up emergency card by token
	var cardID, profileID uuid.UUID
	var enabled bool
	err := h.db.QueryRow(r.Context(),
		`SELECT id, profile_id, enabled FROM emergency_cards WHERE token = $1`,
		token,
	).Scan(&cardID, &profileID, &enabled)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeJSON(w, http.StatusNotFound, errorResponse("invalid_token"))
			return
		}
		h.logger.Error("lookup emergency card by token", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if !enabled {
		writeJSON(w, http.StatusForbidden, errorResponse("emergency_access_disabled"))
		return
	}

	// Get wait_hours from config
	var waitHours int
	err = h.db.QueryRow(r.Context(),
		`SELECT wait_hours FROM emergency_access_configs WHERE profile_id = $1`,
		profileID,
	).Scan(&waitHours)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeJSON(w, http.StatusNotFound, errorResponse("emergency_access_not_configured"))
			return
		}
		h.logger.Error("get emergency access config for request", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	now := time.Now().UTC()
	autoApproveAt := now.Add(time.Duration(waitHours) * time.Hour)
	requestID := uuid.New()

	status := "pending"
	if waitHours == 0 {
		status = "auto_approved"
	}

	_, err = h.db.Exec(r.Context(),
		`INSERT INTO emergency_access_requests (id, profile_id, requester_id, status, requested_at, auto_approve_at)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		requestID, profileID, uuid.Nil, status, now, autoApproveAt,
	)
	if err != nil {
		h.logger.Error("create emergency access request", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{
		"id":              requestID,
		"status":          status,
		"auto_approve_at": autoApproveAt,
	})
}

// HandleGetPendingRequests lists pending emergency access requests for profiles
// owned by the authenticated user.
// GET /emergency/pending
func (h *EmergencyHandler) HandleGetPendingRequests(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	rows, err := h.db.Query(r.Context(),
		`SELECT ear.id, ear.profile_id, ear.requester_id, ear.status, ear.requested_at, ear.resolved_at, ear.expires_at, ear.auto_approve_at
		 FROM emergency_access_requests ear
		 JOIN profiles p ON p.id = ear.profile_id
		 WHERE p.owner_user_id = $1 AND ear.status = 'pending'
		 ORDER BY ear.requested_at DESC`,
		claims.UserID,
	)
	if err != nil {
		h.logger.Error("list pending emergency requests", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	var items []emergencyAccessRequest
	for rows.Next() {
		var req emergencyAccessRequest
		if err := rows.Scan(&req.ID, &req.ProfileID, &req.RequesterID,
			&req.Status, &req.RequestedAt, &req.ResolvedAt, &req.ExpiresAt, &req.AutoApproveAt); err != nil {
			h.logger.Error("scan emergency request", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		items = append(items, req)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate emergency requests", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if items == nil {
		items = []emergencyAccessRequest{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
	})
}

// HandleApproveRequest approves an emergency access request.
// POST /emergency/approve/{requestID}
func (h *EmergencyHandler) HandleApproveRequest(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	requestID, err := uuid.Parse(chi.URLParam(r, "requestID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request_id"))
		return
	}

	// Verify the request belongs to a profile owned by the authenticated user
	var profileOwnerID uuid.UUID
	err = h.db.QueryRow(r.Context(),
		`SELECT p.owner_user_id
		 FROM emergency_access_requests ear
		 JOIN profiles p ON p.id = ear.profile_id
		 WHERE ear.id = $1`,
		requestID,
	).Scan(&profileOwnerID)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeJSON(w, http.StatusNotFound, errorResponse("request_not_found"))
			return
		}
		h.logger.Error("verify request ownership", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if profileOwnerID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	now := time.Now().UTC()
	tag, err := h.db.Exec(r.Context(),
		`UPDATE emergency_access_requests SET status = 'approved', resolved_at = $1 WHERE id = $2 AND status = 'pending'`,
		now, requestID,
	)
	if err != nil {
		h.logger.Error("approve emergency request", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusConflict, errorResponse("request_not_pending"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "approved"})
}

// HandleDenyRequest denies an emergency access request.
// POST /emergency/deny/{requestID}
func (h *EmergencyHandler) HandleDenyRequest(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	requestID, err := uuid.Parse(chi.URLParam(r, "requestID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request_id"))
		return
	}

	// Verify the request belongs to a profile owned by the authenticated user
	var profileOwnerID uuid.UUID
	err = h.db.QueryRow(r.Context(),
		`SELECT p.owner_user_id
		 FROM emergency_access_requests ear
		 JOIN profiles p ON p.id = ear.profile_id
		 WHERE ear.id = $1`,
		requestID,
	).Scan(&profileOwnerID)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeJSON(w, http.StatusNotFound, errorResponse("request_not_found"))
			return
		}
		h.logger.Error("verify request ownership", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if profileOwnerID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	now := time.Now().UTC()
	tag, err := h.db.Exec(r.Context(),
		`UPDATE emergency_access_requests SET status = 'denied', resolved_at = $1 WHERE id = $2 AND status = 'pending'`,
		now, requestID,
	)
	if err != nil {
		h.logger.Error("deny emergency request", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusConflict, errorResponse("request_not_pending"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "denied"})
}
