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
	Enabled           bool     `json:"enabled"`
	WaitHours         int      `json:"wait_hours"`
	NotifyOnRequest   bool     `json:"notify_on_request"`
	AutoApprove       bool     `json:"auto_approve"`
	VisibleFields     []string `json:"visible_fields"`
	EmergencyCardData []byte   `json:"emergency_card_data"`
}

type emergencyAccessConfig struct {
	ID              uuid.UUID `json:"id"`
	ProfileID       uuid.UUID `json:"profile_id"`
	Enabled         bool      `json:"enabled"`
	WaitHours       int       `json:"wait_hours"`
	NotifyOnRequest bool      `json:"notify_on_request"`
	AutoApprove     bool      `json:"auto_approve"`
	VisibleFields   []string  `json:"visible_fields"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

type emergencyAccessRequest struct {
	ID            uuid.UUID  `json:"id"`
	CardID        uuid.UUID  `json:"card_id"`
	ProfileID     uuid.UUID  `json:"profile_id"`
	RequesterNote string     `json:"requester_note"`
	Status        string     `json:"status"`
	AutoApproveAt *time.Time `json:"auto_approve_at,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

type requestEmergencyAccessBody struct {
	RequesterNote string `json:"requester_note"`
}

// ── Handlers ────────────────────────────────────────────────────────

// HandleGetEmergencyCard returns the emergency card data for a profile.
// This endpoint is token-based and does not require JWT authentication.
// GET /profiles/{profileID}/emergency-card
func (h *EmergencyHandler) HandleGetEmergencyCard(w http.ResponseWriter, r *http.Request) {
	profileID, err := uuid.Parse(chi.URLParam(r, "profileID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_profile_id"))
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

	visibleFieldsJSON, err := json.Marshal(req.VisibleFields)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_visible_fields"))
		return
	}

	now := time.Now().UTC()
	configID := uuid.New()

	_, err = h.db.Exec(r.Context(),
		`INSERT INTO emergency_access_configs (id, profile_id, enabled, wait_hours, notify_on_request, auto_approve, visible_fields, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		 ON CONFLICT (profile_id) DO UPDATE SET
		   enabled = EXCLUDED.enabled,
		   wait_hours = EXCLUDED.wait_hours,
		   notify_on_request = EXCLUDED.notify_on_request,
		   auto_approve = EXCLUDED.auto_approve,
		   visible_fields = EXCLUDED.visible_fields,
		   updated_at = EXCLUDED.updated_at`,
		configID, profileID, req.Enabled, req.WaitHours, req.NotifyOnRequest,
		req.AutoApprove, visibleFieldsJSON, now, now,
	)
	if err != nil {
		h.logger.Error("configure emergency access", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Also upsert the emergency card if card data was provided
	if req.EmergencyCardData != nil {
		cardID := uuid.New()
		_, err = h.db.Exec(r.Context(),
			`INSERT INTO emergency_cards (id, profile_id, enabled, data, created_at, updated_at)
			 VALUES ($1, $2, $3, $4, $5, $6)
			 ON CONFLICT (profile_id) DO UPDATE SET
			   enabled = EXCLUDED.enabled,
			   data = EXCLUDED.data,
			   updated_at = EXCLUDED.updated_at`,
			cardID, profileID, req.Enabled, req.EmergencyCardData, now, now,
		)
		if err != nil {
			h.logger.Error("upsert emergency card", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
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
	var visibleFieldsJSON []byte
	err = h.db.QueryRow(r.Context(),
		`SELECT id, profile_id, enabled, wait_hours, notify_on_request, auto_approve, visible_fields, created_at, updated_at
		 FROM emergency_access_configs WHERE profile_id = $1`,
		profileID,
	).Scan(&cfg.ID, &cfg.ProfileID, &cfg.Enabled, &cfg.WaitHours,
		&cfg.NotifyOnRequest, &cfg.AutoApprove, &visibleFieldsJSON,
		&cfg.CreatedAt, &cfg.UpdatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeJSON(w, http.StatusNotFound, errorResponse("config_not_found"))
			return
		}
		h.logger.Error("get emergency access config", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if visibleFieldsJSON != nil {
		if err := json.Unmarshal(visibleFieldsJSON, &cfg.VisibleFields); err != nil {
			h.logger.Error("unmarshal visible_fields", zap.Error(err))
		}
	}

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
	var autoApprove bool
	err = h.db.QueryRow(r.Context(),
		`SELECT wait_hours, auto_approve FROM emergency_access_configs WHERE profile_id = $1`,
		profileID,
	).Scan(&waitHours, &autoApprove)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeJSON(w, http.StatusNotFound, errorResponse("emergency_access_not_configured"))
			return
		}
		h.logger.Error("get emergency access config for request", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	var body requestEmergencyAccessBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		// Body is optional for this endpoint
		body = requestEmergencyAccessBody{}
	}

	now := time.Now().UTC()
	autoApproveAt := now.Add(time.Duration(waitHours) * time.Hour)
	requestID := uuid.New()

	status := "pending"
	if autoApprove && waitHours == 0 {
		status = "approved"
	}

	_, err = h.db.Exec(r.Context(),
		`INSERT INTO emergency_access_requests (id, card_id, profile_id, requester_note, status, auto_approve_at, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		requestID, cardID, profileID, body.RequesterNote, status, autoApproveAt, now, now,
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
		`SELECT ear.id, ear.card_id, ear.profile_id, ear.requester_note, ear.status, ear.auto_approve_at, ear.created_at, ear.updated_at
		 FROM emergency_access_requests ear
		 JOIN profiles p ON p.id = ear.profile_id
		 WHERE p.owner_user_id = $1 AND ear.status = 'pending'
		 ORDER BY ear.created_at DESC`,
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
		if err := rows.Scan(&req.ID, &req.CardID, &req.ProfileID, &req.RequesterNote,
			&req.Status, &req.AutoApproveAt, &req.CreatedAt, &req.UpdatedAt); err != nil {
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
		`UPDATE emergency_access_requests SET status = 'approved', updated_at = $1 WHERE id = $2 AND status = 'pending'`,
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
		`UPDATE emergency_access_requests SET status = 'denied', updated_at = $1 WHERE id = $2 AND status = 'pending'`,
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
