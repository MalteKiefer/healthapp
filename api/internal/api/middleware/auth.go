package middleware

import (
	"net/http"
	"strings"

	"github.com/healthvault/healthvault/internal/api/handlers"
	"github.com/healthvault/healthvault/internal/crypto"
)

// JWTAuth returns middleware that validates JWT access tokens.
// It checks the Authorization header first, then falls back to the
// access_token httpOnly cookie.
func JWTAuth(ts *crypto.TokenService) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			var tokenStr string
			if auth := r.Header.Get("Authorization"); strings.HasPrefix(auth, "Bearer ") || strings.HasPrefix(auth, "bearer ") {
				tokenStr = auth[7:]
			} else if cookie, err := r.Cookie("access_token"); err == nil {
				tokenStr = cookie.Value
			}

			if tokenStr == "" {
				writeJSONError(w, http.StatusUnauthorized, "missing_authorization")
				return
			}

			claims, err := ts.VerifyToken(r.Context(), tokenStr)
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
