package handlers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"net/mail"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/pquerna/otp/totp"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/crypto"
	"github.com/healthvault/healthvault/internal/domain/user"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// AuthHandler handles authentication endpoints.
type AuthHandler struct {
	userRepo      user.Repository
	tokenService  *crypto.TokenService
	db            *pgxpool.Pool
	rdb           *redis.Client
	logger        *zap.Logger
	defaultQuota  int64
	totpEncKey    []byte // 32-byte AES-256 key for decrypting TOTP secrets during 2FA login
	secureCookies bool   // true unless hostname is localhost/127.0.0.1
}

func NewAuthHandler(repo user.Repository, ts *crypto.TokenService, db *pgxpool.Pool, rdb *redis.Client, logger *zap.Logger, defaultQuotaMB int, totpEncKey []byte, hostname string) *AuthHandler {
	secure := !strings.Contains(hostname, "localhost") && !strings.Contains(hostname, "127.0.0.1")
	return &AuthHandler{
		userRepo:      repo,
		tokenService:  ts,
		db:            db,
		rdb:           rdb,
		logger:        logger,
		defaultQuota:  int64(defaultQuotaMB) * 1024 * 1024,
		totpEncKey:    totpEncKey,
		secureCookies: secure,
	}
}

// setAuthCookies writes httpOnly access and refresh token cookies.
func setAuthCookies(w http.ResponseWriter, accessToken, refreshToken string, secure bool) {
	http.SetCookie(w, &http.Cookie{
		Name:     "access_token",
		Value:    accessToken,
		Path:     "/",
		MaxAge:   900,
		HttpOnly: true,
		Secure:   secure,
		SameSite: http.SameSiteStrictMode,
	})
	http.SetCookie(w, &http.Cookie{
		Name:     "refresh_token",
		Value:    refreshToken,
		Path:     "/api/v1/auth/refresh",
		MaxAge:   604800,
		HttpOnly: true,
		Secure:   secure,
		SameSite: http.SameSiteStrictMode,
	})
}

// clearAuthCookies removes auth cookies by setting MaxAge to -1.
func clearAuthCookies(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     "access_token",
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
	})
	http.SetCookie(w, &http.Cookie{
		Name:     "refresh_token",
		Value:    "",
		Path:     "/api/v1/auth/refresh",
		MaxAge:   -1,
		HttpOnly: true,
	})
}

// writeAuditLog inserts an audit log entry. Errors are logged but never block
// the calling request.
func (h *AuthHandler) writeAuditLog(ctx context.Context, r *http.Request, userID uuid.UUID, action, resource string, resourceID *uuid.UUID, metadata map[string]interface{}) {
	var metaJSON []byte
	if metadata != nil {
		var err error
		metaJSON, err = json.Marshal(metadata)
		if err != nil {
			h.logger.Error("marshal audit metadata", zap.Error(err))
		}
	}
	_, err := h.db.Exec(ctx,
		`INSERT INTO audit_log (user_id, action, resource, resource_id, ip_address, user_agent, metadata)
		 VALUES ($1, $2, $3, $4, $5::inet, $6, $7)`,
		userID, action, resource, resourceID, r.RemoteAddr, r.UserAgent(), metaJSON,
	)
	if err != nil {
		h.logger.Error("write audit log", zap.String("action", action), zap.Error(err))
	}
}

// ── Request/Response Types ──────────────────────────────────────────

type registerInitRequest struct {
	Email       string `json:"email"`
	InviteToken string `json:"invite_token"`
}

type registerInitResponse struct {
	PEKSalt  string `json:"pek_salt"`
	AuthSalt string `json:"auth_salt"`
}

type registerCompleteRequest struct {
	Email              string   `json:"email"`
	DisplayName        string   `json:"display_name"`
	AuthHash           string   `json:"auth_hash"`
	IdentityPubkey     string   `json:"identity_pubkey"`
	IdentityPrivkeyEnc string   `json:"identity_privkey_enc"`
	SigningPubkey      string   `json:"signing_pubkey"`
	SigningPrivkeyEnc  string   `json:"signing_privkey_enc"`
	RecoveryCodes      []string `json:"recovery_codes"`
	InviteToken        string   `json:"invite_token"`
}

type loginRequest struct {
	Email    string `json:"email"`
	AuthHash string `json:"auth_hash"`
}

type loginResponse struct {
	ExpiresAt          int64  `json:"expires_at"`
	UserID             string `json:"user_id"`
	Role               string `json:"role"`
	RequiresTOTP       bool   `json:"requires_totp"`
	PEKSalt            string `json:"pek_salt"`
	ChallengeToken     string `json:"challenge_token,omitempty"`
	IdentityPrivkeyEnc string `json:"identity_privkey_enc"`
	SigningPrivkeyEnc  string `json:"signing_privkey_enc"`
}

type login2FARequest struct {
	UserID         string `json:"user_id"`
	Code           string `json:"code"`
	ChallengeToken string `json:"challenge_token"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// ── Handlers ────────────────────────────────────────────────────────

// registrationMode reads the registration mode from DB first (admin-configurable
// without restart), then falls back to the REGISTRATION_MODE env var, defaulting
// to "invite_only".
func (h *AuthHandler) registrationMode(ctx context.Context) string {
	if dbMode := h.getSetting(ctx, "registration_mode", ""); dbMode != "" {
		return dbMode
	}
	if envMode := os.Getenv("REGISTRATION_MODE"); envMode != "" {
		return envMode
	}
	return "invite_only"
}

// HandleRegisterInit handles Step 1: generates salts for the client.
func (h *AuthHandler) HandleRegisterInit(w http.ResponseWriter, r *http.Request) {
	// Enforce registration mode early so clients get a clear error.
	mode := h.registrationMode(r.Context())
	if mode == "closed" {
		writeJSON(w, http.StatusForbidden, errorResponse("registration_closed"))
		return
	}

	var req registerInitRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.Email == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("email_required"))
		return
	}
	addr, err := mail.ParseAddress(req.Email)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_email"))
		return
	}
	req.Email = strings.ToLower(addr.Address)

	// When invite_only, require a valid invite token up front.
	if mode == "invite_only" {
		if req.InviteToken == "" {
			writeJSON(w, http.StatusForbidden, errorResponse("invite_token_required"))
			return
		}
		var inviteEmail *string
		err := h.db.QueryRow(r.Context(),
			`SELECT email FROM registration_invites WHERE token = $1 AND used_at IS NULL`,
			req.InviteToken,
		).Scan(&inviteEmail)
		if err != nil {
			writeJSON(w, http.StatusForbidden, errorResponse("invalid_invite_token"))
			return
		}
		// If the invite is scoped to an email, verify it matches.
		if inviteEmail != nil && *inviteEmail != "" && *inviteEmail != req.Email {
			writeJSON(w, http.StatusForbidden, errorResponse("invite_email_mismatch"))
			return
		}
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
	mode := h.registrationMode(r.Context())
	if mode == "closed" {
		writeJSON(w, http.StatusForbidden, errorResponse("registration_closed"))
		return
	}

	var req registerCompleteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.Email == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("email_required"))
		return
	}
	{
		addr, err := mail.ParseAddress(req.Email)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, errorResponse("invalid_email"))
			return
		}
		req.Email = strings.ToLower(addr.Address)
	}

	if req.DisplayName == "" || req.AuthHash == "" ||
		req.IdentityPubkey == "" || req.IdentityPrivkeyEnc == "" ||
		req.SigningPubkey == "" || req.SigningPrivkeyEnc == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("missing_required_fields"))
		return
	}

	if len(req.RecoveryCodes) != 10 {
		writeJSON(w, http.StatusBadRequest, errorResponse("exactly_10_recovery_codes_required"))
		return
	}

	// When invite_only, re-validate the invite token (it could have been used
	// between the init and complete steps).
	if mode == "invite_only" {
		if req.InviteToken == "" {
			writeJSON(w, http.StatusForbidden, errorResponse("invite_token_required"))
			return
		}
		var inviteEmail *string
		err := h.db.QueryRow(r.Context(),
			`SELECT email FROM registration_invites WHERE token = $1 AND used_at IS NULL`,
			req.InviteToken,
		).Scan(&inviteEmail)
		if err != nil {
			writeJSON(w, http.StatusForbidden, errorResponse("invalid_invite_token"))
			return
		}
		if inviteEmail != nil && *inviteEmail != "" && *inviteEmail != req.Email {
			writeJSON(w, http.StatusForbidden, errorResponse("invite_email_mismatch"))
			return
		}
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
		SigningPubkey:      req.SigningPubkey,
		SigningPrivkeyEnc:  req.SigningPrivkeyEnc,
		Role:               "user",
	}

	if err := h.userRepo.Create(r.Context(), u); err != nil {
		h.logger.Error("create user", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Mark the invite as used now that the user has been created.
	if mode == "invite_only" && req.InviteToken != "" {
		if _, err := h.db.Exec(r.Context(),
			`UPDATE registration_invites SET used_at = NOW(), used_by = $1 WHERE token = $2 AND used_at IS NULL`,
			u.ID, req.InviteToken,
		); err != nil {
			h.logger.Error("mark invite used", zap.Error(err))
			// Non-fatal: user was already created. Log and continue.
		}
	}

	// Hash recovery codes with Argon2id before storing (matches HandleRecovery's VerifyArgon2id)
	hashedCodes := make([]string, 0, len(req.RecoveryCodes))
	for _, code := range req.RecoveryCodes {
		codeHash, err := crypto.HashArgon2id(code)
		if err != nil {
			h.logger.Error("hash recovery code", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		hashedCodes = append(hashedCodes, codeHash)
	}
	if err := h.userRepo.StoreRecoveryCodes(r.Context(), u.ID, hashedCodes); err != nil {
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

	h.writeAuditLog(r.Context(), r, u.ID, "auth.register", "user", &u.ID, map[string]interface{}{
		"email": u.Email,
	})

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

	if req.Email == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("email_required"))
		return
	}
	{
		addr, err := mail.ParseAddress(req.Email)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, errorResponse("invalid_email"))
			return
		}
		req.Email = strings.ToLower(addr.Address)
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

	// If 2FA enabled, generate a short-lived challenge token that binds the
	// password verification step to the upcoming TOTP step. This prevents an
	// attacker from calling /auth/login/2fa directly with a stolen user_id.
	if u.TOTPEnabled {
		challengeBytes := make([]byte, 32)
		if _, err := rand.Read(challengeBytes); err != nil {
			h.logger.Error("generate 2fa challenge token", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		challengeToken := hex.EncodeToString(challengeBytes)

		// Store in Redis: key = "2fa_challenge:{token}", value = userID, TTL = 5 min
		if err := h.rdb.Set(r.Context(), "2fa_challenge:"+challengeToken, u.ID.String(), 5*time.Minute).Err(); err != nil {
			h.logger.Error("store 2fa challenge token", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}

		writeJSON(w, http.StatusOK, loginResponse{
			UserID:         u.ID.String(),
			RequiresTOTP:   true,
			PEKSalt:        u.PEKSalt,
			ChallengeToken: challengeToken,
		})
		return
	}

	h.completeLogin(w, r, u)
}

// HandleLogin2FA verifies TOTP code after password is confirmed.
// The caller must provide the challenge_token that was returned by HandleLogin;
// this token expires after 5 minutes and is invalidated after 5 failed TOTP
// attempts, binding the 2FA step to a prior successful password verification.
func (h *AuthHandler) HandleLogin2FA(w http.ResponseWriter, r *http.Request) {
	var req login2FARequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.ChallengeToken == "" {
		writeJSON(w, http.StatusUnauthorized, errorResponse("challenge_token_required"))
		return
	}

	// Per-challenge-token rate limiting: track failed attempts independently of
	// IP so that distributing requests across IPs cannot bypass the limit.
	// Check and increment the attempt counter BEFORE touching the challenge token
	// to avoid leaking whether the token is valid to an attacker.
	attemptKey := "totp_attempts:" + req.ChallengeToken
	attempts, _ := h.rdb.Incr(r.Context(), attemptKey).Result()
	if attempts == 1 {
		// Set expiry only on the first increment so the window is anchored to
		// the first attempt rather than reset on every call.
		h.rdb.Expire(r.Context(), attemptKey, 15*time.Minute)
	}
	if attempts > 5 {
		// Too many attempts: destroy the challenge token so the attacker cannot
		// continue even if they switch IPs, then clean up the counter.
		h.rdb.Del(r.Context(), "2fa_challenge:"+req.ChallengeToken)
		h.rdb.Del(r.Context(), attemptKey)
		writeJSON(w, http.StatusTooManyRequests, errorResponse("too_many_attempts"))
		return
	}

	// Fetch the challenge token from Redis without deleting it yet — deletion
	// happens explicitly below so we can keep it alive across failed attempts
	// up to the limit enforced above.
	userIDStr, err := h.rdb.Get(r.Context(), "2fa_challenge:"+req.ChallengeToken).Result()
	if err != nil {
		// Token not found or expired
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_or_expired_challenge"))
		return
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_credentials"))
		return
	}

	u, err := h.userRepo.GetByID(r.Context(), userID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_credentials"))
		return
	}

	if !u.TOTPEnabled || u.TOTPSecretEnc == nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("2fa_not_enabled"))
		return
	}

	secret, err := crypto.DecryptAESGCM(*u.TOTPSecretEnc, h.totpEncKey)
	if err != nil {
		h.logger.Error("decrypt totp secret for 2fa login", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	valid := totp.Validate(req.Code, secret)
	if !valid {
		writeJSON(w, http.StatusUnauthorized, errorResponse("invalid_totp_code"))
		return
	}

	// TOTP validated successfully: consume the challenge token (single-use) and
	// clean up the attempt counter.
	h.rdb.Del(r.Context(), "2fa_challenge:"+req.ChallengeToken)
	h.rdb.Del(r.Context(), attemptKey)

	h.completeLogin(w, r, u)
}

// HandleRefresh exchanges a refresh token for a new token pair.
func (h *AuthHandler) HandleRefresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	// Body may be empty when the refresh token comes from a cookie.
	_ = json.NewDecoder(r.Body).Decode(&req)

	// Try request body first (API clients), then cookie.
	if req.RefreshToken == "" {
		if cookie, err := r.Cookie("refresh_token"); err == nil {
			req.RefreshToken = cookie.Value
		}
	}

	if req.RefreshToken == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("refresh_token_required"))
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

	// Verify user still exists and is active
	u, err := h.userRepo.GetByID(r.Context(), claims.UserID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse("user_not_found"))
		return
	}

	if u.IsDisabled {
		writeJSON(w, http.StatusForbidden, errorResponse("account_disabled"))
		return
	}

	// Deny old refresh token
	if err := h.tokenService.DenyToken(r.Context(), claims.ID, time.Until(claims.ExpiresAt.Time)); err != nil {
		h.logger.Error("deny old refresh token", zap.Error(err))
	}

	// Generate new pair using current role from database
	pair, err := h.tokenService.GenerateTokenPair(u.ID, u.Role)
	if err != nil {
		h.logger.Error("generate token pair", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	setAuthCookies(w, pair.AccessToken, pair.RefreshToken, h.secureCookies)

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"expires_at": pair.ExpiresAt,
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

	clearAuthCookies(w)

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

	if req.Email == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("email_required"))
		return
	}
	{
		addr, err := mail.ParseAddress(req.Email)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, errorResponse("invalid_email"))
			return
		}
		req.Email = strings.ToLower(addr.Address)
	}
	if req.RecoveryCode == "" {
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

// HandleGetPolicy returns the public password policy so login/register pages
// can enforce the same minimum passphrase length configured by the admin.
// GET /auth/policy  (no JWT required)
func (h *AuthHandler) HandleGetPolicy(w http.ResponseWriter, r *http.Request) {
	var minLen int
	err := h.db.QueryRow(r.Context(),
		`SELECT COALESCE((SELECT value FROM instance_settings WHERE key = 'min_passphrase_length'), '12')::int`,
	).Scan(&minLen)
	if err != nil {
		minLen = 12
	}

	// Read password requirements
	requireUpper := h.getSetting(r.Context(), "require_uppercase", "false")
	requireLower := h.getSetting(r.Context(), "require_lowercase", "false")
	requireNumbers := h.getSetting(r.Context(), "require_numbers", "false")
	requireSymbols := h.getSetting(r.Context(), "require_symbols", "false")

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"min_passphrase_length": minLen,
		"require_uppercase":     requireUpper == "true",
		"require_lowercase":     requireLower == "true",
		"require_numbers":       requireNumbers == "true",
		"require_symbols":       requireSymbols == "true",
		"registration_mode":     h.registrationMode(r.Context()),
	})
}

// getSetting reads a single value from instance_settings, returning defaultVal on error.
func (h *AuthHandler) getSetting(ctx context.Context, key, defaultVal string) string {
	var val string
	err := h.db.QueryRow(ctx, `SELECT value FROM instance_settings WHERE key = $1`, key).Scan(&val)
	if err != nil {
		return defaultVal
	}
	return val
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
		UserID:     u.ID,
		JTI:        pair.JTI,
		DeviceHint: r.UserAgent(),
		IPAddress:  r.RemoteAddr,
		ExpiresAt:  time.Now().UTC().Add(7 * 24 * time.Hour),
	}
	if err := h.userRepo.CreateSession(r.Context(), session); err != nil {
		h.logger.Error("create session", zap.Error(err))
	}

	h.writeAuditLog(r.Context(), r, u.ID, "auth.login", "session", nil, map[string]interface{}{
		"email": u.Email,
	})

	setAuthCookies(w, pair.AccessToken, pair.RefreshToken, h.secureCookies)

	writeJSON(w, http.StatusOK, loginResponse{
		ExpiresAt:          pair.ExpiresAt,
		UserID:             u.ID.String(),
		Role:               u.Role,
		PEKSalt:            u.PEKSalt,
		IdentityPrivkeyEnc: u.IdentityPrivkeyEnc,
		SigningPrivkeyEnc:  u.SigningPrivkeyEnc,
	})
}
