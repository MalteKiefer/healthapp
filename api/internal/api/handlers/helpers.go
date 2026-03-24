package handlers

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/healthvault/healthvault/internal/crypto"
)

type contextKey string

const claimsKey contextKey = "claims"

// ContextWithClaims stores JWT claims in the request context.
func ContextWithClaims(ctx context.Context, claims *crypto.Claims) context.Context {
	return context.WithValue(ctx, claimsKey, claims)
}

// ClaimsFromContext retrieves JWT claims from the request context.
func ClaimsFromContext(ctx context.Context) (*crypto.Claims, bool) {
	claims, ok := ctx.Value(claimsKey).(*crypto.Claims)
	return claims, ok
}

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func errorResponse(code string) map[string]string {
	return map[string]string{"error": code}
}
