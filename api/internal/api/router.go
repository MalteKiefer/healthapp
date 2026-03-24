package api

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/api/handlers"
	"github.com/healthvault/healthvault/internal/api/middleware"
	"github.com/healthvault/healthvault/internal/config"
	"github.com/healthvault/healthvault/internal/crypto"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// Server holds dependencies for HTTP handlers.
type Server struct {
	Router         *chi.Mux
	DB             *pgxpool.Pool
	Redis          *redis.Client
	Logger         *zap.Logger
	Config         *config.Config
	TokenService   *crypto.TokenService
	AuthHandler    *handlers.AuthHandler
	ProfileHandler *handlers.ProfileHandler
	VitalHandler   *handlers.VitalHandler
}

// NewServer creates a configured HTTP server with all routes.
func NewServer(db *pgxpool.Pool, rdb *redis.Client, logger *zap.Logger, cfg *config.Config, ts *crypto.TokenService) *Server {
	userRepo := postgres.NewUserRepo(db)
	profileRepo := postgres.NewProfileRepo(db)
	vitalRepo := postgres.NewVitalRepo(db)

	authHandler := handlers.NewAuthHandler(userRepo, ts, logger, cfg.Instance.DefaultQuotaMB)
	profileHandler := handlers.NewProfileHandler(profileRepo, logger)
	vitalHandler := handlers.NewVitalHandler(vitalRepo, profileRepo, logger)

	s := &Server{
		Router:         chi.NewRouter(),
		DB:             db,
		Redis:          rdb,
		Logger:         logger,
		Config:         cfg,
		TokenService:   ts,
		AuthHandler:    authHandler,
		ProfileHandler: profileHandler,
		VitalHandler:   vitalHandler,
	}

	s.setupMiddleware()
	s.setupRoutes()

	return s
}

func (s *Server) setupMiddleware() {
	s.Router.Use(chimiddleware.RequestID)
	s.Router.Use(chimiddleware.RealIP)
	s.Router.Use(middleware.StructuredLogger(s.Logger))
	s.Router.Use(chimiddleware.Recoverer)
	s.Router.Use(chimiddleware.Timeout(30 * time.Second))
	s.Router.Use(middleware.CORS(s.Config.Instance.Hostname))
	s.Router.Use(middleware.SecurityHeaders)
}

func (s *Server) setupRoutes() {
	rl := middleware.NewRateLimiter(s.Redis)

	// Public endpoints — no auth required
	s.Router.Get("/health", s.handleHealth)

	// API v1
	s.Router.Route("/api/v1", func(r chi.Router) {
		// Auth routes — rate limited, no JWT required
		r.Route("/auth", func(r chi.Router) {
			r.With(rl.Limit(middleware.RateLimitConfig{
				Requests: 3, Window: time.Hour, BlockDuration: time.Hour,
			})).Post("/register", s.AuthHandler.HandleRegisterInit)

			r.With(rl.Limit(middleware.RateLimitConfig{
				Requests: 3, Window: time.Hour, BlockDuration: time.Hour,
			})).Post("/register/complete", s.AuthHandler.HandleRegisterComplete)

			r.With(rl.Limit(middleware.RateLimitConfig{
				Requests: 5, Window: 15 * time.Minute, BlockDuration: 30 * time.Minute,
			})).Post("/login", s.AuthHandler.HandleLogin)

			r.With(rl.Limit(middleware.RateLimitConfig{
				Requests: 5, Window: 15 * time.Minute, BlockDuration: 30 * time.Minute,
			})).Post("/login/2fa", s.AuthHandler.HandleLogin2FA)

			r.Post("/refresh", s.AuthHandler.HandleRefresh)
			r.Post("/logout", s.AuthHandler.HandleLogout)

			r.With(rl.Limit(middleware.RateLimitConfig{
				Requests: 3, Window: time.Hour, BlockDuration: 2 * time.Hour,
			})).Post("/recovery", s.handleNotImplemented)

			r.Get("/2fa/setup", s.handleNotImplemented)
			r.Post("/2fa/enable", s.handleNotImplemented)
			r.Post("/2fa/disable", s.handleNotImplemented)
			r.Get("/2fa/recovery-codes", s.handleNotImplemented)
		})

		// Protected routes — JWT required
		r.Group(func(r chi.Router) {
			r.Use(middleware.JWTAuth(s.TokenService))

			// Users
			r.Route("/users", func(r chi.Router) {
				r.Get("/me", s.handleNotImplemented)
				r.Patch("/me", s.handleNotImplemented)
				r.Delete("/me", s.handleNotImplemented)
				r.Get("/me/sessions", s.handleNotImplemented)
				r.Delete("/me/sessions/{sessionID}", s.handleNotImplemented)
				r.Delete("/me/sessions/others", s.handleNotImplemented)
				r.Post("/me/change-passphrase", s.handleNotImplemented)
				r.Get("/me/storage", s.handleNotImplemented)
				r.Get("/me/preferences", s.handleNotImplemented)
				r.Patch("/me/preferences", s.handleNotImplemented)
				r.Get("/{userID}/identity-pubkey", s.handleNotImplemented)
			})

			// Profiles
			r.Route("/profiles", func(r chi.Router) {
				r.Get("/", s.ProfileHandler.HandleList)
				r.Post("/", s.ProfileHandler.HandleCreate)

				r.Route("/{profileID}", func(r chi.Router) {
					r.Get("/", s.ProfileHandler.HandleGet)
					r.Patch("/", s.ProfileHandler.HandleUpdate)
					r.Delete("/", s.ProfileHandler.HandleDelete)
					r.Post("/grants", s.handleNotImplemented)
					r.Delete("/grants/{grantUserID}", s.handleNotImplemented)
					r.Post("/key-rotation", s.handleNotImplemented)
					r.Post("/transfer", s.handleNotImplemented)
					r.Post("/archive", s.ProfileHandler.HandleArchive)
					r.Post("/unarchive", s.ProfileHandler.HandleUnarchive)

					// Vitals
					r.Route("/vitals", func(r chi.Router) {
						r.Get("/", s.VitalHandler.HandleList)
						r.Post("/", s.VitalHandler.HandleCreate)
						r.Get("/chart", s.VitalHandler.HandleChart)
						r.Get("/{vitalID}", s.VitalHandler.HandleGet)
						r.Patch("/{vitalID}", s.VitalHandler.HandleUpdate)
						r.Delete("/{vitalID}", s.VitalHandler.HandleDelete)
					})

					// Labs
					r.Route("/labs", func(r chi.Router) {
						r.Get("/", s.handleNotImplemented)
						r.Post("/", s.handleNotImplemented)
						r.Get("/{labID}", s.handleNotImplemented)
						r.Patch("/{labID}", s.handleNotImplemented)
						r.Delete("/{labID}", s.handleNotImplemented)
						r.Get("/{labID}/export/pdf", s.handleNotImplemented)
					})

					// Documents
					r.Route("/documents", func(r chi.Router) {
						r.Get("/", s.handleNotImplemented)
						r.Post("/", s.handleNotImplemented)
						r.Post("/bulk", s.handleNotImplemented)
						r.Get("/search", s.handleNotImplemented)
						r.Get("/{docID}", s.handleNotImplemented)
						r.Patch("/{docID}", s.handleNotImplemented)
						r.Delete("/{docID}", s.handleNotImplemented)
						r.Post("/{docID}/ocr-index", s.handleNotImplemented)
						r.Delete("/{docID}/ocr-index", s.handleNotImplemented)
					})

					// Health Diary
					r.Route("/diary", func(r chi.Router) {
						r.Get("/", s.handleNotImplemented)
						r.Post("/", s.handleNotImplemented)
						r.Get("/{eventID}", s.handleNotImplemented)
						r.Patch("/{eventID}", s.handleNotImplemented)
						r.Delete("/{eventID}", s.handleNotImplemented)
					})

					// Medications
					r.Route("/medications", func(r chi.Router) {
						r.Get("/", s.handleNotImplemented)
						r.Post("/", s.handleNotImplemented)
						r.Get("/active", s.handleNotImplemented)
						r.Get("/adherence", s.handleNotImplemented)
						r.Patch("/{medID}", s.handleNotImplemented)
						r.Delete("/{medID}", s.handleNotImplemented)
						r.Get("/{medID}/intake", s.handleNotImplemented)
						r.Post("/{medID}/intake", s.handleNotImplemented)
						r.Patch("/{medID}/intake/{intakeID}", s.handleNotImplemented)
						r.Delete("/{medID}/intake/{intakeID}", s.handleNotImplemented)
					})

					// Allergies
					r.Route("/allergies", func(r chi.Router) {
						r.Get("/", s.handleNotImplemented)
						r.Post("/", s.handleNotImplemented)
						r.Patch("/{allergyID}", s.handleNotImplemented)
						r.Delete("/{allergyID}", s.handleNotImplemented)
					})

					// Vaccinations
					r.Route("/vaccinations", func(r chi.Router) {
						r.Get("/", s.handleNotImplemented)
						r.Post("/", s.handleNotImplemented)
						r.Get("/due", s.handleNotImplemented)
						r.Patch("/{vaccID}", s.handleNotImplemented)
						r.Delete("/{vaccID}", s.handleNotImplemented)
					})

					// Diagnoses
					r.Route("/diagnoses", func(r chi.Router) {
						r.Get("/", s.handleNotImplemented)
						r.Post("/", s.handleNotImplemented)
						r.Patch("/{diagID}", s.handleNotImplemented)
						r.Delete("/{diagID}", s.handleNotImplemented)
					})

					// Medical Contacts
					r.Route("/contacts", func(r chi.Router) {
						r.Get("/", s.handleNotImplemented)
						r.Post("/", s.handleNotImplemented)
						r.Patch("/{contactID}", s.handleNotImplemented)
						r.Delete("/{contactID}", s.handleNotImplemented)
					})

					// Tasks
					r.Route("/tasks", func(r chi.Router) {
						r.Get("/", s.handleNotImplemented)
						r.Post("/", s.handleNotImplemented)
						r.Get("/open", s.handleNotImplemented)
						r.Patch("/{taskID}", s.handleNotImplemented)
						r.Delete("/{taskID}", s.handleNotImplemented)
					})

					// Appointments
					r.Route("/appointments", func(r chi.Router) {
						r.Get("/", s.handleNotImplemented)
						r.Post("/", s.handleNotImplemented)
						r.Get("/upcoming", s.handleNotImplemented)
						r.Patch("/{apptID}", s.handleNotImplemented)
						r.Delete("/{apptID}", s.handleNotImplemented)
						r.Post("/{apptID}/complete", s.handleNotImplemented)
					})

					// Symptoms
					r.Route("/symptoms", func(r chi.Router) {
						r.Get("/", s.handleNotImplemented)
						r.Post("/", s.handleNotImplemented)
						r.Get("/chart", s.handleNotImplemented)
						r.Patch("/{symptomID}", s.handleNotImplemented)
						r.Delete("/{symptomID}", s.handleNotImplemented)
					})

					// Vital Thresholds
					r.Get("/vital-thresholds", s.handleNotImplemented)
					r.Put("/vital-thresholds", s.handleNotImplemented)

					// Emergency
					r.Get("/emergency-card", s.handleNotImplemented)
					r.Post("/emergency-access", s.handleNotImplemented)
					r.Get("/emergency-access", s.handleNotImplemented)
					r.Delete("/emergency-access", s.handleNotImplemented)

					// Activity Log
					r.Get("/activity", s.handleNotImplemented)

					// Export
					r.Get("/export/fhir", s.handleNotImplemented)
					r.Post("/import/fhir", s.handleNotImplemented)
					r.Get("/export/ics", s.handleNotImplemented)
				})
			})

			// Families
			r.Route("/families", func(r chi.Router) {
				r.Get("/", s.handleNotImplemented)
				r.Post("/", s.handleNotImplemented)
				r.Route("/{familyID}", func(r chi.Router) {
					r.Get("/", s.handleNotImplemented)
					r.Patch("/", s.handleNotImplemented)
					r.Post("/invite", s.handleNotImplemented)
					r.Post("/accept", s.handleNotImplemented)
					r.Delete("/members/{memberID}", s.handleNotImplemented)
					r.Post("/dissolve", s.handleNotImplemented)
				})
			})

			// Notifications
			r.Route("/notifications", func(r chi.Router) {
				r.Get("/", s.handleNotImplemented)
				r.Post("/{notifID}/read", s.handleNotImplemented)
				r.Post("/read-all", s.handleNotImplemented)
				r.Delete("/{notifID}", s.handleNotImplemented)
				r.Get("/preferences", s.handleNotImplemented)
				r.Patch("/preferences", s.handleNotImplemented)
			})

			// Search
			r.Get("/search", s.handleNotImplemented)

			// Reference ranges
			r.Get("/reference-ranges", s.handleNotImplemented)

			// Calendar feeds
			r.Route("/calendar/feeds", func(r chi.Router) {
				r.Get("/", s.handleNotImplemented)
				r.Post("/", s.handleNotImplemented)
				r.Get("/{feedID}", s.handleNotImplemented)
				r.Patch("/{feedID}", s.handleNotImplemented)
				r.Delete("/{feedID}", s.handleNotImplemented)
			})

			// Export
			r.Route("/export", func(r chi.Router) {
				r.Post("/", s.handleNotImplemented)
				r.Post("/schedule", s.handleNotImplemented)
			})

			// Emergency (public-ish, but still under v1)
			r.Post("/emergency/request/{token}", s.handleNotImplemented)
			r.Get("/emergency/pending", s.handleNotImplemented)
			r.Post("/emergency/approve/{requestID}", s.handleNotImplemented)
			r.Post("/emergency/deny/{requestID}", s.handleNotImplemented)

			// Admin
			r.Route("/admin", func(r chi.Router) {
				r.Use(middleware.RequireAdmin)

				r.Get("/users", s.handleNotImplemented)
				r.Post("/users/{userID}/disable", s.handleNotImplemented)
				r.Post("/users/{userID}/enable", s.handleNotImplemented)
				r.Delete("/users/{userID}", s.handleNotImplemented)
				r.Get("/users/{userID}/sessions", s.handleNotImplemented)
				r.Delete("/users/{userID}/sessions", s.handleNotImplemented)
				r.Patch("/users/{userID}/quota", s.handleNotImplemented)
				r.Get("/storage", s.handleNotImplemented)
				r.Get("/invites", s.handleNotImplemented)
				r.Post("/invites", s.handleNotImplemented)
				r.Delete("/invites/{token}", s.handleNotImplemented)
				r.Get("/system", s.handleNotImplemented)
				r.Get("/backups", s.handleNotImplemented)
				r.Post("/backups/trigger", s.handleNotImplemented)
				r.Get("/audit-log", s.handleNotImplemented)
				r.Patch("/settings", s.handleNotImplemented)

				// Admin legal/consent
				r.Get("/legal/documents", s.handleNotImplemented)
				r.Post("/legal/documents", s.handleNotImplemented)
				r.Get("/legal/consent-records", s.handleNotImplemented)
				r.Get("/legal/consent-records/{userID}", s.handleNotImplemented)

				// Admin webhooks
				r.Route("/webhooks", func(r chi.Router) {
					r.Get("/", s.handleNotImplemented)
					r.Post("/", s.handleNotImplemented)
					r.Patch("/{webhookID}", s.handleNotImplemented)
					r.Delete("/{webhookID}", s.handleNotImplemented)
					r.Get("/{webhookID}/logs", s.handleNotImplemented)
					r.Post("/{webhookID}/test", s.handleNotImplemented)
				})
			})
		})
	})

	// ICS calendar feed — no auth header, token-based
	s.Router.Get("/cal/{token}.ics", s.handleNotImplemented)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	dbOK := s.DB.Ping(ctx) == nil
	redisOK := s.Redis.Ping(ctx).Err() == nil

	status := "ok"
	httpStatus := http.StatusOK
	if !dbOK || !redisOK {
		status = "degraded"
		httpStatus = http.StatusServiceUnavailable
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(httpStatus)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":   status,
		"database": dbOK,
		"redis":    redisOK,
	})
}

func (s *Server) handleNotImplemented(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusNotImplemented)
	json.NewEncoder(w).Encode(map[string]string{
		"error": "not_implemented",
	})
}
