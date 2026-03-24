package crypto

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// generateTestKeyPair creates a temporary RSA key pair, writes them to temp
// files, and returns the file paths. The caller should defer os.RemoveAll on
// the returned directory.
func generateTestKeyPair(t *testing.T) (privPath, pubPath, dir string) {
	t.Helper()

	dir = t.TempDir()
	privPath = filepath.Join(dir, "private.pem")
	pubPath = filepath.Join(dir, "public.pem")

	privKey, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)

	privBytes := x509.MarshalPKCS1PrivateKey(privKey)
	privPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: privBytes})
	require.NoError(t, os.WriteFile(privPath, privPEM, 0600))

	pubBytes, err := x509.MarshalPKIXPublicKey(&privKey.PublicKey)
	require.NoError(t, err)
	pubPEM := pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubBytes})
	require.NoError(t, os.WriteFile(pubPath, pubPEM, 0644))

	return privPath, pubPath, dir
}

// newTestTokenService creates a TokenService with a nil Redis client (for
// tests that do not need Redis).
func newTestTokenService(t *testing.T, accessTTL, refreshTTL time.Duration) *TokenService {
	t.Helper()
	privPath, pubPath, _ := generateTestKeyPair(t)
	ts, err := NewTokenService(privPath, pubPath, nil, accessTTL, refreshTTL)
	require.NoError(t, err)
	return ts
}

// newTestTokenServiceWithRedis creates a TokenService backed by a real Redis
// connection on localhost:6379. Returns nil if Redis is not reachable.
func newTestTokenServiceWithRedis(t *testing.T, accessTTL, refreshTTL time.Duration) *TokenService {
	t.Helper()

	rdb := redis.NewClient(&redis.Options{
		Addr: "localhost:6379",
		DB:   15, // use a high DB number to avoid clashing with production data
	})

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		t.Skip("Redis not available")
		return nil
	}

	// Flush the test DB before each test to start clean.
	rdb.FlushDB(ctx)

	t.Cleanup(func() {
		rdb.FlushDB(context.Background())
		rdb.Close()
	})

	privPath, pubPath, _ := generateTestKeyPair(t)
	ts, err := NewTokenService(privPath, pubPath, rdb, accessTTL, refreshTTL)
	require.NoError(t, err)
	return ts
}

func TestGenerateTokenPair(t *testing.T) {
	ts := newTestTokenService(t, 15*time.Minute, 7*24*time.Hour)
	userID := uuid.New()

	pair, err := ts.GenerateTokenPair(userID, "user")
	require.NoError(t, err)
	assert.NotEmpty(t, pair.AccessToken, "access token should not be empty")
	assert.NotEmpty(t, pair.RefreshToken, "refresh token should not be empty")
	assert.NotEmpty(t, pair.JTI, "JTI should not be empty")
	assert.Greater(t, pair.ExpiresAt, time.Now().Unix(), "expiration should be in the future")
	assert.NotEqual(t, pair.AccessToken, pair.RefreshToken, "access and refresh tokens should differ")
}

func TestVerifyToken_Valid(t *testing.T) {
	ts := newTestTokenServiceWithRedis(t, 15*time.Minute, 7*24*time.Hour)
	userID := uuid.New()
	role := "admin"

	pair, err := ts.GenerateTokenPair(userID, role)
	require.NoError(t, err)

	ctx := context.Background()
	claims, err := ts.VerifyToken(ctx, pair.AccessToken)
	require.NoError(t, err)
	assert.Equal(t, userID, claims.UserID, "UserID should match")
	assert.Equal(t, role, claims.Role, "Role should match")
	assert.Equal(t, "access", claims.Type, "Type should be access")
	assert.Equal(t, "healthvault", claims.Issuer, "Issuer should be healthvault")
	assert.Equal(t, userID.String(), claims.Subject, "Subject should match user ID string")
}

func TestVerifyToken_Expired(t *testing.T) {
	// Use a very short TTL so the token expires quickly.
	ts := newTestTokenServiceWithRedis(t, 1*time.Millisecond, 1*time.Millisecond)
	userID := uuid.New()

	pair, err := ts.GenerateTokenPair(userID, "user")
	require.NoError(t, err)

	// Wait for the token to expire.
	time.Sleep(50 * time.Millisecond)

	ctx := context.Background()
	_, err = ts.VerifyToken(ctx, pair.AccessToken)
	assert.Error(t, err, "expired token should fail verification")
	assert.Contains(t, err.Error(), "token is expired", "error should mention expiration")
}

func TestDenyToken(t *testing.T) {
	ts := newTestTokenServiceWithRedis(t, 15*time.Minute, 7*24*time.Hour)
	userID := uuid.New()

	pair, err := ts.GenerateTokenPair(userID, "user")
	require.NoError(t, err)

	ctx := context.Background()

	// Token should be valid before denying.
	_, err = ts.VerifyToken(ctx, pair.AccessToken)
	require.NoError(t, err)

	// Deny the token.
	err = ts.DenyToken(ctx, pair.JTI, 15*time.Minute)
	require.NoError(t, err)

	// Token should now be rejected.
	_, err = ts.VerifyToken(ctx, pair.AccessToken)
	assert.Error(t, err, "denied token should fail verification")
	assert.Contains(t, err.Error(), "token has been revoked", "error should mention revocation")
}
