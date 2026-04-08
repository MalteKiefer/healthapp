package handlers

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/appointments"
	"github.com/healthvault/healthvault/internal/domain/diary"
	"github.com/healthvault/healthvault/internal/domain/profiles"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// AppointmentHandler handles appointment endpoints.
type AppointmentHandler struct {
	apptRepo    appointments.Repository
	diaryRepo   diary.Repository
	profileRepo profiles.Repository
	logger      *zap.Logger
}

func NewAppointmentHandler(ar appointments.Repository, dr diary.Repository, pr profiles.Repository, logger *zap.Logger) *AppointmentHandler {
	return &AppointmentHandler{apptRepo: ar, diaryRepo: dr, profileRepo: pr, logger: logger}
}

// HandleList returns appointments for a profile.
func (h *AppointmentHandler) HandleList(w http.ResponseWriter, r *http.Request) {
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

	items, err := h.apptRepo.List(r.Context(), profileID)
	if err != nil {
		h.logger.Error("list appointments", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": len(items),
	})
}

// HandleCreate creates a new appointment.
func (h *AppointmentHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
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

	var a appointments.Appointment
	if err := json.NewDecoder(r.Body).Decode(&a); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if a.Title == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("title_required"))
		return
	}

	a.ProfileID = profileID

	if err := h.apptRepo.Create(r.Context(), &a); err != nil {
		h.logger.Error("create appointment", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, a)
}

// HandleGetUpcoming is deprecated — filtering is now done client-side after
// decrypting the full list.
func (h *AppointmentHandler) HandleGetUpcoming(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{
		"error":   "endpoint_removed",
		"message": "This endpoint has been removed. Use the list endpoint with client-side filtering instead.",
	})
}

// HandleUpdate patches an appointment.
func (h *AppointmentHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
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

	apptID, err := uuid.Parse(chi.URLParam(r, "apptID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_appointment_id"))
		return
	}

	existing, err := h.apptRepo.GetByID(r.Context(), apptID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get appointment", zap.Error(err))
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

	if existing.Title == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("title_required"))
		return
	}

	if err := h.apptRepo.Update(r.Context(), existing); err != nil {
		h.logger.Error("update appointment", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, existing)
}

// HandleDelete deletes an appointment.
func (h *AppointmentHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
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

	apptID, err := uuid.Parse(chi.URLParam(r, "apptID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_appointment_id"))
		return
	}

	existing, err := h.apptRepo.GetByID(r.Context(), apptID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get appointment", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if err := h.apptRepo.Delete(r.Context(), apptID); err != nil {
		h.logger.Error("delete appointment", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleComplete marks an appointment as completed, optionally linking a diary event.
func (h *AppointmentHandler) HandleComplete(w http.ResponseWriter, r *http.Request) {
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

	apptID, err := uuid.Parse(chi.URLParam(r, "apptID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_appointment_id"))
		return
	}

	existing, err := h.apptRepo.GetByID(r.Context(), apptID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get appointment", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	// Optionally link a diary event
	var body struct {
		DiaryEventID *uuid.UUID `json:"diary_event_id"`
	}
	// Body is optional — empty body (io.EOF) is fine, but malformed JSON is not
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil && !errors.Is(err, io.EOF) {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	// Verify the diary event belongs to the same profile
	if body.DiaryEventID != nil {
		diaryEvent, err := h.diaryRepo.GetByID(r.Context(), *body.DiaryEventID)
		if err != nil {
			if errors.Is(err, postgres.ErrNotFound) {
				writeJSON(w, http.StatusBadRequest, errorResponse("diary_event_not_found"))
				return
			}
			h.logger.Error("get diary event", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		if diaryEvent.ProfileID != profileID {
			writeJSON(w, http.StatusBadRequest, errorResponse("diary_event_not_found"))
			return
		}
	}

	if err := h.apptRepo.Complete(r.Context(), apptID, body.DiaryEventID); err != nil {
		h.logger.Error("complete appointment", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "completed"})
}

// HandleMigrateContent lazily backfills the content_enc column for an
// appointment row. Idempotent: the repo writes only if the column is currently
// NULL, so concurrent clients (e.g. web + mobile) cannot overwrite each other.
// PATCH /profiles/{profileID}/appointments/{appointmentID}/migrate-content
func (h *AppointmentHandler) HandleMigrateContent(w http.ResponseWriter, r *http.Request) {
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

	appointmentID, err := uuid.Parse(chi.URLParam(r, "apptID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_appointment_id"))
		return
	}

	existing, err := h.apptRepo.GetByID(r.Context(), appointmentID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get appointment for migrate", zap.Error(err))
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

	if err := h.apptRepo.SetContentEnc(r.Context(), appointmentID, body.ContentEnc); err != nil {
		h.logger.Error("set content_enc", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
