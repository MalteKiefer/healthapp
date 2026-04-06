package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
	"github.com/healthvault/healthvault/internal/domain/tasks"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// TaskHandler handles task endpoints.
type TaskHandler struct {
	taskRepo    tasks.Repository
	profileRepo profiles.Repository
	logger      *zap.Logger
}

func NewTaskHandler(tr tasks.Repository, pr profiles.Repository, logger *zap.Logger) *TaskHandler {
	return &TaskHandler{taskRepo: tr, profileRepo: pr, logger: logger}
}

// HandleList returns tasks for a profile.
func (h *TaskHandler) HandleList(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	profileID, err := uuid.Parse(chi.URLParam(r, "profileID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_profile_id"))
		return
	}

	hasAccess, err := h.profileRepo.HasAccess(r.Context(), profileID, claims.UserID)
	if err != nil || !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	items, err := h.taskRepo.List(r.Context(), profileID)
	if err != nil {
		h.logger.Error("list tasks", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": len(items),
	})
}

// HandleCreate creates a new task.
func (h *TaskHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	profileID, err := uuid.Parse(chi.URLParam(r, "profileID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_profile_id"))
		return
	}

	hasAccess, err := h.profileRepo.HasAccess(r.Context(), profileID, claims.UserID)
	if err != nil || !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	var t tasks.Task
	if err := json.NewDecoder(r.Body).Decode(&t); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if t.Title == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("title_required"))
		return
	}

	t.ProfileID = profileID
	t.CreatedByUserID = claims.UserID

	if err := h.taskRepo.Create(r.Context(), &t); err != nil {
		h.logger.Error("create task", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, t)
}

// HandleGetOpen is deprecated — filtering is now done client-side after
// decrypting the full list.
func (h *TaskHandler) HandleGetOpen(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{
		"error":   "endpoint_removed",
		"message": "This endpoint has been removed. Use the list endpoint with client-side filtering instead.",
	})
}

// HandleUpdate patches a task. If status changed to "done", sets done_at.
func (h *TaskHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	profileID, err := uuid.Parse(chi.URLParam(r, "profileID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_profile_id"))
		return
	}

	hasAccess, err := h.profileRepo.HasAccess(r.Context(), profileID, claims.UserID)
	if err != nil || !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	taskID, err := uuid.Parse(chi.URLParam(r, "taskID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_task_id"))
		return
	}

	existing, err := h.taskRepo.GetByID(r.Context(), taskID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get task", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	oldStatus := existing.Status

	if err := json.NewDecoder(r.Body).Decode(existing); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	// If status changed to "done", set done_at
	if existing.Status == "done" && oldStatus != "done" {
		now := time.Now().UTC()
		existing.DoneAt = &now
	}

	if err := h.taskRepo.Update(r.Context(), existing); err != nil {
		h.logger.Error("update task", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, existing)
}

// HandleDelete deletes a task.
func (h *TaskHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	profileID, err := uuid.Parse(chi.URLParam(r, "profileID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_profile_id"))
		return
	}

	hasAccess, err := h.profileRepo.HasAccess(r.Context(), profileID, claims.UserID)
	if err != nil || !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	taskID, err := uuid.Parse(chi.URLParam(r, "taskID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_task_id"))
		return
	}

	existing, err := h.taskRepo.GetByID(r.Context(), taskID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get task", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if err := h.taskRepo.Delete(r.Context(), taskID); err != nil {
		h.logger.Error("delete task", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleMigrateContent lazily backfills the content_enc column for a task row.
// Idempotent: the repo writes only if the column is currently NULL, so
// concurrent clients (e.g. web + mobile) cannot overwrite each other.
// PATCH /profiles/{profileID}/tasks/{taskID}/migrate-content
func (h *TaskHandler) HandleMigrateContent(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	profileID, err := uuid.Parse(chi.URLParam(r, "profileID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_profile_id"))
		return
	}
	hasAccess, err := h.profileRepo.HasAccess(r.Context(), profileID, claims.UserID)
	if err != nil || !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	taskID, err := uuid.Parse(chi.URLParam(r, "taskID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_task_id"))
		return
	}

	existing, err := h.taskRepo.GetByID(r.Context(), taskID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get task for migrate", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	var body struct {
		ContentEnc string `json:"content_enc"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.ContentEnc == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("content_enc_required"))
		return
	}

	if err := h.taskRepo.SetContentEnc(r.Context(), taskID, body.ContentEnc); err != nil {
		h.logger.Error("set content_enc", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
