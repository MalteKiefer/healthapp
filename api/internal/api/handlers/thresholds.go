package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
)

// ThresholdHandler handles vital threshold endpoints.
type ThresholdHandler struct {
	db          *pgxpool.Pool
	profileRepo profiles.Repository
	logger      *zap.Logger
}

func NewThresholdHandler(db *pgxpool.Pool, pr profiles.Repository, logger *zap.Logger) *ThresholdHandler {
	return &ThresholdHandler{db: db, profileRepo: pr, logger: logger}
}

// ── Request/Response Types ──────────────────────────────────────────

type vitalThreshold struct {
	ID           uuid.UUID `json:"id"`
	ProfileID    uuid.UUID `json:"profile_id"`
	Metric       string    `json:"metric"`
	MinValue     *float64  `json:"min_value,omitempty"`
	MaxValue     *float64  `json:"max_value,omitempty"`
	AlertEnabled bool      `json:"alert_enabled"`
}

type setThresholdsRequest struct {
	Thresholds []vitalThreshold `json:"thresholds"`
}

// HandleGet returns vital thresholds for a profile.
// GET /profiles/{profileID}/vital-thresholds
func (h *ThresholdHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
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

	rows, err := h.db.Query(r.Context(),
		`SELECT id, profile_id, metric, min_value, max_value, alert_enabled
		FROM vital_thresholds
		WHERE profile_id = $1
		ORDER BY metric`, profileID)
	if err != nil {
		h.logger.Error("query thresholds", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	thresholds := []vitalThreshold{}
	for rows.Next() {
		var t vitalThreshold
		if err := rows.Scan(&t.ID, &t.ProfileID, &t.Metric, &t.MinValue, &t.MaxValue, &t.AlertEnabled); err != nil {
			h.logger.Error("scan threshold", zap.Error(err))
			continue
		}
		thresholds = append(thresholds, t)
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"thresholds": thresholds,
	})
}

// HandleSet upserts vital thresholds for a profile.
// PUT /profiles/{profileID}/vital-thresholds
func (h *ThresholdHandler) HandleSet(w http.ResponseWriter, r *http.Request) {
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

	var req setThresholdsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	tx, err := h.db.Begin(r.Context())
	if err != nil {
		h.logger.Error("begin tx", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer tx.Rollback(r.Context())

	for _, t := range req.Thresholds {
		if t.Metric == "" {
			continue
		}
		_, err := tx.Exec(r.Context(),
			`INSERT INTO vital_thresholds (profile_id, metric, min_value, max_value, alert_enabled)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (profile_id, metric) DO UPDATE
			SET min_value = EXCLUDED.min_value,
				max_value = EXCLUDED.max_value,
				alert_enabled = EXCLUDED.alert_enabled,
				updated_at = NOW()`,
			profileID, t.Metric, t.MinValue, t.MaxValue, t.AlertEnabled)
		if err != nil {
			h.logger.Error("upsert threshold", zap.String("metric", t.Metric), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
	}

	if err := tx.Commit(r.Context()); err != nil {
		h.logger.Error("commit thresholds", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "thresholds_updated"})
}
