package middleware

import (
	"net/http"
	"strings"

	"github.com/healthvault/healthvault/internal/api/handlers"
	"github.com/healthvault/healthvault/internal/crypto"
)

// JWTAuth returns middleware that validates JWT access tokens.
func JWTAuth(ts *crypto.TokenService) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				writeJSONError(w, http.StatusUnauthorized, "missing_authorization_header")
				return
			}

			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") {
				writeJSONError(w, http.StatusUnauthorized, "invalid_authorization_format")
				return
			}

			claims, err := ts.VerifyToken(r.Context(), parts[1])
			if err != nil {
				writeJSONError(w, http.StatusUnauthorized, "invalid_token")
				return
			}

			if claims.Type != "access" {
				writeJSONError(w, http.StatusUnauthorized, "not_an_access_token")
				return
			}

			ctx := handlers.ContextWithClaims(r.Context(), claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// RequireAdmin returns middleware that checks the user has admin role.
func RequireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := handlers.ClaimsFromContext(r.Context())
		if !ok || claims.Role != "admin" {
			writeJSONError(w, http.StatusForbidden, "admin_required")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSONError(w http.ResponseWriter, status int, code string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	w.Write([]byte(`{"error":"` + code + `"}`))
}
