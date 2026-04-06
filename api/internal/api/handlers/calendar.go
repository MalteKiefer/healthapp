package handlers

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/appointments"
	"github.com/healthvault/healthvault/internal/domain/calendar"
	"github.com/healthvault/healthvault/internal/domain/contacts"
	"github.com/healthvault/healthvault/internal/domain/tasks"
	"github.com/healthvault/healthvault/internal/domain/vaccinations"
)

// CalendarHandler handles ICS feed management and generation.
type CalendarHandler struct {
	feedRepo    calendar.Repository
	apptRepo    appointments.Repository
	taskRepo    tasks.Repository
	vaccRepo    vaccinations.Repository
	contactRepo contacts.Repository
	logger      *zap.Logger
	hostname    string
}

func NewCalendarHandler(
	fr calendar.Repository,
	ar appointments.Repository,
	tr tasks.Repository,
	vr vaccinations.Repository,
	cr contacts.Repository,
	logger *zap.Logger,
	hostname string,
) *CalendarHandler {
	return &CalendarHandler{
		feedRepo: fr, apptRepo: ar, taskRepo: tr, vaccRepo: vr,
		contactRepo: cr, logger: logger, hostname: hostname,
	}
}

// ── Feed Management (authenticated) ────────────────────────────────

func (h *CalendarHandler) HandleListFeeds(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	feeds, err := h.feedRepo.ListByUserID(r.Context(), claims.UserID)
	if err != nil {
		h.logger.Error("list feeds", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"items": feeds})
}

func (h *CalendarHandler) HandleCreateFeed(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	var req struct {
		Name                string      `json:"name"`
		ProfileIDs          []uuid.UUID `json:"profile_ids"`
		IncludeAppointments *bool       `json:"include_appointments"`
		IncludeTasks        *bool       `json:"include_tasks"`
		IncludeVaccinations *bool       `json:"include_vaccinations"`
		IncludeMedications  *bool       `json:"include_medications"`
		IncludeLabs         *bool       `json:"include_labs"`
		VerboseMode         bool        `json:"verbose_mode"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}
	if req.Name == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("name_required"))
		return
	}

	// Generate 256-bit token
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		h.logger.Error("generate token", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	token := base64.RawURLEncoding.EncodeToString(tokenBytes)
	tokenHash := fmt.Sprintf("%x", sha256.Sum256([]byte(token)))

	feed := &calendar.Feed{
		UserID:              claims.UserID,
		Name:                req.Name,
		TokenHash:           tokenHash,
		ProfileIDs:          req.ProfileIDs,
		IncludeAppointments: req.IncludeAppointments == nil || *req.IncludeAppointments,
		IncludeTasks:        req.IncludeTasks == nil || *req.IncludeTasks,
		IncludeVaccinations: req.IncludeVaccinations == nil || *req.IncludeVaccinations,
		IncludeMedications:  req.IncludeMedications != nil && *req.IncludeMedications,
		IncludeLabs:         req.IncludeLabs == nil || *req.IncludeLabs,
		VerboseMode:         req.VerboseMode,
	}

	if err := h.feedRepo.Create(r.Context(), feed); err != nil {
		h.logger.Error("create feed", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusCreated, calendar.FeedWithToken{
		Feed:  *feed,
		Token: token,
		URL:   fmt.Sprintf("https://%s/cal/%s.ics", h.hostname, token),
	})
}

func (h *CalendarHandler) HandleGetFeed(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	feedID, err := uuid.Parse(chi.URLParam(r, "feedID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_id"))
		return
	}
	feed, err := h.feedRepo.GetByID(r.Context(), feedID)
	if err != nil || feed.UserID != claims.UserID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}
	writeJSON(w, http.StatusOK, feed)
}

func (h *CalendarHandler) HandleUpdateFeed(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	feedID, _ := uuid.Parse(chi.URLParam(r, "feedID"))
	feed, err := h.feedRepo.GetByID(r.Context(), feedID)
	if err != nil || feed.UserID != claims.UserID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}
	if err := json.NewDecoder(r.Body).Decode(feed); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}
	if err := h.feedRepo.Update(r.Context(), feed); err != nil {
		h.logger.Error("update feed", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	writeJSON(w, http.StatusOK, feed)
}

func (h *CalendarHandler) HandleDeleteFeed(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	feedID, _ := uuid.Parse(chi.URLParam(r, "feedID"))
	feed, err := h.feedRepo.GetByID(r.Context(), feedID)
	if err != nil || feed.UserID != claims.UserID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}
	if err := h.feedRepo.Delete(r.Context(), feedID); err != nil {
		h.logger.Error("delete feed", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// HandleMigrateContent lazily backfills the content_enc column for a
// calendar feed row. Idempotent: the repo writes only if the column is
// currently NULL.
// PATCH /calendar/feeds/{feedID}/migrate-content
func (h *CalendarHandler) HandleMigrateContent(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}
	feedID, err := uuid.Parse(chi.URLParam(r, "feedID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_id"))
		return
	}
	feed, err := h.feedRepo.GetByID(r.Context(), feedID)
	if err != nil || feed.UserID != claims.UserID {
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

	if err := h.feedRepo.SetContentEnc(r.Context(), feedID, body.ContentEnc); err != nil {
		h.logger.Error("set content_enc", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// ── ICS Feed Endpoint (token-based, no auth header) ────────────────

func (h *CalendarHandler) HandleICSFeed(w http.ResponseWriter, r *http.Request) {
	tokenParam := chi.URLParam(r, "token")
	// Strip .ics suffix if present from routing
	tokenParam = strings.TrimSuffix(tokenParam, ".ics")

	tokenHash := fmt.Sprintf("%x", sha256.Sum256([]byte(tokenParam)))

	feed, err := h.feedRepo.GetByTokenHash(r.Context(), tokenHash)
	if err != nil {
		http.NotFound(w, r)
		return
	}

	// Update last polled timestamp async
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = h.feedRepo.UpdateLastPolled(ctx, feed.ID)
	}()

	// Collect events from all configured sources
	var events []calendar.CalendarEvent

	for _, profileID := range feed.ProfileIDs {
		if feed.IncludeAppointments {
			appts, err := h.apptRepo.GetUpcoming(r.Context(), profileID)
			if err == nil {
				for _, a := range appts {
					summary := "Medical Appointment"
					desc := "Open HealthVault for details"
					loc := ""
					if feed.VerboseMode {
						summary = a.Title
						if a.PreparationNotes != nil {
							desc = *a.PreparationNotes
						}
					}
					// Location is always included (not sensitive)
					if a.Location != nil && *a.Location != "" {
						loc = *a.Location
					} else if a.DoctorID != nil {
						// Fall back to doctor's address
						if doc, err := h.contactRepo.GetByID(r.Context(), *a.DoctorID); err == nil && doc.Address != nil {
							loc = *doc.Address
						}
					}

					var end *time.Time
					if a.DurationMinutes != nil {
						t := a.ScheduledAt.Add(time.Duration(*a.DurationMinutes) * time.Minute)
						end = &t
					}

					ev := calendar.CalendarEvent{
						UID:         fmt.Sprintf("appt-%s", a.ID),
						Summary:     summary,
						Description: desc,
						Location:    loc,
						Start:       a.ScheduledAt,
						End:         end,
						Alarms: []calendar.Alarm{
							{TriggerBefore: 24 * time.Hour, Description: "Upcoming appointment tomorrow"},
							{TriggerBefore: 2 * time.Hour, Description: "Appointment in 2 hours"},
						},
					}
					events = append(events, ev)
				}
			}
		}

		if feed.IncludeTasks {
			openTasks, err := h.taskRepo.GetOpen(r.Context(), profileID)
			if err == nil {
				for _, t := range openTasks {
					if t.DueDate == nil {
						continue
					}
					summary := "Medical Follow-up Due"
					if feed.VerboseMode {
						summary = t.Title
					}
					priority := 5
					switch t.Priority {
					case "urgent":
						priority = 1
					case "high":
						priority = 3
					case "low":
						priority = 9
					}

					events = append(events, calendar.CalendarEvent{
						UID:         fmt.Sprintf("task-%s", t.ID),
						Summary:     summary,
						Description: "Open HealthVault for details",
						Start:       *t.DueDate,
						AllDay:      true,
						IsTodo:      true,
						Priority:    priority,
						Status:      "NEEDS-ACTION",
					})
				}
			}
		}

		if feed.IncludeVaccinations {
			dueVaccs, err := h.vaccRepo.GetDue(r.Context(), profileID)
			if err == nil {
				for _, v := range dueVaccs {
					if v.NextDueAt == nil {
						continue
					}
					summary := "Vaccination Due"
					if feed.VerboseMode {
						summary = fmt.Sprintf("Vaccination Due: %s", v.VaccineName)
					}
					events = append(events, calendar.CalendarEvent{
						UID:     fmt.Sprintf("vacc-due-%s", v.ID),
						Summary: summary,
						Start:   *v.NextDueAt,
						AllDay:  true,
						Alarms: []calendar.Alarm{
							{TriggerBefore: 30 * 24 * time.Hour, Description: "Vaccination due in 30 days"},
							{TriggerBefore: 7 * 24 * time.Hour, Description: "Vaccination due in 7 days"},
						},
					})
				}
			}
		}
	}

	icsContent := calendar.GenerateICS(
		fmt.Sprintf("HealthVault — %s", feed.Name),
		"UTC",
		events,
	)

	w.Header().Set("Content-Type", "text/calendar; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="healthvault.ics"`)
	w.Header().Set("Cache-Control", "no-cache, no-store")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(icsContent))
}
