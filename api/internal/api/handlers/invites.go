package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// InviteHandler handles admin invite management endpoints.
type InviteHandler struct {
	db     *pgxpool.Pool
	logger *zap.Logger
}

// NewInviteHandler creates a new InviteHandler.
func NewInviteHandler(db *pgxpool.Pool, logger *zap.Logger) *InviteHandler {
	return &InviteHandler{db: db, logger: logger}
}

// HandleListInvites returns existing invites.
// GET /admin/invites
func (h *InviteHandler) HandleListInvites(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": []interface{}{},
		"note":  "invite management coming soon",
	})
}

// HandleCreateInvite generates a new registration invite token.
// POST /admin/invites
func (h *InviteHandler) HandleCreateInvite(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		h.logger.Error("generate invite token", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	token := hex.EncodeToString(tokenBytes)

	h.logger.Info("invite token created",
		zap.String("created_by", claims.UserID.String()),
	)

	writeJSON(w, http.StatusCreated, map[string]string{
		"token": token,
	})
}

// HandleDeleteInvite deletes an existing invite token.
// DELETE /admin/invites/{token}
func (h *InviteHandler) HandleDeleteInvite(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	token := chi.URLParam(r, "token")
	if token == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("token_required"))
		return
	}

	h.logger.Info("invite token deleted",
		zap.String("token", token),
		zap.String("deleted_by", claims.UserID.String()),
	)

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
