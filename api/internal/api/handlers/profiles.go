package handlers

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
)

// ProfileHandler handles profile endpoints.
type ProfileHandler struct {
	repo   profiles.Repository
	logger *zap.Logger
}

func NewProfileHandler(repo profiles.Repository, logger *zap.Logger) *ProfileHandler {
	return &ProfileHandler{
		repo:   repo,
		logger: logger,
	}
}

// ── Request/Response Types ──────────────────────────────────────────

type createProfileRequest struct {
	DisplayName    string  `json:"display_name"`
	DateOfBirth    *string `json:"date_of_birth,omitempty"`
	BiologicalSex  string  `json:"biological_sex,omitempty"`
	BloodType      *string `json:"blood_type,omitempty"`
	RhesusFactor   *string `json:"rhesus_factor,omitempty"`
	AvatarColor    string  `json:"avatar_color,omitempty"`
	AvatarImageEnc []byte  `json:"avatar_image_enc,omitempty"`
}

type updateProfileRequest struct {
	DisplayName           *string `json:"display_name,omitempty"`
	DateOfBirth           *string `json:"date_of_birth,omitempty"`
	BiologicalSex         *string `json:"biological_sex,omitempty"`
	BloodType             *string `json:"blood_type,omitempty"`
	RhesusFactor          *string `json:"rhesus_factor,omitempty"`
	AvatarColor           *string `json:"avatar_color,omitempty"`
	AvatarImageEnc        []byte  `json:"avatar_image_enc,omitempty"`
	OnboardingCompletedAt *bool   `json:"onboarding_completed_at,omitempty"`
}

// ── Handlers ────────────────────────────────────────────────────────

// HandleList returns all profiles accessible by the authenticated user.
func (h *ProfileHandler) HandleList(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	list, err := h.repo.GetAccessibleByUserID(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("list profiles", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if list == nil {
		list = []profiles.Profile{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": list,
		"total": len(list),
	})
}

// HandleCreate creates a new profile owned by the authenticated user.
func (h *ProfileHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	var req createProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.DisplayName == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("display_name_required"))
		return
	}

	p := &profiles.Profile{
		OwnerUserID:   claims.UserID,
		DisplayName:   req.DisplayName,
		BiologicalSex: req.BiologicalSex,
		BloodType:     req.BloodType,
		RhesusFactor:  req.RhesusFactor,
		AvatarImageEnc: req.AvatarImageEnc,
	}

	if req.DateOfBirth != nil {
		dob, err := time.Parse("2006-01-02", *req.DateOfBirth)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, errorResponse("invalid_date_of_birth"))
			return
		}
		p.DateOfBirth = &dob
	}

	// Auto-generate avatar color if not provided.
	if req.AvatarColor != "" {
		p.AvatarColor = req.AvatarColor
	} else {
		p.AvatarColor = generateAvatarColor()
	}

	if err := h.repo.Create(r.Context(), p); err != nil {
		h.logger.Error("create profile", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.Header().Set("Location", fmt.Sprintf("/api/v1/profiles/%s", p.ID))
	writeJSON(w, http.StatusCreated, p)
}

// HandleGet returns a single profile by ID.
func (h *ProfileHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
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

	hasAccess, err := h.repo.HasAccess(r.Context(), profileID, claims.UserID)
	if err != nil {
		h.logger.Error("check access", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	p, err := h.repo.GetByID(r.Context(), profileID)
	if err != nil {
		h.logger.Error("get profile", zap.Error(err))
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}

	writeJSON(w, http.StatusOK, p)
}

// HandleUpdate patches profile fields.
func (h *ProfileHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
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

	hasAccess, err := h.repo.HasAccess(r.Context(), profileID, claims.UserID)
	if err != nil {
		h.logger.Error("check access", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	p, err := h.repo.GetByID(r.Context(), profileID)
	if err != nil {
		h.logger.Error("get profile for update", zap.Error(err))
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}

	var req updateProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.DisplayName != nil {
		p.DisplayName = *req.DisplayName
	}
	if req.DateOfBirth != nil {
		dob, err := time.Parse("2006-01-02", *req.DateOfBirth)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, errorResponse("invalid_date_of_birth"))
			return
		}
		p.DateOfBirth = &dob
	}
	if req.BiologicalSex != nil {
		p.BiologicalSex = *req.BiologicalSex
	}
	if req.BloodType != nil {
		p.BloodType = req.BloodType
	}
	if req.RhesusFactor != nil {
		p.RhesusFactor = req.RhesusFactor
	}
	if req.AvatarColor != nil {
		p.AvatarColor = *req.AvatarColor
	}
	if req.AvatarImageEnc != nil {
		p.AvatarImageEnc = req.AvatarImageEnc
	}
	if req.OnboardingCompletedAt != nil && *req.OnboardingCompletedAt {
		now := time.Now().UTC()
		p.OnboardingCompletedAt = &now
	}

	if err := h.repo.Update(r.Context(), p); err != nil {
		h.logger.Error("update profile", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, p)
}

// HandleDelete permanently deletes a profile. Only the owner may delete.
func (h *ProfileHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
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

	p, err := h.repo.GetByID(r.Context(), profileID)
	if err != nil {
		h.logger.Error("get profile for delete", zap.Error(err))
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}

	if p.OwnerUserID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	if err := h.repo.Delete(r.Context(), profileID); err != nil {
		h.logger.Error("delete profile", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleArchive soft-archives a profile.
func (h *ProfileHandler) HandleArchive(w http.ResponseWriter, r *http.Request) {
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

	hasAccess, err := h.repo.HasAccess(r.Context(), profileID, claims.UserID)
	if err != nil {
		h.logger.Error("check access", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	if err := h.repo.Archive(r.Context(), profileID); err != nil {
		h.logger.Error("archive profile", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "archived"})
}

// HandleUnarchive removes the archive flag from a profile.
func (h *ProfileHandler) HandleUnarchive(w http.ResponseWriter, r *http.Request) {
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

	hasAccess, err := h.repo.HasAccess(r.Context(), profileID, claims.UserID)
	if err != nil {
		h.logger.Error("check access", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	if err := h.repo.Unarchive(r.Context(), profileID); err != nil {
		h.logger.Error("unarchive profile", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "unarchived"})
}

// ── Helpers ─────────────────────────────────────────────────────────

// generateAvatarColor returns a random hex color string.
func generateAvatarColor() string {
	b := make([]byte, 3)
	if _, err := rand.Read(b); err != nil {
		return "#4A90D9"
	}
	return fmt.Sprintf("#%02X%02X%02X", b[0], b[1], b[2])
}
