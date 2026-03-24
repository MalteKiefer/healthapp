package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
	"github.com/healthvault/healthvault/internal/domain/tasks"
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

// HandleGetOpen returns open tasks for a profile.
func (h *TaskHandler) HandleGetOpen(w http.ResponseWriter, r *http.Request) {
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

	items, err := h.taskRepo.GetOpen(r.Context(), profileID)
	if err != nil {
		h.logger.Error("get open tasks", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
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
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
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
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
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
