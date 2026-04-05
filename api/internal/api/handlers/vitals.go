package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
	"github.com/healthvault/healthvault/internal/domain/vitals"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// VitalHandler handles vital sign endpoints.
type VitalHandler struct {
	vitalRepo   vitals.Repository
	profileRepo profiles.Repository
	logger      *zap.Logger
}

func NewVitalHandler(vr vitals.Repository, pr profiles.Repository, logger *zap.Logger) *VitalHandler {
	return &VitalHandler{vitalRepo: vr, profileRepo: pr, logger: logger}
}

// HandleList returns vitals for a profile with optional date filtering and pagination.
func (h *VitalHandler) HandleList(w http.ResponseWriter, r *http.Request) {
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

	filter := vitals.ListFilter{
		ProfileID: profileID,
		Limit:     50,
	}

	if v := r.URL.Query().Get("limit"); v != "" {
		if l, err := strconv.Atoi(v); err == nil && l > 0 && l <= 200 {
			filter.Limit = l
		}
	}
	if v := r.URL.Query().Get("offset"); v != "" {
		if o, err := strconv.Atoi(v); err == nil && o >= 0 {
			filter.Offset = o
		}
	}
	if v := r.URL.Query().Get("from"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			filter.From = &t
		}
	}
	if v := r.URL.Query().Get("to"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			filter.To = &t
		}
	}

	items, total, err := h.vitalRepo.List(r.Context(), filter)
	if err != nil {
		h.logger.Error("list vitals", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}

// HandleCreate creates a new vital measurement with duplicate detection.
func (h *VitalHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
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

	var v vitals.Vital
	if err := json.NewDecoder(r.Body).Decode(&v); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	v.ProfileID = profileID
	if v.MeasuredAt.IsZero() {
		v.MeasuredAt = time.Now().UTC()
	}

	// Duplicate detection (skip if force=true)
	if r.URL.Query().Get("force") != "true" {
		existingID, err := h.vitalRepo.CheckDuplicate(r.Context(), &v)
		if err != nil {
			h.logger.Error("check duplicate", zap.Error(err))
		} else if existingID != nil {
			writeJSON(w, http.StatusConflict, map[string]interface{}{
				"error":       "possible_duplicate",
				"existing_id": existingID.String(),
			})
			return
		}
	}

	if err := h.vitalRepo.Create(r.Context(), &v); err != nil {
		h.logger.Error("create vital", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.Header().Set("Location", fmt.Sprintf("/api/v1/profiles/%s/vitals/%s", profileID, v.ID))
	writeJSON(w, http.StatusCreated, v)
}

// HandleGet returns a single vital measurement.
func (h *VitalHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
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

	vitalID, err := uuid.Parse(chi.URLParam(r, "vitalID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_vital_id"))
		return
	}

	v, err := h.vitalRepo.GetByID(r.Context(), vitalID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get vital", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if v.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	writeJSON(w, http.StatusOK, v)
}

// HandleUpdate patches a vital measurement.
func (h *VitalHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
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

	vitalID, err := uuid.Parse(chi.URLParam(r, "vitalID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_vital_id"))
		return
	}

	existing, err := h.vitalRepo.GetByID(r.Context(), vitalID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get vital", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	// Decode patch — only non-nil fields are updated
	if err := json.NewDecoder(r.Body).Decode(existing); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if err := h.vitalRepo.Update(r.Context(), existing); err != nil {
		h.logger.Error("update vital", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, existing)
}

// HandleDelete soft-deletes a vital measurement.
func (h *VitalHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
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

	vitalID, err := uuid.Parse(chi.URLParam(r, "vitalID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_vital_id"))
		return
	}

	existing, err := h.vitalRepo.GetByID(r.Context(), vitalID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get vital", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if err := h.vitalRepo.SoftDelete(r.Context(), vitalID); err != nil {
		h.logger.Error("delete vital", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleChart is deprecated under Stage 2 — vitals content is encrypted, so
// the server can no longer aggregate numeric values. Clients compute chart
// series locally from the decrypted vitals list.
func (h *VitalHandler) HandleChart(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{
		"error":   "endpoint_removed",
		"message": "vitals/chart is now computed client-side from decrypted content",
	})
}

// HandleMigrateContent lazily backfills the content_enc column for a vital
// row. Idempotent: the repo writes only if the column is currently NULL, so
// concurrent clients (e.g. web + mobile) cannot overwrite each other.
// PATCH /profiles/{profileID}/vitals/{vitalID}/migrate-content
func (h *VitalHandler) HandleMigrateContent(w http.ResponseWriter, r *http.Request) {
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

	vitalID, err := uuid.Parse(chi.URLParam(r, "vitalID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_vital_id"))
		return
	}

	existing, err := h.vitalRepo.GetByID(r.Context(), vitalID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get vital for migrate", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	var body struct {
		ContentEnc string `json:"content_enc"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.ContentEnc == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("content_enc_required"))
		return
	}

	if err := h.vitalRepo.SetContentEnc(r.Context(), vitalID, body.ContentEnc); err != nil {
		h.logger.Error("set content_enc", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
