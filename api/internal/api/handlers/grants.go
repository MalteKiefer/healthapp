package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
)

// GrantHandler handles profile key grant, key-rotation and transfer endpoints.
type GrantHandler struct {
	db          *pgxpool.Pool
	profileRepo profiles.Repository
	logger      *zap.Logger
}

func NewGrantHandler(db *pgxpool.Pool, pr profiles.Repository, logger *zap.Logger) *GrantHandler {
	return &GrantHandler{db: db, profileRepo: pr, logger: logger}
}

// ── Request Types ───────────────────────────────────────────────────

type createGrantRequest struct {
	EncryptedKey   string  `json:"encrypted_key"`
	GrantSignature string  `json:"grant_signature"`
	GranteeUserID  string  `json:"grantee_user_id"`
	ViaFamilyID    *string `json:"via_family_id,omitempty"`
}

type transferRequest struct {
	NewOwnerUserID string `json:"new_owner_user_id"`
}

// ── Handlers ────────────────────────────────────────────────────────

// HandleCreateGrant creates a new profile key grant.
// POST /profiles/{profileID}/grants
func (h *GrantHandler) HandleCreateGrant(w http.ResponseWriter, r *http.Request) {
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

	// Only the owner can create grants
	p, err := h.profileRepo.GetByID(r.Context(), profileID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}
	if p.OwnerUserID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("owner_required"))
		return
	}

	var req createGrantRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	// GrantSignature is intentionally optional — signing keys are ECDH (not
	// ECDSA) so clients can't produce real signatures yet. Stage 2 follow-up.
	if req.EncryptedKey == "" || req.GranteeUserID == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("missing_required_fields"))
		return
	}

	granteeID, err := uuid.Parse(req.GranteeUserID)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_grantee_user_id"))
		return
	}

	var viaFamilyID *uuid.UUID
	if req.ViaFamilyID != nil && *req.ViaFamilyID != "" {
		fid, err := uuid.Parse(*req.ViaFamilyID)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, errorResponse("invalid_via_family_id"))
			return
		}
		// Both caller (owner) and grantee must be active members of that family.
		var count int
		err = h.db.QueryRow(r.Context(), `
			SELECT COUNT(*) FROM family_memberships
			WHERE family_id = $1 AND user_id = ANY($2) AND left_at IS NULL`,
			fid, []uuid.UUID{claims.UserID, granteeID}).Scan(&count)
		if err != nil {
			h.logger.Error("check family membership", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		if count < 2 {
			writeJSON(w, http.StatusForbidden, errorResponse("not_in_family"))
			return
		}
		viaFamilyID = &fid
	}

	grant := &profiles.KeyGrant{
		ProfileID:       profileID,
		GranteeUserID:   granteeID,
		EncryptedKey:    req.EncryptedKey,
		GrantSignature:  req.GrantSignature,
		GrantedByUserID: claims.UserID,
		GrantedAt:       time.Now().UTC(),
		ViaFamilyID:     viaFamilyID,
	}

	if err := h.profileRepo.CreateKeyGrant(r.Context(), grant); err != nil {
		h.logger.Error("create key grant", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, grant)
}

// HandleRevokeGrant revokes a key grant for a specific grantee.
// DELETE /profiles/{profileID}/grants/{grantUserID}
func (h *GrantHandler) HandleRevokeGrant(w http.ResponseWriter, r *http.Request) {
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

	// Only the owner can revoke grants
	p, err := h.profileRepo.GetByID(r.Context(), profileID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}
	if p.OwnerUserID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("owner_required"))
		return
	}

	grantUserID, err := uuid.Parse(chi.URLParam(r, "grantUserID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_grant_user_id"))
		return
	}

	if err := h.profileRepo.RevokeKeyGrant(r.Context(), profileID, grantUserID); err != nil {
		h.logger.Error("revoke key grant", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleListGrants lists active key grants for a profile. Owner only.
// GET /profiles/{profileID}/grants
func (h *GrantHandler) HandleListGrants(w http.ResponseWriter, r *http.Request) {
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

	p, err := h.profileRepo.GetByID(r.Context(), profileID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}
	if p.OwnerUserID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("owner_required"))
		return
	}

	// Join grants with users to get display_name/email/identity_pubkey so the
	// client can both show who has access and unwrap the grantee's perspective.
	rows, err := h.db.Query(r.Context(), `
		SELECT g.id, g.grantee_user_id, g.granted_by_user_id, g.granted_at,
		       g.encrypted_key, g.via_family_id,
		       u.email, COALESCE(u.display_name, ''), u.identity_pubkey
		FROM profile_key_grants g
		JOIN users u ON u.id = g.grantee_user_id
		WHERE g.profile_id = $1 AND g.revoked_at IS NULL
		ORDER BY g.granted_at ASC`, profileID)
	if err != nil {
		h.logger.Error("list grants", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	type grantRow struct {
		ID              uuid.UUID  `json:"id"`
		GranteeUserID   uuid.UUID  `json:"grantee_user_id"`
		GrantedByUserID uuid.UUID  `json:"granted_by_user_id"`
		GrantedAt       time.Time  `json:"granted_at"`
		EncryptedKey    string     `json:"encrypted_key"`
		ViaFamilyID     *uuid.UUID `json:"via_family_id,omitempty"`
		Email           string     `json:"email"`
		DisplayName     string     `json:"display_name"`
		IdentityPubkey  string     `json:"identity_pubkey"`
	}
	items := make([]grantRow, 0)
	for rows.Next() {
		var g grantRow
		if err := rows.Scan(&g.ID, &g.GranteeUserID, &g.GrantedByUserID, &g.GrantedAt,
			&g.EncryptedKey, &g.ViaFamilyID, &g.Email, &g.DisplayName, &g.IdentityPubkey); err != nil {
			h.logger.Error("scan grant row", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		items = append(items, g)
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"items": items, "total": len(items)})
}

// HandleGetMyGrant returns the caller's active grant for a profile, with the
// granter's identity_pubkey so the client can unwrap the encrypted_key.
// GET /profiles/{profileID}/my-grant
func (h *GrantHandler) HandleGetMyGrant(w http.ResponseWriter, r *http.Request) {
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

	// The grant acts as the access gate; no additional HasAccess check needed.
	type myGrantResp struct {
		ProfileID              uuid.UUID  `json:"profile_id"`
		EncryptedKey           string     `json:"encrypted_key"`
		GrantedByUserID        uuid.UUID  `json:"granted_by_user_id"`
		GranterIdentityPubkey  string     `json:"granter_identity_pubkey"`
		ViaFamilyID            *uuid.UUID `json:"via_family_id,omitempty"`
		GrantedAt              time.Time  `json:"granted_at"`
	}
	var resp myGrantResp
	resp.ProfileID = profileID
	err = h.db.QueryRow(r.Context(), `
		SELECT g.encrypted_key, g.granted_by_user_id, u.identity_pubkey,
		       g.via_family_id, g.granted_at
		FROM profile_key_grants g
		JOIN users u ON u.id = g.granted_by_user_id
		WHERE g.profile_id = $1 AND g.grantee_user_id = $2 AND g.revoked_at IS NULL
		LIMIT 1`, profileID, claims.UserID).Scan(
		&resp.EncryptedKey, &resp.GrantedByUserID, &resp.GranterIdentityPubkey,
		&resp.ViaFamilyID, &resp.GrantedAt,
	)
	if err != nil {
		// no row → caller has no active grant for this profile
		writeJSON(w, http.StatusNotFound, errorResponse("no_grant"))
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

// HandleKeyRotation returns 501 as key rotation requires client-side re-encryption.
// POST /profiles/{profileID}/key-rotation
func (h *GrantHandler) HandleKeyRotation(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, map[string]string{
		"error":   "not_implemented",
		"message": "key rotation requires client-side re-encryption",
	})
}

// HandleTransfer transfers profile ownership to another user.
// POST /profiles/{profileID}/transfer
func (h *GrantHandler) HandleTransfer(w http.ResponseWriter, r *http.Request) {
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

	// Only the current owner can transfer
	p, err := h.profileRepo.GetByID(r.Context(), profileID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorResponse("profile_not_found"))
		return
	}
	if p.OwnerUserID != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("owner_required"))
		return
	}

	var req transferRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	newOwnerID, err := uuid.Parse(req.NewOwnerUserID)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_new_owner_user_id"))
		return
	}

	if newOwnerID == claims.UserID {
		writeJSON(w, http.StatusBadRequest, errorResponse("cannot_transfer_to_self"))
		return
	}

	// Verify target user exists and is active
	var targetExists bool
	err = h.db.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND is_disabled = false)`, newOwnerID).Scan(&targetExists)
	if err != nil {
		h.logger.Error("check target user", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if !targetExists {
		writeJSON(w, http.StatusBadRequest, errorResponse("target_user_not_found"))
		return
	}

	// Verify current user is the actual owner (direct DB check)
	var currentOwner uuid.UUID
	err = h.db.QueryRow(r.Context(), `SELECT owner_user_id FROM profiles WHERE id = $1`, profileID).Scan(&currentOwner)
	if err != nil {
		h.logger.Error("check profile owner", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if currentOwner != claims.UserID {
		writeJSON(w, http.StatusForbidden, errorResponse("only_owner_can_transfer"))
		return
	}

	now := time.Now().UTC()
	_, err = h.db.Exec(r.Context(),
		`UPDATE profiles SET owner_user_id = $2, updated_at = $3 WHERE id = $1`,
		profileID, newOwnerID, now,
	)
	if err != nil {
		h.logger.Error("transfer profile", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"status":       "transferred",
		"profile_id":   profileID,
		"new_owner_id": newOwnerID,
	})
}
