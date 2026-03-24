package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/contacts"
	"github.com/healthvault/healthvault/internal/domain/profiles"
)

// ContactHandler handles medical contact endpoints.
type ContactHandler struct {
	contactRepo contacts.Repository
	profileRepo profiles.Repository
	logger      *zap.Logger
}

func NewContactHandler(cr contacts.Repository, pr profiles.Repository, logger *zap.Logger) *ContactHandler {
	return &ContactHandler{contactRepo: cr, profileRepo: pr, logger: logger}
}

// HandleList returns contacts for a profile.
func (h *ContactHandler) HandleList(w http.ResponseWriter, r *http.Request) {
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

	items, err := h.contactRepo.List(r.Context(), profileID)
	if err != nil {
		h.logger.Error("list contacts", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
	})
}

// HandleCreate creates a new medical contact.
func (h *ContactHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
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

	var c contacts.Contact
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if c.Name == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("name_required"))
		return
	}

	c.ProfileID = profileID

	if err := h.contactRepo.Create(r.Context(), &c); err != nil {
		h.logger.Error("create contact", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, c)
}

// HandleUpdate patches a medical contact.
func (h *ContactHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
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

	contactID, err := uuid.Parse(chi.URLParam(r, "contactID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_contact_id"))
		return
	}

	existing, err := h.contactRepo.GetByID(r.Context(), contactID)
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

	if err := h.contactRepo.Update(r.Context(), existing); err != nil {
		h.logger.Error("update contact", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, existing)
}

// HandleDelete soft-deletes a medical contact.
func (h *ContactHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
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

	contactID, err := uuid.Parse(chi.URLParam(r, "contactID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_contact_id"))
		return
	}

	existing, err := h.contactRepo.GetByID(r.Context(), contactID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if err := h.contactRepo.SoftDelete(r.Context(), contactID); err != nil {
		h.logger.Error("delete contact", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
