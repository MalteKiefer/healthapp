package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/family"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// FamilyHandler handles family management endpoints.
type FamilyHandler struct {
	familyRepo family.Repository
	logger     *zap.Logger
}

func NewFamilyHandler(fr family.Repository, logger *zap.Logger) *FamilyHandler {
	return &FamilyHandler{familyRepo: fr, logger: logger}
}

// HandleList returns all families the authenticated user belongs to.
func (h *FamilyHandler) HandleList(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	families, err := h.familyRepo.ListByUserID(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("list families", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": families,
	})
}

// HandleCreate creates a new family and adds the creator as owner.
func (h *FamilyHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}
	if req.Name == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("name_required"))
		return
	}

	f := family.Family{
		Name:      req.Name,
		CreatedBy: claims.UserID,
	}
	if err := h.familyRepo.Create(r.Context(), &f); err != nil {
		h.logger.Error("create family", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Add creator as owner
	m := family.FamilyMembership{
		UserID:   claims.UserID,
		FamilyID: f.ID,
		Role:     "owner",
	}
	if err := h.familyRepo.AddMember(r.Context(), &m); err != nil {
		h.logger.Error("add owner membership", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, f)
}

// HandleGet returns a single family by ID.
func (h *FamilyHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	familyID, err := uuid.Parse(chi.URLParam(r, "familyID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_family_id"))
		return
	}

	if !h.isMember(r, familyID, claims.UserID) {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	f, err := h.familyRepo.GetByID(r.Context(), familyID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get family", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, f)
}

// HandleUpdate updates a family's name. Requires owner or admin role.
func (h *FamilyHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	familyID, err := uuid.Parse(chi.URLParam(r, "familyID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_family_id"))
		return
	}

	if !h.isOwnerOrAdmin(r, familyID, claims.UserID) {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	f, err := h.familyRepo.GetByID(r.Context(), familyID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get family for update", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}
	if req.Name != "" {
		f.Name = req.Name
	}

	if err := h.familyRepo.Update(r.Context(), f); err != nil {
		h.logger.Error("update family", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, f)
}

// HandleInvite generates an invite token for a family. Requires owner or admin role.
func (h *FamilyHandler) HandleInvite(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	familyID, err := uuid.Parse(chi.URLParam(r, "familyID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_family_id"))
		return
	}

	if !h.isOwnerOrAdmin(r, familyID, claims.UserID) {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	token, err := generateToken(32)
	if err != nil {
		h.logger.Error("generate invite token", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	inv := family.FamilyInvite{
		FamilyID:  familyID,
		Token:     token,
		CreatedBy: claims.UserID,
		ExpiresAt: time.Now().UTC().Add(7 * 24 * time.Hour),
	}

	if err := h.familyRepo.CreateInvite(r.Context(), &inv); err != nil {
		h.logger.Error("create invite", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, inv)
}

// HandleAcceptInvite validates a token and adds the authenticated user as a member.
func (h *FamilyHandler) HandleAcceptInvite(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	var req struct {
		Token string `json:"token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Token == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("token_required"))
		return
	}

	inv, err := h.familyRepo.GetInviteByToken(r.Context(), req.Token)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("invite_not_found"))
			return
		}
		h.logger.Error("get invite", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if inv.UsedAt != nil {
		writeJSON(w, http.StatusGone, errorResponse("invite_already_used"))
		return
	}
	if time.Now().UTC().After(inv.ExpiresAt) {
		writeJSON(w, http.StatusGone, errorResponse("invite_expired"))
		return
	}

	// Check that the user is not already a member
	if h.isMember(r, inv.FamilyID, claims.UserID) {
		writeJSON(w, http.StatusConflict, errorResponse("already_member"))
		return
	}

	m := family.FamilyMembership{
		UserID:   claims.UserID,
		FamilyID: inv.FamilyID,
		Role:     "member",
	}
	if err := h.familyRepo.AddMember(r.Context(), &m); err != nil {
		h.logger.Error("add member via invite", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if err := h.familyRepo.UseInvite(r.Context(), inv.ID); err != nil {
		h.logger.Error("mark invite used", zap.Error(err))
	}

	writeJSON(w, http.StatusOK, m)
}

// HandleRemoveMember removes a member from a family. Requires owner or admin role.
func (h *FamilyHandler) HandleRemoveMember(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	familyID, err := uuid.Parse(chi.URLParam(r, "familyID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_family_id"))
		return
	}

	memberID, err := uuid.Parse(chi.URLParam(r, "memberID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_member_id"))
		return
	}

	if !h.isOwnerOrAdmin(r, familyID, claims.UserID) {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	if err := h.familyRepo.RemoveMember(r.Context(), familyID, memberID); err != nil {
		h.logger.Error("remove member", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleDissolve dissolves a family. Requires owner role.
func (h *FamilyHandler) HandleDissolve(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	familyID, err := uuid.Parse(chi.URLParam(r, "familyID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_family_id"))
		return
	}

	if !h.isOwner(r, familyID, claims.UserID) {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	if err := h.familyRepo.Dissolve(r.Context(), familyID); err != nil {
		h.logger.Error("dissolve family", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// ── Helpers ─────────────────────────────────────────────────────────

// generateToken creates a cryptographically random hex token.
func generateToken(nBytes int) (string, error) {
	b := make([]byte, nBytes)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// isMember returns true if the user holds any active membership in the family.
func (h *FamilyHandler) isMember(r *http.Request, familyID, userID uuid.UUID) bool {
	members, err := h.familyRepo.GetMemberships(r.Context(), familyID)
	if err != nil {
		return false
	}
	for _, m := range members {
		if m.UserID == userID {
			return true
		}
	}
	return false
}

// isOwnerOrAdmin returns true if the user is an owner or admin of the family.
func (h *FamilyHandler) isOwnerOrAdmin(r *http.Request, familyID, userID uuid.UUID) bool {
	members, err := h.familyRepo.GetMemberships(r.Context(), familyID)
	if err != nil {
		return false
	}
	for _, m := range members {
		if m.UserID == userID && (m.Role == "owner" || m.Role == "admin") {
			return true
		}
	}
	return false
}

// isOwner returns true if the user is the owner of the family.
func (h *FamilyHandler) isOwner(r *http.Request, familyID, userID uuid.UUID) bool {
	members, err := h.familyRepo.GetMemberships(r.Context(), familyID)
	if err != nil {
		return false
	}
	for _, m := range members {
		if m.UserID == userID && m.Role == "owner" {
			return true
		}
	}
	return false
}
