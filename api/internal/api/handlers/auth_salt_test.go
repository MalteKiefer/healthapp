package handlers_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/healthvault/healthvault/internal/domain/user"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

func TestGetAuthSalt_KnownUser_ReturnsStoredSalt(t *testing.T) {
	env := setupTestEnv(t)

	// Seed the user directly via the repository instead of going through
	// the /auth/register HTTP flow. The full handler test suite hammers
	// the register endpoint enough to trip its per-IP rate limiter by
	// the time this test runs (alphabetical ordering puts auth_salt_test
	// after auth_test), which would cause a spurious 403.
	email := fmt.Sprintf("known-%d@example.com", time.Now().UnixNano())
	userRepo := postgres.NewUserRepo(env.DB)
	seeded := &user.User{
		Email:              email,
		DisplayName:        "Salt Test",
		AuthHash:           "test-auth-hash",
		PEKSalt:            "test-pek-salt",
		AuthSalt:           "deadbeefcafebabe0011223344556677",
		IdentityPubkey:     "test-identity-pubkey",
		IdentityPrivkeyEnc: "test-identity-privkey-enc",
		SigningPubkey:      "test-signing-pubkey",
		SigningPrivkeyEnc:  "test-signing-privkey-enc",
		Role:               "user",
	}
	require.NoError(t, userRepo.Create(context.Background(), seeded))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/auth/salt?email="+email, nil)
	w := httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code, "body: %s", w.Body.String())

	var resp map[string]string
	require.NoError(t, json.NewDecoder(w.Body).Decode(&resp))
	assert.Equal(t, seeded.AuthSalt, resp["salt"], "endpoint should return the stored auth_salt")
}

func TestGetAuthSalt_UnknownUser_ReturnsDeterministicPseudoSalt(t *testing.T) {
	env := setupTestEnv(t)

	email := fmt.Sprintf("ghost-%d@example.com", time.Now().UnixNano())

	call := func() string {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/auth/salt?email="+email, nil)
		w := httptest.NewRecorder()
		env.Router.ServeHTTP(w, req)
		require.Equal(t, http.StatusOK, w.Code, "body: %s", w.Body.String())
		var resp map[string]string
		require.NoError(t, json.NewDecoder(w.Body).Decode(&resp))
		require.NotEmpty(t, resp["salt"])
		return resp["salt"]
	}

	first := call()
	second := call()
	assert.Equal(t, first, second, "unknown-email pseudo-salt must be deterministic")

	// Pseudo-salt is HMAC-SHA256(key, email)[:16] hex-encoded → 32 hex chars.
	assert.Len(t, first, 32, "pseudo-salt should be 16 bytes hex-encoded (32 chars)")
}

func TestGetAuthSalt_MissingEmail_Returns400(t *testing.T) {
	env := setupTestEnv(t)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/auth/salt", nil)
	w := httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
}
