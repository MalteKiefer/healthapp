package middleware

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/healthvault/healthvault/internal/api/handlers"
)

const (
	consentCacheKeyPrefix = "consent:latest_doc_id:"
	consentCacheTTL       = 5 * time.Minute
)

// requiredDocumentTypes lists the legal document types that every user must
// accept before accessing the application. GDPR requires separate consent for
// different processing purposes, so each type is verified independently.
var requiredDocumentTypes = []string{"privacy_policy", "terms_of_service"}

// ConsentCheck returns middleware that enforces acceptance of the latest legal
// documents of every required type. Unauthenticated requests and exempt paths
// are passed through. When a user has not accepted the most recent version of
// any required document type the middleware responds with HTTP 451 (Unavailable
// For Legal Reasons).
func ConsentCheck(db *pgxpool.Pool, rdb *redis.Client) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Skip exempt paths.
			path := r.URL.Path
			if strings.HasPrefix(path, "/api/v1/auth/") ||
				strings.HasPrefix(path, "/health") ||
				path == "/api/v1/legal/accept" ||
				path == "/api/v1/legal/pending" {
				next.ServeHTTP(w, r)
				return
			}

			// Only enforce for authenticated requests.
			claims, ok := handlers.ClaimsFromContext(r.Context())
			if !ok {
				next.ServeHTTP(w, r)
				return
			}

			for _, docType := range requiredDocumentTypes {
				docID, found := latestDocumentIDByType(r.Context(), db, rdb, docType)
				if !found {
					// No document of this type published yet — skip check for it.
					continue
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
			}

			next.ServeHTTP(w, r)
		})
	}
}

// latestDocumentIDByType returns the ID of the most recent effective legal
// document of the given type. The value is cached in Redis for consentCacheTTL
// to avoid a DB query on every request. If Redis is unavailable the DB is
// queried directly.
func latestDocumentIDByType(ctx context.Context, db *pgxpool.Pool, rdb *redis.Client, docType string) (uuid.UUID, bool) {
	cacheKey := fmt.Sprintf("%s%s", consentCacheKeyPrefix, docType)

	// Try Redis cache first.
	if rdb != nil {
		val, err := rdb.Get(ctx, cacheKey).Result()
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
		`SELECT id FROM instance_legal_documents
		 WHERE document_type = $1 AND effective_from <= NOW()
		 ORDER BY effective_from DESC LIMIT 1`,
		docType,
	).Scan(&docID)
	if err != nil {
		return uuid.Nil, false
	}

	// Warm the cache.
	if rdb != nil {
		_ = rdb.Set(ctx, cacheKey, docID.String(), consentCacheTTL).Err()
	}

	return docID, true
}
