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
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
)

// DoctorShareHandler handles temporary doctor access via share links.
//
// Flow:
// 1. Browser generates random 256-bit temp key
// 2. Browser re-encrypts selected records with temp key
// 3. Server stores ciphertext bundle, returns share_id
// 4. Share URL: https://host/share/{share_id}#{base64(tempKey)}
// 5. Fragment (#tempKey) never reaches the server
// 6. Doctor opens URL, browser fetches ciphertext, decrypts with fragment key
// 7. Read-only, expires configurable (max 7 days)
type DoctorShareHandler struct {
	db          *pgxpool.Pool
	profileRepo profiles.Repository
	logger      *zap.Logger
	hostname    string
}

func NewDoctorShareHandler(db *pgxpool.Pool, pr profiles.Repository, logger *zap.Logger, hostname string) *DoctorShareHandler {
	return &DoctorShareHandler{db: db, profileRepo: pr, logger: logger, hostname: hostname}
}

type createShareRequest struct {
	ProfileID     string `json:"profile_id"`
	EncryptedData string `json:"encrypted_data"` // ciphertext bundle encrypted with temp key
	ExpiresInHours int   `json:"expires_in_hours"`
	Label         string `json:"label"` // e.g. "Dr. Weber — Cardiology visit"
}

type shareResponse struct {
	ShareID  string `json:"share_id"`
	ShareURL string `json:"share_url"`
	ExpiresAt string `json:"expires_at"`
}

// HandleCreateShare creates a temporary share link.
// POST /api/v1/profiles/{profileID}/share
func (h *DoctorShareHandler) HandleCreateShare(w http.ResponseWriter, r *http.Request) {
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

	var req createShareRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.EncryptedData == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("encrypted_data_required"))
		return
	}

	// Max 7 days, default 24 hours
	hours := req.ExpiresInHours
	if hours <= 0 {
		hours = 24
	}
	if hours > 168 {
		hours = 168
	}

	// Generate share ID
	shareBytes := make([]byte, 16)
	if _, err := rand.Read(shareBytes); err != nil {
		h.logger.Error("generate share id", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	shareID := hex.EncodeToString(shareBytes)
	expiresAt := time.Now().UTC().Add(time.Duration(hours) * time.Hour)

	// Store the ciphertext bundle
	_, err = h.db.Exec(r.Context(), `
		INSERT INTO doctor_shares (id, share_id, profile_id, created_by, encrypted_data, label, expires_at, created_at)
		VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, NOW())`,
		shareID, profileID, claims.UserID, req.EncryptedData, req.Label, expiresAt)
	if err != nil {
		h.logger.Error("create share", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// The share URL uses a fragment — the server never sees the temp key
	// Example: https://healthvault.home/share/abc123#base64TempKey
	writeJSON(w, http.StatusCreated, shareResponse{
		ShareID:   shareID,
		ShareURL:  "https://" + h.hostname + "/share/" + shareID,
		ExpiresAt: expiresAt.Format(time.RFC3339),
	})
}

// HandleGetShare returns the encrypted data bundle for a share link.
// GET /share/{shareID} — no authentication required
func (h *DoctorShareHandler) HandleGetShare(w http.ResponseWriter, r *http.Request) {
	shareID := chi.URLParam(r, "shareID")
	if shareID == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("share_id_required"))
		return
	}

	var encryptedData string
	var expiresAt time.Time
	var revokedAt *time.Time
	err := h.db.QueryRow(r.Context(), `
		SELECT encrypted_data, expires_at, revoked_at
		FROM doctor_shares WHERE share_id = $1`, shareID).Scan(&encryptedData, &expiresAt, &revokedAt)

	if errors.Is(err, pgx.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, errorResponse("share_not_found"))
		return
	}
	if err != nil {
		h.logger.Error("get share", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if revokedAt != nil {
		writeJSON(w, http.StatusGone, errorResponse("share_revoked"))
		return
	}

	if time.Now().UTC().After(expiresAt) {
		writeJSON(w, http.StatusGone, errorResponse("share_expired"))
		return
	}

	// Record access
	h.db.Exec(r.Context(), `
		INSERT INTO doctor_share_access_log (id, share_id, ip_address, user_agent, accessed_at)
		VALUES (gen_random_uuid(), $1, $2, $3, NOW())`,
		shareID, r.RemoteAddr, r.UserAgent())

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"encrypted_data": encryptedData,
		"expires_at":     expiresAt.Format(time.RFC3339),
	})
}

// HandleRevokeShare revokes a share link immediately.
// DELETE /api/v1/profiles/{profileID}/share/{shareID}
func (h *DoctorShareHandler) HandleRevokeShare(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	shareID := chi.URLParam(r, "shareID")
	_, err := h.db.Exec(r.Context(), `
		UPDATE doctor_shares SET revoked_at = NOW()
		WHERE share_id = $1 AND created_by = $2 AND revoked_at IS NULL`,
		shareID, claims.UserID)
	if err != nil {
		h.logger.Error("revoke share", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleListShares returns active shares for a profile.
// GET /api/v1/profiles/{profileID}/shares
func (h *DoctorShareHandler) HandleListShares(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	profileID, _ := uuid.Parse(chi.URLParam(r, "profileID"))

	rows, err := h.db.Query(r.Context(), `
		SELECT share_id, label, expires_at, revoked_at, created_at
		FROM doctor_shares WHERE profile_id = $1 AND created_by = $2
		ORDER BY created_at DESC LIMIT 50`, profileID, claims.UserID)
	if err != nil {
		h.logger.Error("list shares", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	type shareItem struct {
		ShareID   string     `json:"share_id"`
		Label     string     `json:"label"`
		ExpiresAt string     `json:"expires_at"`
		RevokedAt *string    `json:"revoked_at,omitempty"`
		CreatedAt string     `json:"created_at"`
		Active    bool       `json:"active"`
	}

	var items []shareItem
	for rows.Next() {
		var s shareItem
		var expiresAt, createdAt time.Time
		var revokedAt *time.Time
		if err := rows.Scan(&s.ShareID, &s.Label, &expiresAt, &revokedAt, &createdAt); err != nil {
			continue
		}
		s.ExpiresAt = expiresAt.Format(time.RFC3339)
		s.CreatedAt = createdAt.Format(time.RFC3339)
		s.Active = revokedAt == nil && time.Now().UTC().Before(expiresAt)
		if revokedAt != nil {
			t := revokedAt.Format(time.RFC3339)
			s.RevokedAt = &t
		}
		items = append(items, s)
	}

	if items == nil {
		items = []shareItem{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"items": items})
}
