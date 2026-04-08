package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// privateCIDRs holds the parsed private/reserved CIDR ranges used by the SSRF
// filter. Parsed once at init to avoid re-parsing on every request.
var privateCIDRs []*net.IPNet

func init() {
	for _, cidr := range []string{
		// IPv4
		"0.0.0.0/8",      // unspecified
		"10.0.0.0/8",     // RFC 1918
		"100.64.0.0/10",  // CGNAT/shared address space (RFC 6598)
		"127.0.0.0/8",    // loopback
		"169.254.0.0/16", // link-local / cloud metadata (AWS, GCP, Azure)
		"172.16.0.0/12",  // RFC 1918
		"192.168.0.0/16", // RFC 1918
		// IPv6
		"::1/128",   // loopback
		"fc00::/7",  // unique local
		"fe80::/10", // link-local
	} {
		_, ipNet, err := net.ParseCIDR(cidr)
		if err != nil {
			log.Fatalf("webhooks: invalid CIDR %q: %v", cidr, err)
		}
		privateCIDRs = append(privateCIDRs, ipNet)
	}
}

// WebhookHandler handles admin webhook management endpoints.
type WebhookHandler struct {
	db     *pgxpool.Pool
	logger *zap.Logger
}

// NewWebhookHandler creates a new WebhookHandler.
func NewWebhookHandler(db *pgxpool.Pool, logger *zap.Logger) *WebhookHandler {
	return &WebhookHandler{db: db, logger: logger}
}

// ── Response / Request Types ────────────────────────────────────────

type webhookEntry struct {
	ID        uuid.UUID `json:"id"`
	URL       string    `json:"url"`
	Events    []string  `json:"events"`
	Secret    string    `json:"secret"`
	Enabled   bool      `json:"enabled"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type webhookDeliveryLogEntry struct {
	ID          uuid.UUID `json:"id"`
	WebhookID   uuid.UUID `json:"webhook_id"`
	Event       string    `json:"event"`
	StatusCode  *int      `json:"status_code,omitempty"`
	Response    *string   `json:"response,omitempty"`
	Error       *string   `json:"error,omitempty"`
	DeliveredAt time.Time `json:"delivered_at"`
}

type createWebhookRequest struct {
	URL    string   `json:"url"`
	Events []string `json:"events"`
	Secret string   `json:"secret"`
}

type updateWebhookRequest struct {
	URL     *string  `json:"url,omitempty"`
	Events  []string `json:"events,omitempty"`
	Secret  *string  `json:"secret,omitempty"`
	Enabled *bool    `json:"enabled,omitempty"`
}

// ── Helpers ─────────────────────────────────────────────────────────

// isPrivateOrLocalhost resolves the URL's hostname and checks whether the
// resulting IP falls into RFC 1918 / loopback ranges. Returns an error if
// the address is publicly routable or the hostname cannot be resolved.
func isPrivateOrLocalhost(rawURL string) error {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return fmt.Errorf("invalid url: %w", err)
	}

	hostname := parsed.Hostname()
	if hostname == "" {
		return fmt.Errorf("missing hostname")
	}

	ips, err := net.LookupIP(hostname)
	if err != nil {
		return fmt.Errorf("dns lookup failed: %w", err)
	}
	if len(ips) == 0 {
		return fmt.Errorf("no addresses found for %s", hostname)
	}

	for _, ip := range ips {
		private := false
		for _, pn := range privateCIDRs {
			if pn.Contains(ip) {
				private = true
				break
			}
		}
		if !private {
			return fmt.Errorf("public IP %s is not allowed", ip)
		}
	}

	return nil
}

// ── Handlers ────────────────────────────────────────────────────────

// HandleList returns all webhooks.
// GET /admin/webhooks
func (h *WebhookHandler) HandleList(w http.ResponseWriter, r *http.Request) {
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
		`SELECT id, url, events, secret, enabled, created_at, updated_at
		 FROM webhooks
		 ORDER BY created_at DESC`,
	)
	if err != nil {
		h.logger.Error("list webhooks", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	var webhooks []webhookEntry
	for rows.Next() {
		var wh webhookEntry
		if err := rows.Scan(&wh.ID, &wh.URL, &wh.Events, &wh.Secret, &wh.Enabled, &wh.CreatedAt, &wh.UpdatedAt); err != nil {
			h.logger.Error("scan webhook", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		webhooks = append(webhooks, wh)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate webhooks", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if webhooks == nil {
		webhooks = []webhookEntry{}
	}

	// Mask secrets - only show last 4 chars
	for i := range webhooks {
		if webhooks[i].Secret != "" {
			if len(webhooks[i].Secret) > 4 {
				webhooks[i].Secret = "****" + webhooks[i].Secret[len(webhooks[i].Secret)-4:]
			} else {
				webhooks[i].Secret = "****"
			}
		}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": webhooks,
	})
}

// HandleCreate creates a new webhook after validating the URL is private.
// POST /admin/webhooks
func (h *WebhookHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	var req createWebhookRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if req.URL == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("url_required"))
		return
	}
	if len(req.Events) == 0 {
		writeJSON(w, http.StatusBadRequest, errorResponse("events_required"))
		return
	}
	if req.Secret == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("secret_required"))
		return
	}

	if err := isPrivateOrLocalhost(req.URL); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "url_not_private",
			"details": err.Error(),
		})
		return
	}

	now := time.Now().UTC()
	var id uuid.UUID
	err := h.db.QueryRow(r.Context(),
		`INSERT INTO webhooks (url, events, secret, enabled, created_at, updated_at)
		 VALUES ($1, $2, $3, true, $4, $4)
		 RETURNING id`,
		req.URL, req.Events, req.Secret, now,
	).Scan(&id)
	if err != nil {
		h.logger.Error("create webhook", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{
		"id":         id,
		"url":        req.URL,
		"events":     req.Events,
		"enabled":    true,
		"created_at": now,
	})
}

// HandleUpdate updates an existing webhook.
// PATCH /admin/webhooks/{webhookID}
func (h *WebhookHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	webhookID, err := uuid.Parse(chi.URLParam(r, "webhookID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_webhook_id"))
		return
	}

	var req updateWebhookRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	// Validate URL if provided
	if req.URL != nil && *req.URL != "" {
		if err := isPrivateOrLocalhost(*req.URL); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error":   "url_not_private",
				"details": err.Error(),
			})
			return
		}
	}

	// Build dynamic update
	now := time.Now().UTC()
	tag, err := h.db.Exec(r.Context(),
		`UPDATE webhooks
		 SET url        = COALESCE($1, url),
		     events     = COALESCE($2, events),
		     secret     = COALESCE($3, secret),
		     enabled    = COALESCE($4, enabled),
		     updated_at = $5
		 WHERE id = $6`,
		req.URL, req.Events, req.Secret, req.Enabled, now, webhookID,
	)
	if err != nil {
		h.logger.Error("update webhook", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusNotFound, errorResponse("webhook_not_found"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// HandleDelete deletes a webhook.
// DELETE /admin/webhooks/{webhookID}
func (h *WebhookHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	webhookID, err := uuid.Parse(chi.URLParam(r, "webhookID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_webhook_id"))
		return
	}

	tag, err := h.db.Exec(r.Context(),
		`DELETE FROM webhooks WHERE id = $1`,
		webhookID,
	)
	if err != nil {
		h.logger.Error("delete webhook", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusNotFound, errorResponse("webhook_not_found"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// HandleGetLogs returns the last 100 delivery log entries for a webhook.
// GET /admin/webhooks/{webhookID}/logs
func (h *WebhookHandler) HandleGetLogs(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	webhookID, err := uuid.Parse(chi.URLParam(r, "webhookID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_webhook_id"))
		return
	}

	rows, err := h.db.Query(r.Context(),
		`SELECT id, webhook_id, event, status_code, response, error, delivered_at
		 FROM webhook_delivery_log
		 WHERE webhook_id = $1
		 ORDER BY delivered_at DESC
		 LIMIT 100`,
		webhookID,
	)
	if err != nil {
		h.logger.Error("query webhook logs", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer rows.Close()

	var entries []webhookDeliveryLogEntry
	for rows.Next() {
		var e webhookDeliveryLogEntry
		if err := rows.Scan(&e.ID, &e.WebhookID, &e.Event, &e.StatusCode, &e.Response, &e.Error, &e.DeliveredAt); err != nil {
			h.logger.Error("scan webhook log", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		entries = append(entries, e)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate webhook logs", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if entries == nil {
		entries = []webhookDeliveryLogEntry{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": entries,
	})
}

// HandleTest sends a test POST to the webhook URL and records the result.
// POST /admin/webhooks/{webhookID}/test
func (h *WebhookHandler) HandleTest(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	if claims.Role != "admin" {
		writeJSON(w, http.StatusForbidden, errorResponse("admin_required"))
		return
	}

	webhookID, err := uuid.Parse(chi.URLParam(r, "webhookID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_webhook_id"))
		return
	}

	// Fetch the webhook
	var wh webhookEntry
	err = h.db.QueryRow(r.Context(),
		`SELECT id, url, events, secret, enabled, created_at, updated_at
		 FROM webhooks WHERE id = $1`,
		webhookID,
	).Scan(&wh.ID, &wh.URL, &wh.Events, &wh.Secret, &wh.Enabled, &wh.CreatedAt, &wh.UpdatedAt)
	if err != nil {
		h.logger.Error("fetch webhook for test", zap.Error(err))
		writeJSON(w, http.StatusNotFound, errorResponse("webhook_not_found"))
		return
	}

	// Validate URL scheme
	parsed, parseErr := url.Parse(wh.URL)
	if parseErr != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_url"))
		return
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_url_scheme"))
		return
	}

	// Build test payload
	testPayload := map[string]interface{}{
		"event":      "test",
		"webhook_id": webhookID,
		"timestamp":  time.Now().UTC(),
		"message":    "This is a test delivery from HealthVault.",
	}
	body, _ := json.Marshal(testPayload)

	// Send the test request
	client := &http.Client{
		Timeout: 10 * time.Second,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			// Re-validate redirect target to prevent SSRF bypass
			if err := isPrivateOrLocalhost(req.URL.String()); err != nil {
				return fmt.Errorf("redirect to non-private address blocked: %w", err)
			}
			if len(via) > 3 {
				return fmt.Errorf("too many redirects")
			}
			return nil
		},
	}
	resp, err := client.Post(wh.URL, "application/json", bytes.NewReader(body))

	var statusCode *int
	var respSize *int64
	var deliveryErr *string

	if err != nil {
		errStr := err.Error()
		deliveryErr = &errStr
	} else {
		defer resp.Body.Close()
		statusCode = &resp.StatusCode
		// Only record content length, not the full response body
		if resp.ContentLength >= 0 {
			respSize = &resp.ContentLength
		}
	}

	// Record in delivery log (status code and error only, no response body)
	_, logErr := h.db.Exec(r.Context(),
		`INSERT INTO webhook_delivery_log (webhook_id, event, status_code, response, error, delivered_at)
		 VALUES ($1, 'test', $2, NULL, $3, $4)`,
		webhookID, statusCode, deliveryErr, time.Now().UTC(),
	)
	if logErr != nil {
		h.logger.Error("record webhook test delivery", zap.Error(logErr))
	}

	result := map[string]interface{}{
		"webhook_id": webhookID,
		"event":      "test",
	}
	if statusCode != nil {
		result["status_code"] = *statusCode
	}
	if respSize != nil {
		result["response_size"] = *respSize
	}
	if deliveryErr != nil {
		result["error"] = *deliveryErr
	}

	writeJSON(w, http.StatusOK, result)
}
