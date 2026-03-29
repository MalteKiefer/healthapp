package middleware

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/healthvault/healthvault/internal/api/handlers"
)

// RateLimitConfig defines a rate limit tier.
type RateLimitConfig struct {
	Requests      int
	Window        time.Duration
	BlockDuration time.Duration
	PerUser       bool // false = per IP
}

// RateLimiter provides Redis-based sliding window rate limiting.
type RateLimiter struct {
	rdb *redis.Client
}

func NewRateLimiter(rdb *redis.Client) *RateLimiter {
	return &RateLimiter{rdb: rdb}
}

// Limit returns middleware enforcing the given rate limit config.
func (rl *RateLimiter) Limit(cfg RateLimitConfig) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := rl.buildKey(r, cfg)
			ctx := r.Context()

			// Check if currently blocked
			blocked, err := rl.rdb.Exists(ctx, key+":blocked").Result()
			if err == nil && blocked > 0 {
				ttl, _ := rl.rdb.TTL(ctx, key+":blocked").Result()
				writeRateLimitHeaders(w, cfg.Requests, 0, time.Now().Add(ttl))
				writeJSONError(w, http.StatusTooManyRequests, "rate_limit_exceeded")
				return
			}

			// Sliding window counter
			allowed, remaining, err := rl.checkLimit(ctx, key, cfg)
			if err != nil {
				// On Redis error, deny the request (fail closed) to prevent brute-force
				writeJSONError(w, http.StatusServiceUnavailable, "service_temporarily_unavailable")
				return
			}

			writeRateLimitHeaders(w, cfg.Requests, remaining, time.Now().Add(cfg.Window))

			if !allowed {
				// Set block if configured
				if cfg.BlockDuration > 0 {
					rl.rdb.Set(ctx, key+":blocked", "1", cfg.BlockDuration)
				}
				w.Header().Set("Retry-After", strconv.Itoa(int(cfg.Window.Seconds())))
				writeJSONError(w, http.StatusTooManyRequests, "rate_limit_exceeded")
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}

func (rl *RateLimiter) checkLimit(ctx context.Context, key string, cfg RateLimitConfig) (bool, int, error) {
	now := time.Now().UnixMilli()
	windowStart := now - cfg.Window.Milliseconds()
	member := fmt.Sprintf("%d", now)

	pipe := rl.rdb.Pipeline()
	pipe.ZRemRangeByScore(ctx, key, "0", strconv.FormatInt(windowStart, 10))
	pipe.ZAdd(ctx, key, redis.Z{Score: float64(now), Member: member})
	countCmd := pipe.ZCard(ctx, key)
	pipe.Expire(ctx, key, cfg.Window+time.Second)

	_, err := pipe.Exec(ctx)
	if err != nil {
		return false, 0, err
	}

	count := int(countCmd.Val())
	remaining := cfg.Requests - count
	if remaining < 0 {
		remaining = 0
	}

	return count <= cfg.Requests, remaining, nil
}

func (rl *RateLimiter) buildKey(r *http.Request, cfg RateLimitConfig) string {
	if cfg.PerUser {
		claims, ok := handlers.ClaimsFromContext(r.Context())
		if ok {
			return fmt.Sprintf("rl:%s:%s", r.URL.Path, claims.UserID)
		}
	}
	return fmt.Sprintf("rl:%s:%s", r.URL.Path, r.RemoteAddr)
}

func writeRateLimitHeaders(w http.ResponseWriter, limit, remaining int, reset time.Time) {
	w.Header().Set("X-RateLimit-Limit", strconv.Itoa(limit))
	w.Header().Set("X-RateLimit-Remaining", strconv.Itoa(remaining))
	w.Header().Set("X-RateLimit-Reset", strconv.FormatInt(reset.Unix(), 10))
}
