package middleware

import (
	"fmt"
	"net/http"
	"strings"
)

// CORS returns middleware that sets CORS headers locked to the instance hostname.
func CORS(hostname string) func(next http.Handler) http.Handler {
	allowedOrigins := map[string]bool{
		fmt.Sprintf("https://%s", hostname): true,
	}
	// Allow HTTP in development
	if hostname == "localhost" || strings.HasPrefix(hostname, "localhost:") {
		allowedOrigins[fmt.Sprintf("http://%s", hostname)] = true
		allowedOrigins["http://localhost:5173"] = true // Vite dev server
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")

			if allowedOrigins[origin] {
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Access-Control-Allow-Credentials", "true")
				w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, PUT, DELETE, OPTIONS")
				w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Request-ID")
				w.Header().Set("Access-Control-Expose-Headers", "X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset")
				w.Header().Set("Access-Control-Max-Age", "86400")
			}

			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
