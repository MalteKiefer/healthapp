package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/user"
)

// UserHandler handles user/me endpoints.
type UserHandler struct {
	userRepo user.Repository
	logger   *zap.Logger
}

func NewUserHandler(repo user.Repository, logger *zap.Logger) *UserHandler {
	return &UserHandler{userRepo: repo, logger: logger}
}

// HandleGetMe returns the authenticated user's profile (without sensitive fields).
func (h *UserHandler) HandleGetMe(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	u, err := h.userRepo.GetByID(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("get user", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, sanitizeUser(u))
}

// HandleUpdateMe updates the authenticated user's display name.
func (h *UserHandler) HandleUpdateMe(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	var req struct {
		DisplayName string `json:"display_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.DisplayName == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("display_name_required"))
		return
	}

	u, err := h.userRepo.GetByID(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("get user for update", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	u.DisplayName = req.DisplayName

	if err := h.userRepo.Update(r.Context(), u); err != nil {
		h.logger.Error("update user", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, sanitizeUser(u))
}

// HandleDeleteMe deletes the authenticated user's account.
func (h *UserHandler) HandleDeleteMe(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	// TODO: check for shared profiles before allowing deletion

	if err := h.userRepo.Delete(r.Context(), claims.UserID); err != nil {
		h.logger.Error("delete user", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleGetSessions returns the authenticated user's active sessions.
func (h *UserHandler) HandleGetSessions(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	sessions, err := h.userRepo.GetSessionsByUserID(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("get sessions", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"sessions": sessions,
	})
}

// HandleRevokeSession revokes a specific session by ID.
func (h *UserHandler) HandleRevokeSession(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	sessionID, err := uuid.Parse(chi.URLParam(r, "sessionID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_session_id"))
		return
	}

	// Verify the session belongs to this user
	sessions, err := h.userRepo.GetSessionsByUserID(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("get sessions for revoke", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	found := false
	for _, s := range sessions {
		if s.ID == sessionID {
			found = true
			break
		}
	}
	if !found {
		writeJSON(w, http.StatusNotFound, errorResponse("session_not_found"))
		return
	}

	if err := h.userRepo.RevokeSession(r.Context(), sessionID); err != nil {
		h.logger.Error("revoke session", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleRevokeOtherSessions revokes all sessions except the current one.
func (h *UserHandler) HandleRevokeOtherSessions(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	// Find the current session by the JWT's JTI
	currentSession, err := h.userRepo.GetSessionByJTI(r.Context(), claims.ID)
	if err != nil {
		h.logger.Error("get current session", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if err := h.userRepo.RevokeAllSessions(r.Context(), claims.UserID, &currentSession.ID); err != nil {
		h.logger.Error("revoke other sessions", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleGetStorage returns the authenticated user's storage information.
func (h *UserHandler) HandleGetStorage(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	storage, err := h.userRepo.GetStorage(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("get storage", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, storage)
}

// HandleGetPreferences returns the authenticated user's preferences.
func (h *UserHandler) HandleGetPreferences(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	prefs, err := h.userRepo.GetPreferences(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("get preferences", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, prefs)
}

// HandleUpdatePreferences updates the authenticated user's preferences.
func (h *UserHandler) HandleUpdatePreferences(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	var prefs user.Preferences
	if err := json.NewDecoder(r.Body).Decode(&prefs); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	prefs.UserID = claims.UserID

	if err := h.userRepo.UpsertPreferences(r.Context(), &prefs); err != nil {
		h.logger.Error("update preferences", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, prefs)
}

// HandleGetPublicKey returns the identity public key for any user (for ECDH key exchange).
func (h *UserHandler) HandleGetPublicKey(w http.ResponseWriter, r *http.Request) {
	userID, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_user_id"))
		return
	}

	u, err := h.userRepo.GetByID(r.Context(), userID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("user_not_found"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"user_id":         u.ID,
		"identity_pubkey": u.IdentityPubkey,
	})
}

// sanitizeUser returns a map representation of the user without sensitive fields.
func sanitizeUser(u *user.User) map[string]interface{} {
	return map[string]interface{}{
		"id":                      u.ID,
		"email":                   u.Email,
		"display_name":            u.DisplayName,
		"identity_pubkey":         u.IdentityPubkey,
		"signing_pubkey":          u.SigningPubkey,
		"role":                    u.Role,
		"is_disabled":             u.IsDisabled,
		"totp_enabled":            u.TOTPEnabled,
		"onboarding_completed_at": u.OnboardingCompletedAt,
		"created_at":              u.CreatedAt,
		"updated_at":              u.UpdatedAt,
	}
}
