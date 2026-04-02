package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/labs"
	"github.com/healthvault/healthvault/internal/domain/profiles"
)

// LabHandler handles lab result endpoints.
type LabHandler struct {
	labRepo     labs.Repository
	profileRepo profiles.Repository
	logger      *zap.Logger
}

func NewLabHandler(lr labs.Repository, pr profiles.Repository, logger *zap.Logger) *LabHandler {
	return &LabHandler{labRepo: lr, profileRepo: pr, logger: logger}
}

// HandleList returns lab results for a profile with pagination.
func (h *LabHandler) HandleList(w http.ResponseWriter, r *http.Request) {
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

	items, total, err := h.labRepo.List(r.Context(), profileID, limit, offset)
	if err != nil {
		h.logger.Error("list lab results", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}

// HandleTrends returns aggregated marker time series for trend visualization.
func (h *LabHandler) HandleTrends(w http.ResponseWriter, r *http.Request) {
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

	var from, to *time.Time
	if v := r.URL.Query().Get("from"); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, errorResponse("invalid_from_date"))
			return
		}
		from = &t
	}
	if v := r.URL.Query().Get("to"); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, errorResponse("invalid_to_date"))
			return
		}
		to = &t
	}

	markers, err := h.labRepo.ListTrends(r.Context(), profileID, from, to)
	if err != nil {
		h.logger.Error("list lab trends", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"markers": markers,
	})
}

// HandleCreate creates a new lab result with duplicate detection.
func (h *LabHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
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

	var lr labs.LabResult
	if err := json.NewDecoder(r.Body).Decode(&lr); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	lr.ProfileID = profileID
	if lr.SampleDate.IsZero() {
		lr.SampleDate = time.Now().UTC()
	}

	// Duplicate detection (skip if force=true)
	if r.URL.Query().Get("force") != "true" {
		existingID, err := h.labRepo.CheckDuplicate(r.Context(), &lr)
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

	if err := h.labRepo.Create(r.Context(), &lr); err != nil {
		h.logger.Error("create lab result", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, lr)
}

// HandleExportPDF returns 501 as lab PDF export is not yet implemented.
func (h *LabHandler) HandleExportPDF(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, map[string]string{
		"error":   "not_implemented",
		"message": "pdf export coming soon",
	})
}

// HandleGet returns a single lab result with its values.
func (h *LabHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
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

	labID, err := uuid.Parse(chi.URLParam(r, "labID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_lab_id"))
		return
	}

	lr, err := h.labRepo.GetByID(r.Context(), labID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if lr.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	writeJSON(w, http.StatusOK, lr)
}

// HandleUpdate updates a lab result using versioning.
func (h *LabHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
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

	labID, err := uuid.Parse(chi.URLParam(r, "labID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_lab_id"))
		return
	}

	existing, err := h.labRepo.GetByID(r.Context(), labID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if err := json.NewDecoder(r.Body).Decode(existing); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if err := h.labRepo.Update(r.Context(), existing); err != nil {
		h.logger.Error("update lab result", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, existing)
}

// HandleDelete soft-deletes a lab result.
func (h *LabHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
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

	labID, err := uuid.Parse(chi.URLParam(r, "labID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_lab_id"))
		return
	}

	existing, err := h.labRepo.GetByID(r.Context(), labID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if err := h.labRepo.SoftDelete(r.Context(), labID); err != nil {
		h.logger.Error("delete lab result", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
