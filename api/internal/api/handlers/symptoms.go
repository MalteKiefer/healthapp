package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
	"github.com/healthvault/healthvault/internal/domain/symptoms"
)

// SymptomHandler handles symptom endpoints.
type SymptomHandler struct {
	symptomRepo symptoms.Repository
	profileRepo profiles.Repository
	logger      *zap.Logger
}

func NewSymptomHandler(sr symptoms.Repository, pr profiles.Repository, logger *zap.Logger) *SymptomHandler {
	return &SymptomHandler{symptomRepo: sr, profileRepo: pr, logger: logger}
}

// HandleList returns symptom records for a profile with pagination.
func (h *SymptomHandler) HandleList(w http.ResponseWriter, r *http.Request) {
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

	items, total, err := h.symptomRepo.List(r.Context(), profileID, limit, offset)
	if err != nil {
		h.logger.Error("list symptoms", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}

// HandleCreate creates a new symptom record.
func (h *SymptomHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
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

	var s symptoms.SymptomRecord
	if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	s.ProfileID = profileID
	if s.RecordedAt.IsZero() {
		s.RecordedAt = time.Now().UTC()
	}

	if err := h.symptomRepo.Create(r.Context(), &s); err != nil {
		h.logger.Error("create symptom", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, s)
}

// HandleGet returns a single symptom record.
func (h *SymptomHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
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

	symptomID, err := uuid.Parse(chi.URLParam(r, "symptomID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_symptom_id"))
		return
	}

	s, err := h.symptomRepo.GetByID(r.Context(), symptomID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if s.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	writeJSON(w, http.StatusOK, s)
}

// HandleUpdate patches a symptom record.
func (h *SymptomHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
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

	symptomID, err := uuid.Parse(chi.URLParam(r, "symptomID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_symptom_id"))
		return
	}

	existing, err := h.symptomRepo.GetByID(r.Context(), symptomID)
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

	if err := h.symptomRepo.Update(r.Context(), existing); err != nil {
		h.logger.Error("update symptom", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, existing)
}

// HandleChart returns 501 as symptom charting is not yet implemented.
func (h *SymptomHandler) HandleChart(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, map[string]string{
		"error":   "not_implemented",
		"message": "symptom charting coming soon",
	})
}

// HandleDelete soft-deletes a symptom record.
func (h *SymptomHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
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

	symptomID, err := uuid.Parse(chi.URLParam(r, "symptomID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_symptom_id"))
		return
	}

	existing, err := h.symptomRepo.GetByID(r.Context(), symptomID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if err := h.symptomRepo.SoftDelete(r.Context(), symptomID); err != nil {
		h.logger.Error("delete symptom", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
