package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
)

// ActivityHandler handles profile activity log endpoints.
type ActivityHandler struct {
	db          *pgxpool.Pool
	profileRepo profiles.Repository
	logger      *zap.Logger
}

func NewActivityHandler(db *pgxpool.Pool, pr profiles.Repository, logger *zap.Logger) *ActivityHandler {
	return &ActivityHandler{db: db, profileRepo: pr, logger: logger}
}

// ── Response Types ──────────────────────────────────────────────────

type activityLogEntry struct {
	ID        uuid.UUID `json:"id"`
	ProfileID uuid.UUID `json:"profile_id"`
	Action    string    `json:"action"`
	Entity    string    `json:"entity"`
	EntityID  *string   `json:"entity_id,omitempty"`
	Details   *string   `json:"details,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

// HandleList returns a paginated activity log for a profile.
// GET /profiles/{profileID}/activity
func (h *ActivityHandler) HandleList(w http.ResponseWriter, r *http.Request) {
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

	limit := 50
	offset := 0

	if v := r.URL.Query().Get("limit"); v != "" {
		if l, err := strconv.Atoi(v); err == nil && l > 0 && l <= 200 {
			limit = l
		}
	}
	if v := r.URL.Query().Get("offset"); v != "" {
		if o, err := strconv.Atoi(v); err == nil && o >= 0 {
			offset = o
		}
	}

	// Query total count
	var total int
	err = h.db.QueryRow(r.Context(),
		`SELECT COUNT(*) FROM profile_activity_log WHERE profile_id = $1`,
		profileID).Scan(&total)
	if err != nil {
		h.logger.Error("count activity log", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Query paginated items
	rows, err := h.db.Query(r.Context(),
		`SELECT id, profile_id, action, entity, entity_id, details, created_at
		FROM profile_activity_log
		WHERE profile_id = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3`,
		profileID, limit, offset)
	if err != nil {
		h.logger.Error("query activity log", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	items := []activityLogEntry{}
	for rows.Next() {
		var entry activityLogEntry
		if err := rows.Scan(&entry.ID, &entry.ProfileID, &entry.Action,
			&entry.Entity, &entry.EntityID, &entry.Details, &entry.CreatedAt); err != nil {
			h.logger.Error("scan activity entry", zap.Error(err))
			continue
		}
		items = append(items, entry)
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}
