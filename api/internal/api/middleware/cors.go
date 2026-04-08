package middleware

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"regexp"
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
		if devOrigin := os.Getenv("DEV_ORIGIN"); devOrigin != "" {
			validDevOrigin := regexp.MustCompile(`^http://(localhost|127\.0\.0\.1)(:\d+)?$`)
			if !validDevOrigin.MatchString(devOrigin) {
				log.Fatalf("DEV_ORIGIN %q must match http://localhost:<port> or http://127.0.0.1:<port>", devOrigin)
			}
			allowedOrigins[devOrigin] = true
		}
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

			w.Header().Add("Vary", "Origin")

			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
