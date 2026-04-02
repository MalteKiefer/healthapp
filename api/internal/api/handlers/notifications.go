package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/notifications"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// NotificationHandler handles notification endpoints.
type NotificationHandler struct {
	notifRepo notifications.Repository
	logger    *zap.Logger
}

func NewNotificationHandler(nr notifications.Repository, logger *zap.Logger) *NotificationHandler {
	return &NotificationHandler{notifRepo: nr, logger: logger}
}

// HandleList returns notifications for the authenticated user with pagination.
func (h *NotificationHandler) HandleList(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	filter := notifications.ListFilter{
		UserID: claims.UserID,
		Limit:  50,
	}

	if v := r.URL.Query().Get("limit"); v != "" {
		if l, err := strconv.Atoi(v); err == nil && l > 0 && l <= 200 {
			filter.Limit = l
		}
	}
	if v := r.URL.Query().Get("offset"); v != "" {
		if o, err := strconv.Atoi(v); err == nil && o >= 0 {
			filter.Offset = o
		}
	}

	items, total, err := h.notifRepo.List(r.Context(), filter)
	if err != nil {
		h.logger.Error("list notifications", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}

// HandleMarkRead marks a single notification as read.
func (h *NotificationHandler) HandleMarkRead(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	notifID, err := uuid.Parse(chi.URLParam(r, "notifID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_notification_id"))
		return
	}

	if err := h.notifRepo.MarkRead(r.Context(), notifID, claims.UserID); err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("mark notification read", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleMarkAllRead marks all notifications as read for the authenticated user.
func (h *NotificationHandler) HandleMarkAllRead(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	if err := h.notifRepo.MarkAllRead(r.Context(), claims.UserID); err != nil {
		h.logger.Error("mark all notifications read", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleDelete deletes a single notification.
func (h *NotificationHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	notifID, err := uuid.Parse(chi.URLParam(r, "notifID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_notification_id"))
		return
	}

	if err := h.notifRepo.Delete(r.Context(), notifID, claims.UserID); err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("delete notification", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleGetPreferences returns notification preferences for the authenticated user.
func (h *NotificationHandler) HandleGetPreferences(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	prefs, err := h.notifRepo.GetPreferences(r.Context(), claims.UserID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			// Return defaults when no preferences exist yet.
			writeJSON(w, http.StatusOK, &notifications.NotificationPreferences{
				UserID: claims.UserID,
			})
			return
		}
		h.logger.Error("get notification preferences", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, prefs)
}

// HandleUpdatePreferences creates or updates notification preferences.
func (h *NotificationHandler) HandleUpdatePreferences(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	var prefs notifications.NotificationPreferences
	if err := json.NewDecoder(r.Body).Decode(&prefs); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	prefs.UserID = claims.UserID

	if err := h.notifRepo.UpsertPreferences(r.Context(), &prefs); err != nil {
		h.logger.Error("update notification preferences", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, prefs)
}
