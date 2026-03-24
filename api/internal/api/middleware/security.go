package middleware

import "net/http"

// SecurityHeaders sets security headers on all API responses.
// Note: Primary security headers (CSP, HSTS, etc.) are set by Caddy.
// These are defense-in-depth headers for the API specifically.
func SecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")

		next.ServeHTTP(w, r)
	})
}
