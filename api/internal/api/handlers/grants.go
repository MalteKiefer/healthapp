package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
)

// GrantHandler handles profile key grant, key-rotation and transfer endpoints.
type GrantHandler struct {
	db          *pgxpool.Pool
	profileRepo profiles.Repository
	logger      *zap.Logger
}

func NewGrantHandler(db *pgxpool.Pool, pr profiles.Repository, logger *zap.Logger) *GrantHandler {
	return &GrantHandler{db: db, profileRepo: pr, logger: logger}
}

// ── Request Types ───────────────────────────────────────────────────

type createGrantRequest struct {
	EncryptedKey   string `json:"encrypted_key"`
	GrantSignature string `json:"grant_signature"`
	GranteeUserID  string `json:"grantee_user_id"`
}

type transferRequest struct {
	NewOwnerUserID string `json:"new_owner_user_id"`
}

// ── Handlers ────────────────────────────────────────────────────────

// HandleCreateGrant creates a new profile key grant.
// POST /profiles/{profileID}/grants
func (h *GrantHandler) HandleCreateGrant(w http.ResponseWriter, r *http.Request) {
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

	// Only the owner can create grants
	p, err := h.profileRepo.GetByID(r.Context(), profileID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}
	if p.OwnerUserID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("owner_required"))
		return
	}

	var req createGrantRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.EncryptedKey == "" || req.GrantSignature == "" || req.GranteeUserID == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("missing_required_fields"))
		return
	}

	granteeID, err := uuid.Parse(req.GranteeUserID)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_grantee_user_id"))
		return
	}

	grant := &profiles.KeyGrant{
		ProfileID:       profileID,
		GranteeUserID:   granteeID,
		EncryptedKey:    req.EncryptedKey,
		GrantSignature:  req.GrantSignature,
		GrantedByUserID: claims.UserID,
		GrantedAt:       time.Now().UTC(),
	}

	if err := h.profileRepo.CreateKeyGrant(r.Context(), grant); err != nil {
		h.logger.Error("create key grant", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, grant)
}

// HandleRevokeGrant revokes a key grant for a specific grantee.
// DELETE /profiles/{profileID}/grants/{grantUserID}
func (h *GrantHandler) HandleRevokeGrant(w http.ResponseWriter, r *http.Request) {
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

	// Only the owner can revoke grants
	p, err := h.profileRepo.GetByID(r.Context(), profileID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}
	if p.OwnerUserID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("owner_required"))
		return
	}

	grantUserID, err := uuid.Parse(chi.URLParam(r, "grantUserID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_grant_user_id"))
		return
	}

	if err := h.profileRepo.RevokeKeyGrant(r.Context(), profileID, grantUserID); err != nil {
		h.logger.Error("revoke key grant", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleKeyRotation returns 501 as key rotation requires client-side re-encryption.
// POST /profiles/{profileID}/key-rotation
func (h *GrantHandler) HandleKeyRotation(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, map[string]string{
		"error":   "not_implemented",
		"message": "key rotation requires client-side re-encryption",
	})
}

// HandleTransfer transfers profile ownership to another user.
// POST /profiles/{profileID}/transfer
func (h *GrantHandler) HandleTransfer(w http.ResponseWriter, r *http.Request) {
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

	// Only the current owner can transfer
	p, err := h.profileRepo.GetByID(r.Context(), profileID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}
	if p.OwnerUserID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("owner_required"))
		return
	}

	var req transferRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	newOwnerID, err := uuid.Parse(req.NewOwnerUserID)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_new_owner_user_id"))
		return
	}

	if newOwnerID == claims.UserID {
		writeJSON(w, http.StatusBadRequest, errorResponse("cannot_transfer_to_self"))
		return
	}

	// Verify target user exists and is active
	var targetExists bool
	err = h.db.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND is_disabled = false)`, newOwnerID).Scan(&targetExists)
	if err != nil {
		h.logger.Error("check target user", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if !targetExists {
		writeJSON(w, http.StatusBadRequest, errorResponse("target_user_not_found"))
		return
	}

	// Verify current user is the actual owner (direct DB check)
	var currentOwner uuid.UUID
	err = h.db.QueryRow(r.Context(), `SELECT owner_user_id FROM profiles WHERE id = $1`, profileID).Scan(&currentOwner)
	if err != nil {
		h.logger.Error("check profile owner", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if currentOwner != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("only_owner_can_transfer"))
		return
	}

	now := time.Now().UTC()
	_, err = h.db.Exec(r.Context(),
		`UPDATE profiles SET owner_user_id = $2, updated_at = $3 WHERE id = $1`,
		profileID, newOwnerID, now,
	)
	if err != nil {
		h.logger.Error("transfer profile", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"status":         "transferred",
		"profile_id":     profileID,
		"new_owner_id":   newOwnerID,
	})
}
