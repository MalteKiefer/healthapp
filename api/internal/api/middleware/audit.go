package middleware

import (
	"context"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/api/handlers"
)

// AuditWriter writes audit log entries for all write operations.
type AuditWriter struct {
	db     *pgxpool.Pool
	logger *zap.Logger
}

func NewAuditWriter(db *pgxpool.Pool, logger *zap.Logger) *AuditWriter {
	return &AuditWriter{db: db, logger: logger}
}

// LogAction records an audit event.
func (a *AuditWriter) LogAction(ctx context.Context, userID *uuid.UUID, action, resource string, resourceID *uuid.UUID, r *http.Request) {
	var uid interface{} = nil
	if userID != nil {
		uid = *userID
	}
	var rid interface{} = nil
	if resourceID != nil {
		rid = *resourceID
	}

	_, err := a.db.Exec(ctx,
		`INSERT INTO audit_log (user_id, action, resource, resource_id, ip_address, user_agent)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		uid, action, resource, rid, r.RemoteAddr, r.UserAgent(),
	)
	if err != nil {
		a.logger.Error("audit log write failed",
			zap.String("action", action),
			zap.String("resource", resource),
			zap.Error(err),
		)
	}
}

// AuditWrites returns middleware that logs POST/PATCH/PUT/DELETE operations.
func AuditWrites(aw *AuditWriter) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			next.ServeHTTP(w, r)

			// Only audit write operations
			switch r.Method {
			case http.MethodPost, http.MethodPatch, http.MethodPut, http.MethodDelete:
				var userID *uuid.UUID
				if claims, ok := handlers.ClaimsFromContext(r.Context()); ok {
					userID = &claims.UserID
				}
				go func() {
					ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
					defer cancel()
					aw.LogAction(ctx, userID, r.Method+" "+r.URL.Path, r.URL.Path, nil, r)
				}()
			}
		})
	}
}
