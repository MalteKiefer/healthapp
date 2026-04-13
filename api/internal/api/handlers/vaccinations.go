package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
	"github.com/healthvault/healthvault/internal/domain/vaccinations"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// VaccinationHandler handles vaccination endpoints.
type VaccinationHandler struct {
	vaccinationRepo vaccinations.Repository
	profileRepo     profiles.Repository
	logger          *zap.Logger
}

func NewVaccinationHandler(vr vaccinations.Repository, pr profiles.Repository, logger *zap.Logger) *VaccinationHandler {
	return &VaccinationHandler{vaccinationRepo: vr, profileRepo: pr, logger: logger}
}

// HandleList returns vaccinations for a profile with pagination.
func (h *VaccinationHandler) HandleList(w http.ResponseWriter, r *http.Request) {
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

	filter := vaccinations.ListFilter{
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

	items, total, err := h.vaccinationRepo.List(r.Context(), filter)
	if err != nil {
		h.logger.Error("list vaccinations", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}

// HandleCreate creates a new vaccination record.
func (h *VaccinationHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
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

	var v vaccinations.Vaccination
	if err := json.NewDecoder(r.Body).Decode(&v); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	v.ProfileID = profileID
	if v.AdministeredAt.IsZero() {
		v.AdministeredAt = time.Now().UTC()
	}

	if v.VaccineName == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("vaccine_name_required"))
		return
	}

	if err := h.vaccinationRepo.Create(r.Context(), &v); err != nil {
		h.logger.Error("create vaccination", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, v)
}

// HandleGet returns a single vaccination record.
func (h *VaccinationHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
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

	vaccinationID, err := uuid.Parse(chi.URLParam(r, "vaccinationID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_vaccination_id"))
		return
	}

	v, err := h.vaccinationRepo.GetByID(r.Context(), vaccinationID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get vaccination", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if v.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	writeJSON(w, http.StatusOK, v)
}

// HandleUpdate performs a versioned update on a vaccination record.
func (h *VaccinationHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
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

	vaccinationID, err := uuid.Parse(chi.URLParam(r, "vaccinationID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_vaccination_id"))
		return
	}

	existing, err := h.vaccinationRepo.GetByID(r.Context(), vaccinationID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get vaccination", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
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

	if existing.VaccineName == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("vaccine_name_required"))
		return
	}

	if err := h.vaccinationRepo.Update(r.Context(), existing); err != nil {
		h.logger.Error("update vaccination", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, existing)
}

// HandleDelete soft-deletes a vaccination record.
func (h *VaccinationHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
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

	vaccinationID, err := uuid.Parse(chi.URLParam(r, "vaccinationID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_vaccination_id"))
		return
	}

	existing, err := h.vaccinationRepo.GetByID(r.Context(), vaccinationID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get vaccination", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if err := h.vaccinationRepo.SoftDelete(r.Context(), vaccinationID); err != nil {
		h.logger.Error("delete vaccination", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}


// HandleDue is deprecated — filtering is now done client-side after
// decrypting the full list.
func (h *VaccinationHandler) HandleDue(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{
		"error":   "endpoint_removed",
		"message": "This endpoint has been removed. Use the list endpoint with client-side filtering instead.",
	})
}
