package crypto

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

// TokenService handles JWT RS256 token creation and verification.
type TokenService struct {
	privateKey *rsa.PrivateKey
	publicKey  *rsa.PublicKey
	rdb        *redis.Client
	accessTTL  time.Duration
	refreshTTL time.Duration
}

// TokenPair represents an access + refresh token pair.
type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresAt    int64  `json:"expires_at"`
	JTI          string `json:"-"`
}

// Claims represents the JWT claims.
type Claims struct {
	jwt.RegisteredClaims
	UserID uuid.UUID `json:"uid"`
	Role   string    `json:"role"`
	Type   string    `json:"type"` // "access" or "refresh"
}

// NewTokenService loads RS256 keys and returns a TokenService.
func NewTokenService(privatePath, publicPath string, rdb *redis.Client, accessTTL, refreshTTL time.Duration) (*TokenService, error) {
	privBytes, err := os.ReadFile(privatePath)
	if err != nil {
		return nil, fmt.Errorf("read private key: %w", err)
	}
	block, _ := pem.Decode(privBytes)
	if block == nil {
		return nil, errors.New("invalid PEM block in private key")
	}
	privKey, err := x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		// Try PKCS8
		key, err2 := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err2 != nil {
			return nil, fmt.Errorf("parse private key: %w (pkcs8: %w)", err, err2)
		}
		var ok bool
		privKey, ok = key.(*rsa.PrivateKey)
		if !ok {
			return nil, errors.New("private key is not RSA")
		}
	}

	pubBytes, err := os.ReadFile(publicPath)
	if err != nil {
		return nil, fmt.Errorf("read public key: %w", err)
	}
	pubBlock, _ := pem.Decode(pubBytes)
	if pubBlock == nil {
		return nil, errors.New("invalid PEM block in public key")
	}
	pubIface, err := x509.ParsePKIXPublicKey(pubBlock.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse public key: %w", err)
	}
	pubKey, ok := pubIface.(*rsa.PublicKey)
	if !ok {
		return nil, errors.New("public key is not RSA")
	}

	return &TokenService{
		privateKey: privKey,
		publicKey:  pubKey,
		rdb:        rdb,
		accessTTL:  accessTTL,
		refreshTTL: refreshTTL,
	}, nil
}

// GenerateTokenPair creates a new access + refresh token pair.
func (ts *TokenService) GenerateTokenPair(userID uuid.UUID, role string) (*TokenPair, error) {
	jti, err := generateJTI()
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	accessExp := now.Add(ts.accessTTL)

	accessClaims := Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        jti,
			Subject:   userID.String(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(accessExp),
			Issuer:    "healthvault",
		},
		UserID: userID,
		Role:   role,
		Type:   "access",
	}

	accessToken, err := jwt.NewWithClaims(jwt.SigningMethodRS256, accessClaims).SignedString(ts.privateKey)
	if err != nil {
		return nil, fmt.Errorf("sign access token: %w", err)
	}

	refreshJTI, err := generateJTI()
	if err != nil {
		return nil, err
	}

	refreshClaims := Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        refreshJTI,
			Subject:   userID.String(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ts.refreshTTL)),
			Issuer:    "healthvault",
		},
		UserID: userID,
		Role:   role,
		Type:   "refresh",
	}

	refreshToken, err := jwt.NewWithClaims(jwt.SigningMethodRS256, refreshClaims).SignedString(ts.privateKey)
	if err != nil {
		return nil, fmt.Errorf("sign refresh token: %w", err)
	}

	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresAt:    accessExp.Unix(),
		JTI:          jti,
	}, nil
}

// VerifyToken parses and validates a JWT token.
func (ts *TokenService) VerifyToken(ctx context.Context, tokenStr string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return ts.publicKey, nil
	})
	if err != nil {
		return nil, fmt.Errorf("parse token: %w", err)
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token claims")
	}

	// Check Redis denylist
	denied, err := ts.IsTokenDenied(ctx, claims.ID)
	if err != nil {
		return nil, fmt.Errorf("check denylist: %w", err)
	}
	if denied {
		return nil, errors.New("token has been revoked")
	}

	return claims, nil
}

// DenyToken adds a JTI to the Redis denylist.
func (ts *TokenService) DenyToken(ctx context.Context, jti string, expiry time.Duration) error {
	return ts.rdb.Set(ctx, "jwt:deny:"+jti, "1", expiry).Err()
}

// IsTokenDenied checks if a JTI is on the denylist.
func (ts *TokenService) IsTokenDenied(ctx context.Context, jti string) (bool, error) {
	result, err := ts.rdb.Exists(ctx, "jwt:deny:"+jti).Result()
	if err != nil {
		return false, err
	}
	return result > 0, nil
}

// DeriveEncryptionKey returns a deterministic 32-byte AES-256 key derived from
// the JWT RSA private key using SHA-256. This is used to encrypt TOTP secrets
// at rest without introducing an additional secret.
func (ts *TokenService) DeriveEncryptionKey() []byte {
	privBytes := x509.MarshalPKCS1PrivateKey(ts.privateKey)
	sum := sha256.Sum256(privBytes)
	return sum[:]
}

func generateJTI() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate jti: %w", err)
	}
	return hex.EncodeToString(b), nil
}
