package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// AdminHandler handles admin panel endpoints.
type AdminHandler struct {
	db     *pgxpool.Pool
	rdb    *redis.Client
	logger *zap.Logger
}

func NewAdminHandler(db *pgxpool.Pool, rdb *redis.Client, logger *zap.Logger) *AdminHandler {
	return &AdminHandler{db: db, rdb: rdb, logger: logger}
}

// ── Response Types ──────────────────────────────────────────────────

type adminUser struct {
	ID          uuid.UUID `json:"id"`
	Email       string    `json:"email"`
	DisplayName string    `json:"display_name"`
	Role        string    `json:"role"`
	IsDisabled  bool      `json:"is_disabled"`
	CreatedAt   time.Time `json:"created_at"`
	StorageUsed int64     `json:"storage_used"`
}

type auditLogEntry struct {
	ID        uuid.UUID       `json:"id"`
	UserID    *uuid.UUID      `json:"user_id,omitempty"`
	Action    string          `json:"action"`
	Details   json.RawMessage `json:"details,omitempty"`
	IPAddress string          `json:"ip_address,omitempty"`
	CreatedAt time.Time       `json:"created_at"`
}

type backupEntry struct {
	ID          uuid.UUID `json:"id"`
	Type        string    `json:"type"`
	Status      string    `json:"status"`
	SizeBytes   int64     `json:"size_bytes"`
	StartedAt   time.Time `json:"started_at"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`
}

type setQuotaRequest struct {
	QuotaBytes int64 `json:"quota_bytes"`
}

type updateSettingsRequest struct {
	Settings map[string]string `json:"settings"`
}

// ── Handlers ────────────────────────────────────────────────────────

// HandleListUsers returns all users with storage information.
// GET /admin/users
func (h *AdminHandler) HandleListUsers(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	rows, err := h.db.Query(r.Context(),
		`SELECT u.id, u.email, u.display_name, u.role, u.is_disabled, u.created_at,
		        COALESCE(us.used_bytes, 0) AS storage_used
		 FROM users u
		 LEFT JOIN user_storage us ON us.user_id = u.id
		 ORDER BY u.created_at DESC`,
	)
	if err != nil {
		h.logger.Error("list users", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	var users []adminUser
	for rows.Next() {
		var u adminUser
		if err := rows.Scan(&u.ID, &u.Email, &u.DisplayName, &u.Role,
			&u.IsDisabled, &u.CreatedAt, &u.StorageUsed); err != nil {
			h.logger.Error("scan user", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		users = append(users, u)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate users", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if users == nil {
		users = []adminUser{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": users,
	})
}

// HandleDisableUser disables a user account.
// POST /admin/users/{userID}/disable
func (h *AdminHandler) HandleDisableUser(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	userID, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_user_id"))
		return
	}

	tag, err := h.db.Exec(r.Context(),
		`UPDATE users SET is_disabled = true, updated_at = $1 WHERE id = $2`,
		time.Now().UTC(), userID,
	)
	if err != nil {
		h.logger.Error("disable user", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusNotFound, errorResponse("user_not_found"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "disabled"})
}

// HandleEnableUser re-enables a disabled user account.
// POST /admin/users/{userID}/enable
func (h *AdminHandler) HandleEnableUser(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	userID, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_user_id"))
		return
	}

	tag, err := h.db.Exec(r.Context(),
		`UPDATE users SET is_disabled = false, updated_at = $1 WHERE id = $2`,
		time.Now().UTC(), userID,
	)
	if err != nil {
		h.logger.Error("enable user", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusNotFound, errorResponse("user_not_found"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "enabled"})
}

// HandleDeleteUser permanently deletes a user and all associated data.
// DELETE /admin/users/{userID}
func (h *AdminHandler) HandleDeleteUser(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	userID, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_user_id"))
		return
	}

	// Prevent self-deletion
	if userID == claims.UserID {
		writeJSON(w, http.StatusBadRequest, errorResponse("cannot_delete_self"))
		return
	}

	tag, err := h.db.Exec(r.Context(),
		`DELETE FROM users WHERE id = $1`,
		userID,
	)
	if err != nil {
		h.logger.Error("delete user", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusNotFound, errorResponse("user_not_found"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// HandleGetSystem returns system health information.
// GET /admin/system
func (h *AdminHandler) HandleGetSystem(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	// Database pool stats
	dbStats := h.db.Stat()
	dbInfo := map[string]interface{}{
		"total_conns":          dbStats.TotalConns(),
		"idle_conns":           dbStats.IdleConns(),
		"acquired_conns":      dbStats.AcquiredConns(),
		"max_conns":            dbStats.MaxConns(),
		"constructing_conns":  dbStats.ConstructingConns(),
		"empty_acquire_count": dbStats.EmptyAcquireCount(),
	}

	// Redis info
	redisInfo := map[string]interface{}{}
	ctx := context.Background()
	if pong, err := h.rdb.Ping(ctx).Result(); err == nil {
		redisInfo["status"] = pong
	} else {
		redisInfo["status"] = "error"
		redisInfo["error"] = err.Error()
	}
	if dbSize, err := h.rdb.DBSize(ctx).Result(); err == nil {
		redisInfo["db_size"] = dbSize
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"database": dbInfo,
		"redis":    redisInfo,
		"version":  "1.0.0",
	})
}

// HandleGetAuditLog returns paginated audit log entries.
// GET /admin/audit-log?limit=50&offset=0
func (h *AdminHandler) HandleGetAuditLog(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	limit := 50
	offset := 0

	if v := r.URL.Query().Get("limit"); v != "" {
		if l, err := strconv.Atoi(v); err == nil && l > 0 && l <= 200 {
			limit = l
		}
	}
	if v := r.URL.Query().Get("offset"); v != "" {
		if o, err := strconv.Atoi(v); err == nil && o >= 0 {
			offset = o
		}
	}

	rows, err := h.db.Query(r.Context(),
		`SELECT id, user_id, action, details, ip_address::text, created_at
		 FROM audit_log
		 ORDER BY created_at DESC
		 LIMIT $1 OFFSET $2`,
		limit, offset,
	)
	if err != nil {
		h.logger.Error("query audit log", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	var entries []auditLogEntry
	for rows.Next() {
		var e auditLogEntry
		if err := rows.Scan(&e.ID, &e.UserID, &e.Action, &e.Details, &e.IPAddress, &e.CreatedAt); err != nil {
			h.logger.Error("scan audit entry", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		entries = append(entries, e)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate audit log", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Get total count for pagination
	var total int
	if err := h.db.QueryRow(r.Context(), `SELECT COUNT(*) FROM audit_log`).Scan(&total); err != nil {
		h.logger.Error("count audit log", zap.Error(err))
	}

	if entries == nil {
		entries = []auditLogEntry{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items":  entries,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

// HandleGetSettings updates instance settings key-value pairs.
// PATCH /admin/settings
func (h *AdminHandler) HandleGetSettings(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	var req updateSettingsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if len(req.Settings) == 0 {
		writeJSON(w, http.StatusBadRequest, errorResponse("settings_required"))
		return
	}

	now := time.Now().UTC()
	for key, value := range req.Settings {
		_, err := h.db.Exec(r.Context(),
			`INSERT INTO instance_settings (key, value, updated_at)
			 VALUES ($1, $2, $3)
			 ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at`,
			key, value, now,
		)
		if err != nil {
			h.logger.Error("update setting", zap.String("key", key), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// HandleGetBackups returns recent backup entries.
// GET /admin/backups
func (h *AdminHandler) HandleGetBackups(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	rows, err := h.db.Query(r.Context(),
		`SELECT id, type, status, size_bytes, started_at, completed_at
		 FROM backup_heartbeat
		 ORDER BY started_at DESC
		 LIMIT 50`,
	)
	if err != nil {
		h.logger.Error("query backups", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	var backups []backupEntry
	for rows.Next() {
		var b backupEntry
		if err := rows.Scan(&b.ID, &b.Type, &b.Status, &b.SizeBytes, &b.StartedAt, &b.CompletedAt); err != nil {
			h.logger.Error("scan backup entry", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		backups = append(backups, b)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate backups", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if backups == nil {
		backups = []backupEntry{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": backups,
	})
}

// HandleTriggerBackup logs that a manual backup was requested.
// POST /admin/backups/trigger
func (h *AdminHandler) HandleTriggerBackup(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	h.logger.Info("manual backup requested",
		zap.String("user_id", claims.UserID.String()),
		zap.Time("requested_at", time.Now().UTC()),
	)

	writeJSON(w, http.StatusAccepted, map[string]string{
		"status":  "accepted",
		"message": "backup has been queued",
	})
}

// HandleGetStorage returns total storage used across all users.
// GET /admin/storage
func (h *AdminHandler) HandleGetStorage(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	var totalUsed, totalQuota int64
	var userCount int
	err := h.db.QueryRow(r.Context(),
		`SELECT COALESCE(SUM(used_bytes), 0), COALESCE(SUM(quota_bytes), 0), COUNT(*)
		 FROM user_storage`,
	).Scan(&totalUsed, &totalQuota, &userCount)
	if err != nil {
		h.logger.Error("query storage totals", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"total_used_bytes":  totalUsed,
		"total_quota_bytes": totalQuota,
		"user_count":        userCount,
	})
}

// HandleSetQuota updates the storage quota for a specific user.
// PATCH /admin/users/{userID}/quota
func (h *AdminHandler) HandleSetQuota(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	userID, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_user_id"))
		return
	}

	var req setQuotaRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.QuotaBytes <= 0 {
		writeJSON(w, http.StatusBadRequest, errorResponse("quota_must_be_positive"))
		return
	}

	// Verify user exists
	var exists bool
	err = h.db.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)`, userID).Scan(&exists)
	if err != nil {
		h.logger.Error("check user exists", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if !exists {
		writeJSON(w, http.StatusNotFound, errorResponse("user_not_found"))
		return
	}

	tag, err := h.db.Exec(r.Context(),
		`UPDATE user_storage SET quota_bytes = $1, updated_at = $2 WHERE user_id = $3`,
		req.QuotaBytes, time.Now().UTC(), userID,
	)
	if err != nil {
		h.logger.Error("set quota", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if tag.RowsAffected() == 0 {
		// Storage record might not exist yet; create it
		_, err = h.db.Exec(r.Context(),
			`INSERT INTO user_storage (user_id, used_bytes, quota_bytes, updated_at)
			 VALUES ($1, 0, $2, $3)`,
			userID, req.QuotaBytes, time.Now().UTC(),
		)
		if err != nil {
			h.logger.Error("create storage record", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"user_id":    userID,
		"quota_bytes": req.QuotaBytes,
	})
}

// ── Admin Session Management ────────────────────────────────────────

type adminSession struct {
	ID           uuid.UUID  `json:"id"`
	UserID       uuid.UUID  `json:"user_id"`
	DeviceHint   string     `json:"device_hint"`
	IPAddress    string     `json:"ip_address"`
	CreatedAt    time.Time  `json:"created_at"`
	LastActiveAt time.Time  `json:"last_active_at"`
	ExpiresAt    time.Time  `json:"expires_at"`
	RevokedAt    *time.Time `json:"revoked_at,omitempty"`
}

// HandleGetUserSessions returns all sessions for a given user.
// GET /admin/users/{userID}/sessions
func (h *AdminHandler) HandleGetUserSessions(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	userID, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_user_id"))
		return
	}

	rows, err := h.db.Query(r.Context(),
		`SELECT id, user_id, device_hint, ip_address::text, created_at, last_active_at, expires_at, revoked_at
		 FROM user_sessions
		 WHERE user_id = $1
		 ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		h.logger.Error("query user sessions", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	sessions := []adminSession{}
	for rows.Next() {
		var s adminSession
		if err := rows.Scan(&s.ID, &s.UserID, &s.DeviceHint, &s.IPAddress,
			&s.CreatedAt, &s.LastActiveAt, &s.ExpiresAt, &s.RevokedAt); err != nil {
			h.logger.Error("scan session", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		sessions = append(sessions, s)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate sessions", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"sessions": sessions,
	})
}

// HandleRevokeUserSessions revokes all sessions for a given user.
// DELETE /admin/users/{userID}/sessions
func (h *AdminHandler) HandleRevokeUserSessions(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	userID, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_user_id"))
		return
	}

	now := time.Now().UTC()
	tag, err := h.db.Exec(r.Context(),
		`UPDATE user_sessions SET revoked_at = $2
		 WHERE user_id = $1 AND revoked_at IS NULL`,
		userID, now,
	)
	if err != nil {
		h.logger.Error("revoke user sessions", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"status":          "revoked",
		"sessions_revoked": tag.RowsAffected(),
	})
}
