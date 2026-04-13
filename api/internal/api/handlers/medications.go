package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/medications"
	"github.com/healthvault/healthvault/internal/domain/profiles"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// MedicationHandler handles medication endpoints.
type MedicationHandler struct {
	medRepo     medications.Repository
	profileRepo profiles.Repository
	logger      *zap.Logger
}

func NewMedicationHandler(mr medications.Repository, pr profiles.Repository, logger *zap.Logger) *MedicationHandler {
	return &MedicationHandler{medRepo: mr, profileRepo: pr, logger: logger}
}

// HandleList returns medications for a profile with optional pagination.
func (h *MedicationHandler) HandleList(w http.ResponseWriter, r *http.Request) {
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

	filter := medications.ListFilter{
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
	if r.URL.Query().Get("active") == "true" {
		filter.ActiveOnly = true
	}

	items, total, err := h.medRepo.List(r.Context(), filter)
	if err != nil {
		h.logger.Error("list medications", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}

// HandleCreate creates a new medication record.
func (h *MedicationHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
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

	var m medications.Medication
	if err := json.NewDecoder(r.Body).Decode(&m); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if m.Name == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("name_required"))
		return
	}

	m.ProfileID = profileID

	if err := h.medRepo.Create(r.Context(), &m); err != nil {
		h.logger.Error("create medication", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, m)
}

// HandleGet returns a single medication by ID.
func (h *MedicationHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
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

	medID, err := uuid.Parse(chi.URLParam(r, "medicationID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_medication_id"))
		return
	}

	m, err := h.medRepo.GetByID(r.Context(), medID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get medication", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if m.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	writeJSON(w, http.StatusOK, m)
}

// HandleUpdate performs a versioned update of a medication.
func (h *MedicationHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
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

	medID, err := uuid.Parse(chi.URLParam(r, "medicationID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_medication_id"))
		return
	}

	existing, err := h.medRepo.GetByID(r.Context(), medID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get medication", zap.Error(err))
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

	if err := h.medRepo.Update(r.Context(), existing); err != nil {
		h.logger.Error("update medication", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, existing)
}

// HandleDelete soft-deletes a medication.
func (h *MedicationHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
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

	medID, err := uuid.Parse(chi.URLParam(r, "medicationID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_medication_id"))
		return
	}

	existing, err := h.medRepo.GetByID(r.Context(), medID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get medication", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if err := h.medRepo.SoftDelete(r.Context(), medID); err != nil {
		h.logger.Error("delete medication", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleActive is deprecated — filtering is now done client-side after
// decrypting the full list.
func (h *MedicationHandler) HandleActive(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{
		"error":   "endpoint_removed",
		"message": "This endpoint has been removed. Use the list endpoint with client-side filtering instead.",
	})
}

// HandleCreateIntake records a medication intake event.
func (h *MedicationHandler) HandleCreateIntake(w http.ResponseWriter, r *http.Request) {
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

	medID, err := uuid.Parse(chi.URLParam(r, "medicationID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_medication_id"))
		return
	}

	// Verify medication exists and belongs to profile
	med, err := h.medRepo.GetByID(r.Context(), medID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get medication", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if med.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	var intake medications.MedicationIntake
	if err := json.NewDecoder(r.Body).Decode(&intake); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	intake.MedicationID = medID
	intake.ProfileID = profileID

	if err := h.medRepo.CreateIntake(r.Context(), &intake); err != nil {
		h.logger.Error("create medication intake", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, intake)
}

// HandleListIntake returns intake records for a medication.
func (h *MedicationHandler) HandleListIntake(w http.ResponseWriter, r *http.Request) {
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

	medID, err := uuid.Parse(chi.URLParam(r, "medicationID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_medication_id"))
		return
	}

	// Verify medication exists and belongs to profile
	med, err := h.medRepo.GetByID(r.Context(), medID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get medication", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if med.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
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

	items, total, err := h.medRepo.ListIntake(r.Context(), medID, limit, offset)
	if err != nil {
		h.logger.Error("list medication intakes", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}

// HandleUpdateIntake updates an existing medication intake record.
func (h *MedicationHandler) HandleUpdateIntake(w http.ResponseWriter, r *http.Request) {
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

	medID, err := uuid.Parse(chi.URLParam(r, "medicationID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_medication_id"))
		return
	}

	intakeID, err := uuid.Parse(chi.URLParam(r, "intakeID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_intake_id"))
		return
	}

	// Verify medication exists and belongs to profile
	med, err := h.medRepo.GetByID(r.Context(), medID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("medication_not_found"))
			return
		}
		h.logger.Error("get medication", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if med.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("medication_not_found"))
		return
	}

	existing, err := h.medRepo.GetIntakeByID(r.Context(), intakeID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("intake_not_found"))
			return
		}
		h.logger.Error("get medication intake", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if existing.MedicationID != medID {
		writeJSON(w, http.StatusNotFound, errorResponse("intake_not_found"))
		return
	}

	if err := json.NewDecoder(r.Body).Decode(existing); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	// Preserve immutable fields
	existing.ID = intakeID
	existing.MedicationID = medID
	existing.ProfileID = profileID

	if err := h.medRepo.UpdateIntake(r.Context(), existing); err != nil {
		h.logger.Error("update medication intake", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, existing)
}

// HandleDeleteIntake deletes a medication intake record.
func (h *MedicationHandler) HandleDeleteIntake(w http.ResponseWriter, r *http.Request) {
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

	medID, err := uuid.Parse(chi.URLParam(r, "medicationID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_medication_id"))
		return
	}

	intakeID, err := uuid.Parse(chi.URLParam(r, "intakeID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_intake_id"))
		return
	}

	// Verify medication exists and belongs to profile
	med, err := h.medRepo.GetByID(r.Context(), medID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("medication_not_found"))
			return
		}
		h.logger.Error("get medication", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if med.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("medication_not_found"))
		return
	}

	// Verify intake belongs to medication
	existing, err := h.medRepo.GetIntakeByID(r.Context(), intakeID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("intake_not_found"))
			return
		}
		h.logger.Error("get medication intake", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if existing.MedicationID != medID {
		writeJSON(w, http.StatusNotFound, errorResponse("intake_not_found"))
		return
	}

	if err := h.medRepo.DeleteIntake(r.Context(), intakeID); err != nil {
		h.logger.Error("delete medication intake", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}



// HandleAdherence is deprecated — adherence is now computed client-side.
func (h *MedicationHandler) HandleAdherence(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{
		"error":   "endpoint_removed",
		"message": "This endpoint has been removed. Use client-side rendering instead.",
	})
}
