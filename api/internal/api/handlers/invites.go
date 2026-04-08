package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// truncateToken safely returns a prefix of the token for logging.
func truncateToken(token string) string {
	if len(token) > 8 {
		return token[:8] + "..."
	}
	return token
}

// InviteHandler handles admin invite management endpoints.
type InviteHandler struct {
	db     *pgxpool.Pool
	logger *zap.Logger
}

// NewInviteHandler creates a new InviteHandler.
func NewInviteHandler(db *pgxpool.Pool, logger *zap.Logger) *InviteHandler {
	return &InviteHandler{db: db, logger: logger}
}

type createInviteRequest struct {
	Email string `json:"email"`
	Note  string `json:"note"`
}

type inviteResponse struct {
	Token     string  `json:"token"`
	Email     *string `json:"email"`
	Note      *string `json:"note"`
	CreatedBy string  `json:"created_by"`
	CreatedAt string  `json:"created_at"`
	UsedAt    *string `json:"used_at"`
	UsedBy    *string `json:"used_by"`
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

	rows, err := h.db.Query(r.Context(),
		`SELECT token, email, note, created_by, created_at, used_at, used_by
		 FROM registration_invites
		 ORDER BY created_at DESC`)
	if err != nil {
		h.logger.Error("list invites", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	items := []inviteResponse{}
	for rows.Next() {
		var (
			token     string
			email     *string
			note      *string
			createdBy uuid.UUID
			createdAt time.Time
			usedAt    *time.Time
			usedBy    *uuid.UUID
		)
		if err := rows.Scan(&token, &email, &note, &createdBy, &createdAt, &usedAt, &usedBy); err != nil {
			h.logger.Error("scan invite row", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}

		item := inviteResponse{
			Token:     token,
			Email:     email,
			Note:      note,
			CreatedBy: createdBy.String(),
			CreatedAt: createdAt.Format(time.RFC3339),
		}
		if usedAt != nil {
			s := usedAt.Format(time.RFC3339)
			item.UsedAt = &s
		}
		if usedBy != nil {
			s := usedBy.String()
			item.UsedBy = &s
		}
		items = append(items, item)
	}

	if err := rows.Err(); err != nil {
		h.logger.Error("iterate invite rows", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
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

	var req createInviteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		// Allow empty body — email and note are optional.
		req = createInviteRequest{}
	}

	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		h.logger.Error("generate invite token", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	token := hex.EncodeToString(tokenBytes)

	var email, note *string
	if req.Email != "" {
		email = &req.Email
	}
	if req.Note != "" {
		note = &req.Note
	}

	var createdAt time.Time
	err := h.db.QueryRow(r.Context(),
		`INSERT INTO registration_invites (token, email, note, created_by)
		 VALUES ($1, $2, $3, $4)
		 RETURNING created_at`,
		token, email, note, claims.UserID,
	).Scan(&createdAt)
	if err != nil {
		h.logger.Error("insert invite", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	h.logger.Info("invite token created",
		zap.String("token_prefix", truncateToken(token)),
		zap.String("created_by", claims.UserID.String()),
	)

	writeJSON(w, http.StatusCreated, inviteResponse{
		Token:     token,
		Email:     email,
		Note:      note,
		CreatedBy: claims.UserID.String(),
		CreatedAt: createdAt.Format(time.RFC3339),
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
	if len(token) != 64 {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_token_format"))
		return
	}

	result, err := h.db.Exec(r.Context(),
		`DELETE FROM registration_invites WHERE token = $1`, token)
	if err != nil {
		h.logger.Error("delete invite", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if result.RowsAffected() == 0 {
		writeJSON(w, http.StatusNotFound, errorResponse("invite_not_found"))
		return
	}

	h.logger.Info("invite token deleted",
		zap.String("token_prefix", truncateToken(token)),
		zap.String("deleted_by", claims.UserID.String()),
	)

	w.WriteHeader(http.StatusNoContent)
}
