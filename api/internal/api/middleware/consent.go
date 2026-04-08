package middleware

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/healthvault/healthvault/internal/api/handlers"
)

const (
	consentCacheKey = "consent:latest_doc_id"
	consentCacheTTL = 5 * time.Minute
)

// ConsentCheck returns middleware that enforces acceptance of the latest legal
// document. Unauthenticated requests and exempt paths are passed through. When
// a user has not accepted the most recent document the middleware responds with
// HTTP 451 (Unavailable For Legal Reasons).
func ConsentCheck(db *pgxpool.Pool, rdb *redis.Client) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Skip exempt paths.
			path := r.URL.Path
			if strings.HasPrefix(path, "/api/v1/auth/") ||
				strings.HasPrefix(path, "/health") ||
				path == "/api/v1/legal/accept" {
				next.ServeHTTP(w, r)
				return
			}

			// Only enforce for authenticated requests.
			claims, ok := handlers.ClaimsFromContext(r.Context())
			if !ok {
				next.ServeHTTP(w, r)
				return
			}

			docID, found := latestDocumentID(r.Context(), db, rdb)
			if !found {
				// No legal documents published yet — nothing to enforce.
				next.ServeHTTP(w, r)
				return
			}

			var count int
			err := db.QueryRow(r.Context(),
				`SELECT COUNT(*) FROM user_consent_records WHERE user_id = $1 AND document_id = $2`,
				claims.UserID, docID,
			).Scan(&count)
			if err != nil {
				// On DB error fail closed — never skip consent verification.
				writeJSONError(w, http.StatusServiceUnavailable, "service_unavailable")
				return
			}

			if count == 0 {
				writeJSONError(w, http.StatusUnavailableForLegalReasons, "updated_policy_acceptance_required")
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}

// latestDocumentID returns the ID of the most recent effective legal document.
// The value is cached in Redis for consentCacheTTL to avoid a DB query on
// every request. If Redis is unavailable the DB is queried directly.
func latestDocumentID(ctx context.Context, db *pgxpool.Pool, rdb *redis.Client) (uuid.UUID, bool) {
	// Try Redis cache first.
	if rdb != nil {
		val, err := rdb.Get(ctx, consentCacheKey).Result()
		if err == nil {
			id, parseErr := uuid.Parse(val)
			if parseErr == nil {
				return id, true
			}
		}
	}

	// Fallback to DB.
	var docID uuid.UUID
	err := db.QueryRow(ctx,
		`SELECT id FROM instance_legal_documents WHERE effective_from <= NOW() ORDER BY effective_from DESC LIMIT 1`,
	).Scan(&docID)
	if err != nil {
		return uuid.Nil, false
	}

	// Warm the cache.
	if rdb != nil {
		_ = rdb.Set(ctx, consentCacheKey, docID.String(), consentCacheTTL).Err()
	}

	return docID, true
}
