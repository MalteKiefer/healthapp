package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/crypto"
	"github.com/healthvault/healthvault/internal/domain/user"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// AuthHandler handles authentication endpoints.
type AuthHandler struct {
	userRepo     user.Repository
	tokenService *crypto.TokenService
	logger       *zap.Logger
	defaultQuota int64
}

func NewAuthHandler(repo user.Repository, ts *crypto.TokenService, logger *zap.Logger, defaultQuotaMB int) *AuthHandler {
	return &AuthHandler{
		userRepo:     repo,
		tokenService: ts,
		logger:       logger,
		defaultQuota: int64(defaultQuotaMB) * 1024 * 1024,
	}
}

// ── Request/Response Types ──────────────────────────────────────────

type registerInitRequest struct {
	Email string `json:"email"`
}

type registerInitResponse struct {
	PEKSalt  string `json:"pek_salt"`
	AuthSalt string `json:"auth_salt"`
}

type registerCompleteRequest struct {
	Email             string `json:"email"`
	DisplayName       string `json:"display_name"`
	AuthHash          string `json:"auth_hash"`
	IdentityPubkey    string `json:"identity_pubkey"`
	IdentityPrivkeyEnc string `json:"identity_privkey_enc"`
	SigningPubkey      string `json:"signing_pubkey"`
	SigningPrivkeyEnc  string `json:"signing_privkey_enc"`
	RecoveryCodeHashes []string `json:"recovery_code_hashes"`
}

type loginRequest struct {
	Email    string `json:"email"`
	AuthHash string `json:"auth_hash"`
}

type loginResponse struct {
	AccessToken        string  `json:"access_token"`
	RefreshToken       string  `json:"refresh_token"`
	ExpiresAt          int64   `json:"expires_at"`
	UserID             string  `json:"user_id"`
	RequiresTOTP       bool    `json:"requires_totp"`
	PEKSalt            string  `json:"pek_salt"`
	IdentityPrivkeyEnc string  `json:"identity_privkey_enc"`
	SigningPrivkeyEnc  string  `json:"signing_privkey_enc"`
}

type login2FARequest struct {
	UserID string `json:"user_id"`
	Code   string `json:"code"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// ── Handlers ────────────────────────────────────────────────────────

// HandleRegisterInit handles Step 1: generates salts for the client.
func (h *AuthHandler) HandleRegisterInit(w http.ResponseWriter, r *http.Request) {
	var req registerInitRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.Email == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("email_required"))
		return
	}

	// Check if email already exists
	if _, err := h.userRepo.GetByEmail(r.Context(), req.Email); err == nil {
		writeJSON(w, http.StatusConflict, errorResponse("email_already_registered"))
		return
	}

	pekSalt, err := crypto.GenerateSalt(16)
	if err != nil {
		h.logger.Error("generate pek_salt", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	authSalt, err := crypto.GenerateSalt(16)
	if err != nil {
		h.logger.Error("generate auth_salt", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, registerInitResponse{
		PEKSalt:  pekSalt,
		AuthSalt: authSalt,
	})
}

// HandleRegisterComplete handles Step 2: creates the user account.
func (h *AuthHandler) HandleRegisterComplete(w http.ResponseWriter, r *http.Request) {
	var req registerCompleteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.Email == "" || req.DisplayName == "" || req.AuthHash == "" ||
		req.IdentityPubkey == "" || req.IdentityPrivkeyEnc == "" ||
		req.SigningPubkey == "" || req.SigningPrivkeyEnc == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("missing_required_fields"))
		return
	}

	if len(req.RecoveryCodeHashes) != 10 {
		writeJSON(w, http.StatusBadRequest, errorResponse("exactly_10_recovery_codes_required"))
		return
	}

	// Hash the auth_hash again server-side for storage
	storedHash, err := crypto.HashArgon2id(req.AuthHash)
	if err != nil {
		h.logger.Error("hash auth_hash", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Generate salts (the client already derived from these, but we also store them)
	pekSalt, err := crypto.GenerateSalt(16)
	if err != nil {
		h.logger.Error("generate pek_salt", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	authSalt, err := crypto.GenerateSalt(16)
	if err != nil {
		h.logger.Error("generate auth_salt", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	u := &user.User{
		Email:              req.Email,
		DisplayName:        req.DisplayName,
		AuthHash:           storedHash,
		PEKSalt:            pekSalt,
		AuthSalt:           authSalt,
		IdentityPubkey:     req.IdentityPubkey,
		IdentityPrivkeyEnc: req.IdentityPrivkeyEnc,
		SigningPubkey:       req.SigningPubkey,
		SigningPrivkeyEnc:  req.SigningPrivkeyEnc,
		Role:               "user",
	}

	if err := h.userRepo.Create(r.Context(), u); err != nil {
		h.logger.Error("create user", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Store recovery code hashes
	if err := h.userRepo.StoreRecoveryCodes(r.Context(), u.ID, req.RecoveryCodeHashes); err != nil {
		h.logger.Error("store recovery codes", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Initialize storage quota
	if err := h.userRepo.InitStorage(r.Context(), u.ID, h.defaultQuota); err != nil {
		h.logger.Error("init storage", zap.Error(err))
	}

	// Initialize default preferences
	if err := h.userRepo.UpsertPreferences(r.Context(), &user.Preferences{
		UserID:           u.ID,
		Language:         "en",
		DateFormat:       "DMY",
		WeightUnit:       "kg",
		HeightUnit:       "cm",
		TemperatureUnit:  "celsius",
		BloodGlucoseUnit: "mmol_l",
		WeekStart:        "monday",
		Timezone:         "UTC",
	}); err != nil {
		h.logger.Error("init preferences", zap.Error(err))
	}

	writeJSON(w, http.StatusCreated, map[string]string{
		"id":    u.ID.String(),
		"email": u.Email,
	})
}

// HandleLogin authenticates a user and returns tokens.
func (h *AuthHandler) HandleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	u, err := h.userRepo.GetByEmail(r.Context(), req.Email)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_credentials"))
			return
		}
		h.logger.Error("get user", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if u.IsDisabled {
		writeJSON(w, http.StatusForbidden, errorResponse("account_disabled"))
		return
	}

	// Verify auth hash
	valid, err := crypto.VerifyArgon2id(req.AuthHash, u.AuthHash)
	if err != nil || !valid {
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_credentials"))
		return
	}

	// If 2FA enabled, return partial response requiring TOTP
	if u.TOTPEnabled {
		writeJSON(w, http.StatusOK, loginResponse{
			UserID:       u.ID.String(),
			RequiresTOTP: true,
		})
		return
	}

	h.completeLogin(w, r, u)
}

// HandleLogin2FA verifies TOTP code after password is confirmed.
func (h *AuthHandler) HandleLogin2FA(w http.ResponseWriter, r *http.Request) {
	var req login2FARequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	userID, err := uuid.Parse(req.UserID)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_user_id"))
		return
	}

	u, err := h.userRepo.GetByID(r.Context(), userID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_credentials"))
		return
	}

	// TODO: verify TOTP code against u.TOTPSecretEnc using pquerna/otp
	_ = req.Code

	h.completeLogin(w, r, u)
}

// HandleRefresh exchanges a refresh token for a new token pair.
func (h *AuthHandler) HandleRefresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	claims, err := h.tokenService.VerifyToken(r.Context(), req.RefreshToken)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_refresh_token"))
		return
	}

	if claims.Type != "refresh" {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_a_refresh_token"))
		return
	}

	// Deny old refresh token
	if err := h.tokenService.DenyToken(r.Context(), claims.ID, time.Until(claims.ExpiresAt.Time)); err != nil {
		h.logger.Error("deny old refresh token", zap.Error(err))
	}

	// Generate new pair
	pair, err := h.tokenService.GenerateTokenPair(claims.UserID, claims.Role)
	if err != nil {
		h.logger.Error("generate token pair", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"access_token":  pair.AccessToken,
		"refresh_token": pair.RefreshToken,
		"expires_at":    pair.ExpiresAt,
	})
}

// HandleLogout denies the current token and revokes the session.
func (h *AuthHandler) HandleLogout(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	// Add token to denylist
	if err := h.tokenService.DenyToken(r.Context(), claims.ID, time.Until(claims.ExpiresAt.Time)); err != nil {
		h.logger.Error("deny token", zap.Error(err))
	}

	// Revoke session in database
	session, err := h.userRepo.GetSessionByJTI(r.Context(), claims.ID)
	if err == nil {
		if err := h.userRepo.RevokeSession(r.Context(), session.ID); err != nil {
			h.logger.Error("revoke session", zap.Error(err))
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "logged_out"})
}

// ── Recovery ─────────────────────────────────────────────────────

type recoveryRequest struct {
	Email        string `json:"email"`
	RecoveryCode string `json:"recovery_code"`
}

// HandleRecovery verifies a recovery code and returns a new token pair.
func (h *AuthHandler) HandleRecovery(w http.ResponseWriter, r *http.Request) {
	var req recoveryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.Email == "" || req.RecoveryCode == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("email_and_recovery_code_required"))
		return
	}

	u, err := h.userRepo.GetByEmail(r.Context(), req.Email)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_credentials"))
		return
	}

	if u.IsDisabled {
		writeJSON(w, http.StatusForbidden, errorResponse("account_disabled"))
		return
	}

	codes, err := h.userRepo.GetUnusedRecoveryCodes(r.Context(), u.ID)
	if err != nil {
		h.logger.Error("get recovery codes", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	var matchedCode *user.RecoveryCode
	for i := range codes {
		valid, verr := crypto.VerifyArgon2id(req.RecoveryCode, codes[i].CodeHash)
		if verr != nil {
			continue
		}
		if valid {
			matchedCode = &codes[i]
			break
		}
	}

	if matchedCode == nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_recovery_code"))
		return
	}

	if err := h.userRepo.MarkRecoveryCodeUsed(r.Context(), matchedCode.ID); err != nil {
		h.logger.Error("mark recovery code used", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	h.completeLogin(w, r, u)
}

func (h *AuthHandler) completeLogin(w http.ResponseWriter, r *http.Request, u *user.User) {
	pair, err := h.tokenService.GenerateTokenPair(u.ID, u.Role)
	if err != nil {
		h.logger.Error("generate tokens", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Create session record
	session := &user.Session{
		UserID:    u.ID,
		JTI:       pair.JTI,
		DeviceHint: r.UserAgent(),
		IPAddress: r.RemoteAddr,
		ExpiresAt: time.Now().UTC().Add(7 * 24 * time.Hour),
	}
	if err := h.userRepo.CreateSession(r.Context(), session); err != nil {
		h.logger.Error("create session", zap.Error(err))
	}

	writeJSON(w, http.StatusOK, loginResponse{
		AccessToken:        pair.AccessToken,
		RefreshToken:       pair.RefreshToken,
		ExpiresAt:          pair.ExpiresAt,
		UserID:             u.ID.String(),
		PEKSalt:            u.PEKSalt,
		IdentityPrivkeyEnc: u.IdentityPrivkeyEnc,
		SigningPrivkeyEnc:  u.SigningPrivkeyEnc,
	})
}
