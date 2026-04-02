package middleware

import (
	"fmt"
	"net/http"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/healthvault/healthvault/internal/api/handlers"
)

// SessionTimeout returns middleware that enforces an idle-session timeout on
// the server side. Even though a JWT may still be valid, if the user has been
// idle longer than the configured duration the request is rejected with 401.
//
// On every authenticated request the middleware checks a Redis key
// "session:active:{user_id}". If the key exists its TTL is refreshed. If it
// does not exist AND the JWT was issued more than `timeout` ago the request is
// treated as an expired idle session. Otherwise the key is created (or
// refreshed) with the given timeout duration.
func SessionTimeout(rdb *redis.Client, timeout time.Duration) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims, ok := handlers.ClaimsFromContext(r.Context())
			if !ok {
				// Not authenticated — nothing to check.
				next.ServeHTTP(w, r)
				return
			}

			key := fmt.Sprintf("session:active:%s", claims.UserID.String())
			ctx := r.Context()

			exists, err := rdb.Exists(ctx, key).Result()
			if err != nil {
				// Redis error — fail closed to prevent session timeout bypass.
				writeJSONError(w, http.StatusServiceUnavailable, "service_temporarily_unavailable")
				return
			}

			if exists > 0 {
				// Session key present — refresh TTL.
				_ = rdb.Expire(ctx, key, timeout)
				next.ServeHTTP(w, r)
				return
			}

			// Key does not exist. Check whether the JWT was issued more than
			// `timeout` ago; if so the session has been idle too long.
			if claims.IssuedAt != nil && time.Since(claims.IssuedAt.Time) > timeout {
				writeJSONError(w, http.StatusUnauthorized, "session_timeout")
				return
			}

			// First request (or within the initial window) — create the key.
			_ = rdb.Set(ctx, key, "1", timeout)
			next.ServeHTTP(w, r)
		})
	}
}
