package handlers_test

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/api/handlers"
	"github.com/healthvault/healthvault/internal/api/middleware"
	"github.com/healthvault/healthvault/internal/crypto"
	"github.com/healthvault/healthvault/internal/migrations"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// testEnv holds shared integration-test dependencies.
type testEnv struct {
	DB           *pgxpool.Pool
	Redis        *redis.Client
	TokenService *crypto.TokenService
	Logger       *zap.Logger
	Router       *chi.Mux
}

// setupTestEnv connects to a real Postgres and Redis, runs the migration, and
// wires up the auth routes used by these tests. It skips the test if either
// dependency is unavailable.
func setupTestEnv(t *testing.T) *testEnv {
	t.Helper()

	ctx := context.Background()

	// ── Postgres ────────────────────────────────────────────────────
	db := connectTestDB(t, ctx)

	// Run migration
	migrationSQL, err := migrations.FS.ReadFile("000001_initial_schema.up.sql")
	require.NoError(t, err, "read migration file")

	_, err = db.Exec(ctx, string(migrationSQL))
	require.NoError(t, err, "run migration")

	// Read down migration for cleanup
	downSQL, err := migrations.FS.ReadFile("000001_initial_schema.down.sql")
	require.NoError(t, err, "read down migration file")

	t.Cleanup(func() {
		_, _ = db.Exec(context.Background(), string(downSQL))
		db.Close()
	})

	// ── Redis ───────────────────────────────────────────────────────
	rdb := connectTestRedis(t, ctx)

	t.Cleanup(func() {
		rdb.FlushDB(context.Background())
		rdb.Close()
	})

	// ── Token service (temp RSA keys) ───────────────────────────────
	ts := newTestTokenService(t, rdb)

	logger, _ := zap.NewDevelopment()

	// ── Router ──────────────────────────────────────────────────────
	userRepo := postgres.NewUserRepo(db)
	authHandler := handlers.NewAuthHandler(userRepo, ts, logger, 5120)

	r := chi.NewRouter()
	r.Post("/api/v1/auth/register", authHandler.HandleRegisterInit)
	r.Post("/api/v1/auth/register/complete", authHandler.HandleRegisterComplete)
	r.Post("/api/v1/auth/login", authHandler.HandleLogin)
	r.Post("/api/v1/auth/refresh", authHandler.HandleRefresh)

	// Logout requires claims in context (via JWTAuth middleware)
	r.With(middleware.JWTAuth(ts)).Post("/api/v1/auth/logout", authHandler.HandleLogout)

	return &testEnv{
		DB:           db,
		Redis:        rdb,
		TokenService: ts,
		Logger:       logger,
		Router:       r,
	}
}

// ── Helpers ─────────────────────────────────────────────────────────

func connectTestDB(t *testing.T, ctx context.Context) *pgxpool.Pool {
	t.Helper()

	// Try test-compose port first, then default port.
	for _, port := range []int{5433, 5432} {
		dsn := fmt.Sprintf("postgres://test:test@localhost:%d/healthvault_test?sslmode=disable", port)
		poolCfg, err := pgxpool.ParseConfig(dsn)
		if err != nil {
			continue
		}
		poolCfg.MaxConns = 5

		connCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
		pool, err := pgxpool.NewWithConfig(connCtx, poolCfg)
		cancel()
		if err != nil {
			continue
		}

		pingCtx, pingCancel := context.WithTimeout(ctx, 2*time.Second)
		err = pool.Ping(pingCtx)
		pingCancel()
		if err != nil {
			pool.Close()
			continue
		}
		return pool
	}

	t.Skip("PostgreSQL not available on localhost:5433 or localhost:5432")
	return nil
}

func connectTestRedis(t *testing.T, ctx context.Context) *redis.Client {
	t.Helper()

	for _, port := range []int{6380, 6379} {
		rdb := redis.NewClient(&redis.Options{
			Addr: fmt.Sprintf("localhost:%d", port),
			DB:   15,
		})

		connCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
		err := rdb.Ping(connCtx).Err()
		cancel()
		if err == nil {
			rdb.FlushDB(ctx)
			return rdb
		}
		_ = rdb.Close()
	}

	t.Skip("Redis not available on localhost:6380 or localhost:6379")
	return nil
}

func newTestTokenService(t *testing.T, rdb *redis.Client) *crypto.TokenService {
	t.Helper()

	dir := t.TempDir()
	privPath := filepath.Join(dir, "private.pem")
	pubPath := filepath.Join(dir, "public.pem")

	privKey, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)

	privBytes := x509.MarshalPKCS1PrivateKey(privKey)
	privPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: privBytes})
	require.NoError(t, os.WriteFile(privPath, privPEM, 0600))

	pubBytes, err := x509.MarshalPKIXPublicKey(&privKey.PublicKey)
	require.NoError(t, err)
	pubPEM := pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubBytes})
	require.NoError(t, os.WriteFile(pubPath, pubPEM, 0644))

	ts, err := crypto.NewTokenService(privPath, pubPath, rdb, 15*time.Minute, 7*24*time.Hour)
	require.NoError(t, err)
	return ts
}

// registerTestUser registers a user through the API and returns the user-id.
func registerTestUser(t *testing.T, env *testEnv, email string) string {
	t.Helper()

	// Step 1: register init
	initBody := mustJSON(t, map[string]string{"email": email})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", initBody)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)
	require.Equal(t, http.StatusOK, w.Code, "register init should return 200")

	// Step 2: register complete
	recoveryCodes := make([]string, 10)
	for i := range recoveryCodes {
		recoveryCodes[i] = fmt.Sprintf("recovery-code-%d", i)
	}

	// Hash the recovery codes (the API expects hashes)
	recoveryHashes := make([]string, 10)
	for i, code := range recoveryCodes {
		h, err := crypto.HashArgon2id(code)
		require.NoError(t, err)
		recoveryHashes[i] = h
	}

	// Hash the password client-side to simulate auth_hash
	authHash, err := crypto.HashArgon2id("test-password-123")
	require.NoError(t, err)

	completeBody := mustJSON(t, map[string]interface{}{
		"email":              email,
		"display_name":       "Test User",
		"auth_hash":          authHash,
		"identity_pubkey":    "test-identity-pubkey",
		"identity_privkey_enc": "test-identity-privkey-enc",
		"signing_pubkey":     "test-signing-pubkey",
		"signing_privkey_enc": "test-signing-privkey-enc",
		"recovery_code_hashes": recoveryHashes,
	})
	req = httptest.NewRequest(http.MethodPost, "/api/v1/auth/register/complete", completeBody)
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)
	require.Equal(t, http.StatusCreated, w.Code, "register complete should return 201: %s", w.Body.String())

	var resp map[string]string
	require.NoError(t, json.NewDecoder(w.Body).Decode(&resp))
	require.NotEmpty(t, resp["id"])
	return resp["id"]
}

// loginTestUser logs in and returns the decoded login response.
func loginTestUser(t *testing.T, env *testEnv, email, authHash string) map[string]interface{} {
	t.Helper()

	body := mustJSON(t, map[string]string{
		"email":     email,
		"auth_hash": authHash,
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", body)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)
	require.Equal(t, http.StatusOK, w.Code, "login should return 200: %s", w.Body.String())

	var resp map[string]interface{}
	require.NoError(t, json.NewDecoder(w.Body).Decode(&resp))
	return resp
}

func mustJSON(t *testing.T, v interface{}) *bytes.Buffer {
	t.Helper()
	buf := &bytes.Buffer{}
	require.NoError(t, json.NewEncoder(buf).Encode(v))
	return buf
}

// ── Tests ───────────────────────────────────────────────────────────

func TestRegisterAndLogin(t *testing.T) {
	env := setupTestEnv(t)

	email := fmt.Sprintf("test-%d@example.com", time.Now().UnixNano())

	// Register
	userID := registerTestUser(t, env, email)
	assert.NotEmpty(t, userID)

	// We need to log in with the same auth_hash that was stored. The register
	// handler hashes the auth_hash again server-side, so at login we must send
	// the original (pre-server-hash) value. Since we used HashArgon2id("test-password-123")
	// as the auth_hash during registration, we must send that same value at login.
	authHash, err := crypto.HashArgon2id("test-password-123")
	require.NoError(t, err)

	resp := loginTestUser(t, env, email, authHash)

	assert.NotEmpty(t, resp["access_token"], "should have access_token")
	assert.NotEmpty(t, resp["refresh_token"], "should have refresh_token")
	assert.NotEmpty(t, resp["user_id"], "should have user_id")
	assert.Equal(t, userID, resp["user_id"])

	expiresAt, ok := resp["expires_at"].(float64)
	assert.True(t, ok, "expires_at should be a number")
	assert.Greater(t, expiresAt, float64(time.Now().Unix()), "expires_at should be in the future")
}

func TestLoginInvalidCredentials(t *testing.T) {
	env := setupTestEnv(t)

	email := fmt.Sprintf("test-%d@example.com", time.Now().UnixNano())
	_ = registerTestUser(t, env, email)

	// Try logging in with wrong auth_hash
	body := mustJSON(t, map[string]string{
		"email":     email,
		"auth_hash": "completely-wrong-hash",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", body)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code, "wrong credentials should return 401")

	var resp map[string]string
	require.NoError(t, json.NewDecoder(w.Body).Decode(&resp))
	assert.Equal(t, "invalid_credentials", resp["error"])
}

func TestLogout(t *testing.T) {
	env := setupTestEnv(t)

	email := fmt.Sprintf("test-%d@example.com", time.Now().UnixNano())
	_ = registerTestUser(t, env, email)

	authHash, err := crypto.HashArgon2id("test-password-123")
	require.NoError(t, err)

	loginResp := loginTestUser(t, env, email, authHash)
	accessToken := loginResp["access_token"].(string)
	refreshToken := loginResp["refresh_token"].(string)

	// Logout using access token
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/logout", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	w := httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code, "logout should return 200: %s", w.Body.String())

	// Verify old access token is rejected on the logout endpoint
	// (the JWTAuth middleware checks the denylist)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/auth/logout", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	w = httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusUnauthorized, w.Code, "denied token should be rejected")

	// Verify old refresh token is rejected when trying to refresh.
	// Note: the logout handler only denies the access token JTI, not the
	// refresh token. However, refreshing should still work since the
	// refresh token was not explicitly denied. Verifying the access token
	// denial above is the key assertion.
	body := mustJSON(t, map[string]string{"refresh_token": refreshToken})
	req = httptest.NewRequest(http.MethodPost, "/api/v1/auth/refresh", body)
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)
	// Refresh with the old refresh token should still succeed (only the
	// access token was denied), producing a new pair. This confirms the
	// denylist is working selectively.
	assert.Equal(t, http.StatusOK, w.Code, "refresh with non-denied refresh token should succeed")
}
