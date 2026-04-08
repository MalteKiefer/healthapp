package handlers

import (
	"crypto/rand"
	"encoding/base32"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/pquerna/otp/totp"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/crypto"
	"github.com/healthvault/healthvault/internal/domain/user"
)

// TOTPHandler handles TOTP two-factor authentication endpoints.
type TOTPHandler struct {
	userRepo user.Repository
	rdb      *redis.Client
	logger   *zap.Logger
	encKey   []byte // 32-byte AES-256 key for encrypting TOTP secrets at rest
}

func NewTOTPHandler(repo user.Repository, rdb *redis.Client, logger *zap.Logger, encKey []byte) *TOTPHandler {
	return &TOTPHandler{userRepo: repo, rdb: rdb, logger: logger, encKey: encKey}
}

// totpReplayTTL is the window during which a TOTP code is considered valid
// (the library uses ±1 period = 90 s). Used codes are cached for this duration
// so they cannot be replayed.
const totpReplayTTL = 90 * time.Second

// checkTOTPReplay returns true if the code was already used for the given user.
// It sets the key atomically so that concurrent requests are also blocked.
func (h *TOTPHandler) checkTOTPReplay(r *http.Request, userID, code string) (bool, error) {
	key := fmt.Sprintf("totp_used:%s:%s", userID, code)
	set, err := h.rdb.SetNX(r.Context(), key, "1", totpReplayTTL).Result() //nolint:staticcheck
	if err != nil {
		return false, err
	}
	// SetNX returns true if the key was set (code NOT used before).
	return !set, nil
}

// ── Request/Response Types ──────────────────────────────────────────

type totpSetupResponse struct {
	Secret          string `json:"secret"`
	ProvisioningURI string `json:"provisioning_uri"`
}

type totpEnableRequest struct {
	Code string `json:"code"`
}

type totpDisableRequest struct {
	Code            string `json:"code"`
	CurrentAuthHash string `json:"current_auth_hash"`
}

type recoveryCodesResponse struct {
	Codes []string `json:"codes"`
}

// HandleSetup generates a TOTP secret and returns the provisioning URI and base32 secret.
// GET /2fa/setup
func (h *TOTPHandler) HandleSetup(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	u, err := h.userRepo.GetByID(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("get user for totp setup", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	key, err := totp.Generate(totp.GenerateOpts{
		Issuer:      "HealthVault",
		AccountName: u.Email,
	})
	if err != nil {
		h.logger.Error("generate totp key", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Encrypt the TOTP secret with AES-256-GCM before storing.
	secret := key.Secret()
	encryptedSecret, err := crypto.EncryptAESGCM(secret, h.encKey)
	if err != nil {
		h.logger.Error("encrypt totp secret", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	u.TOTPSecretEnc = &encryptedSecret
	if err := h.userRepo.Update(r.Context(), u); err != nil {
		h.logger.Error("store totp secret", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, totpSetupResponse{
		Secret:          key.Secret(),
		ProvisioningURI: key.URL(),
	})
}

// HandleEnable verifies a TOTP code and enables 2FA on the account.
// POST /2fa/enable
func (h *TOTPHandler) HandleEnable(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	var req totpEnableRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.Code == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("code_required"))
		return
	}

	u, err := h.userRepo.GetByID(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("get user for totp enable", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if u.TOTPSecretEnc == nil || *u.TOTPSecretEnc == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("totp_not_setup"))
		return
	}

	secret, err := crypto.DecryptAESGCM(*u.TOTPSecretEnc, h.encKey)
	if err != nil {
		h.logger.Error("decrypt totp secret for enable", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Replay protection: reject codes that have already been used.
	alreadyUsed, err := h.checkTOTPReplay(r, claims.UserID.String(), req.Code)
	if err != nil {
		h.logger.Error("check totp replay", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if alreadyUsed {
		writeJSON(w, http.StatusTooManyRequests, errorResponse("totp_code_already_used"))
		return
	}

	valid := totp.Validate(req.Code, secret)
	if !valid {
		// Code invalid — remove the replay marker so the user isn't locked
		// out of a code they never successfully used.
		h.rdb.Del(r.Context(), fmt.Sprintf("totp_used:%s:%s", claims.UserID.String(), req.Code))
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_totp_code"))
		return
	}

	u.TOTPEnabled = true
	if err := h.userRepo.Update(r.Context(), u); err != nil {
		h.logger.Error("enable totp", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "totp_enabled"})
}

// HandleDisable verifies the current TOTP code and disables 2FA.
// POST /2fa/disable
func (h *TOTPHandler) HandleDisable(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	var req totpDisableRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.Code == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("code_required"))
		return
	}

	if req.CurrentAuthHash == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("current_auth_hash_required"))
		return
	}

	u, err := h.userRepo.GetByID(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("get user for totp disable", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Verify the user's current password before allowing 2FA disable.
	pwValid, err := crypto.VerifyArgon2id(req.CurrentAuthHash, u.AuthHash)
	if err != nil || !pwValid {
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_credentials"))
		return
	}

	if !u.TOTPEnabled || u.TOTPSecretEnc == nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("totp_not_enabled"))
		return
	}

	secret, err := crypto.DecryptAESGCM(*u.TOTPSecretEnc, h.encKey)
	if err != nil {
		h.logger.Error("decrypt totp secret for disable", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Replay protection: reject codes that have already been used.
	alreadyUsed, err := h.checkTOTPReplay(r, claims.UserID.String(), req.Code)
	if err != nil {
		h.logger.Error("check totp replay", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if alreadyUsed {
		writeJSON(w, http.StatusTooManyRequests, errorResponse("totp_code_already_used"))
		return
	}

	valid := totp.Validate(req.Code, secret)
	if !valid {
		// Code invalid — remove the replay marker so the user isn't locked
		// out of a code they never successfully used.
		h.rdb.Del(r.Context(), fmt.Sprintf("totp_used:%s:%s", claims.UserID.String(), req.Code))
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_totp_code"))
		return
	}

	u.TOTPEnabled = false
	if err := h.userRepo.Update(r.Context(), u); err != nil {
		h.logger.Error("disable totp", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "totp_disabled"})
}

// HandleRegenerateRecoveryCodes generates 10 new recovery codes, hashes them with
// Argon2id, stores the hashes, and returns the plaintext codes once.
// GET /2fa/recovery-codes
func (h *TOTPHandler) HandleRegenerateRecoveryCodes(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	const codeCount = 10
	const codeBytes = 10 // 10 random bytes -> 16-char base32 string

	plaintextCodes := make([]string, codeCount)
	codeHashes := make([]string, codeCount)

	for i := 0; i < codeCount; i++ {
		raw := make([]byte, codeBytes)
		if _, err := rand.Read(raw); err != nil {
			h.logger.Error("generate recovery code entropy", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}

		code := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(raw)
		plaintextCodes[i] = code

		hash, err := crypto.HashArgon2id(code)
		if err != nil {
			h.logger.Error("hash recovery code", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		codeHashes[i] = hash
	}

	// Delete existing recovery codes and store new ones
	if err := h.userRepo.DeleteRecoveryCodes(r.Context(), claims.UserID); err != nil {
		h.logger.Error("delete old recovery codes", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if err := h.userRepo.StoreRecoveryCodes(r.Context(), claims.UserID, codeHashes); err != nil {
		h.logger.Error("store recovery codes", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, recoveryCodesResponse{
		Codes: plaintextCodes,
	})
}
