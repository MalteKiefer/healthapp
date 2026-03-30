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

// ScheduledExportHandler handles CRUD for recurring export schedules.
type ScheduledExportHandler struct {
	db     *pgxpool.Pool
	logger *zap.Logger
}

// NewScheduledExportHandler creates a new ScheduledExportHandler.
func NewScheduledExportHandler(db *pgxpool.Pool, logger *zap.Logger) *ScheduledExportHandler {
	return &ScheduledExportHandler{db: db, logger: logger}
}

// ── Request / Response Types ────────────────────────────────────────

type createScheduleRequest struct {
	ProfileIDs []uuid.UUID `json:"profile_ids"`
	Format     string      `json:"format"`
	Frequency  string      `json:"frequency"`
}

type exportSchedule struct {
	ID         uuid.UUID   `json:"id"`
	UserID     uuid.UUID   `json:"user_id"`
	ProfileIDs []uuid.UUID `json:"profile_ids"`
	Format     string      `json:"format"`
	Frequency  string      `json:"frequency"`
	LastRunAt  *time.Time  `json:"last_run_at,omitempty"`
	NextRunAt  *time.Time  `json:"next_run_at,omitempty"`
	Enabled    bool        `json:"enabled"`
	CreatedAt  time.Time   `json:"created_at"`
}

// ── Handlers ────────────────────────────────────────────────────────

// HandleCreateSchedule stores a new export schedule.
// POST /export/schedule
func (h *ScheduledExportHandler) HandleCreateSchedule(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	var req createScheduleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if len(req.ProfileIDs) == 0 {
		writeJSON(w, http.StatusBadRequest, errorResponse("profile_ids_required"))
		return
	}

	// Verify the user has access to all requested profiles
	for _, pid := range req.ProfileIDs {
		var hasAccess bool
		err := h.db.QueryRow(r.Context(),
			`SELECT EXISTS(
				SELECT 1 FROM profiles WHERE id = $1 AND owner_user_id = $2
				UNION
				SELECT 1 FROM profile_key_grants WHERE profile_id = $1 AND grantee_user_id = $2 AND revoked_at IS NULL
			)`, pid, claims.UserID).Scan(&hasAccess)
		if err != nil || !hasAccess {
			writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
			return
		}
	}

	switch req.Format {
	case "native", "json", "fhir":
		// valid
	default:
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_format"))
		return
	}

	var nextRunAt time.Time
	switch req.Frequency {
	case "weekly":
		nextRunAt = time.Now().UTC().AddDate(0, 0, 7)
	case "monthly":
		nextRunAt = time.Now().UTC().AddDate(0, 1, 0)
	case "quarterly":
		nextRunAt = time.Now().UTC().AddDate(0, 3, 0)
	default:
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_frequency"))
		return
	}

	var sched exportSchedule
	err := h.db.QueryRow(r.Context(),
		`INSERT INTO export_schedules (user_id, profile_ids, format, frequency, next_run_at)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, user_id, profile_ids, format, frequency, last_run_at, next_run_at, enabled, created_at`,
		claims.UserID, req.ProfileIDs, req.Format, req.Frequency, nextRunAt,
	).Scan(
		&sched.ID, &sched.UserID, &sched.ProfileIDs, &sched.Format,
		&sched.Frequency, &sched.LastRunAt, &sched.NextRunAt,
		&sched.Enabled, &sched.CreatedAt,
	)
	if err != nil {
		h.logger.Error("create export schedule", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, sched)
}

// HandleListSchedules returns all export schedules for the authenticated user.
// GET /export/schedules
func (h *ScheduledExportHandler) HandleListSchedules(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	rows, err := h.db.Query(r.Context(),
		`SELECT id, user_id, profile_ids, format, frequency, last_run_at, next_run_at, enabled, created_at
		 FROM export_schedules
		 WHERE user_id = $1
		 ORDER BY created_at DESC`,
		claims.UserID,
	)
	if err != nil {
		h.logger.Error("list export schedules", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	var schedules []exportSchedule
	for rows.Next() {
		var s exportSchedule
		if err := rows.Scan(
			&s.ID, &s.UserID, &s.ProfileIDs, &s.Format,
			&s.Frequency, &s.LastRunAt, &s.NextRunAt,
			&s.Enabled, &s.CreatedAt,
		); err != nil {
			h.logger.Error("scan export schedule", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		schedules = append(schedules, s)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate export schedules", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if schedules == nil {
		schedules = []exportSchedule{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": schedules,
	})
}

// HandleDeleteSchedule removes an export schedule belonging to the user.
// DELETE /export/schedules/{scheduleID}
func (h *ScheduledExportHandler) HandleDeleteSchedule(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	scheduleID, err := uuid.Parse(chi.URLParam(r, "scheduleID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_schedule_id"))
		return
	}

	tag, err := h.db.Exec(r.Context(),
		`DELETE FROM export_schedules WHERE id = $1 AND user_id = $2`,
		scheduleID, claims.UserID,
	)
	if err != nil {
		h.logger.Error("delete export schedule", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusNotFound, errorResponse("schedule_not_found"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
