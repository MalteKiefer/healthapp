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
	Router                 *chi.Mux
	DB                     *pgxpool.Pool
	Redis                  *redis.Client
	Logger                 *zap.Logger
	Config                 *config.Config
	TokenService           *crypto.TokenService
	AuthHandler            *handlers.AuthHandler
	ProfileHandler         *handlers.ProfileHandler
	VitalHandler           *handlers.VitalHandler
	DiaryHandler           *handlers.DiaryHandler
	MedicationHandler      *handlers.MedicationHandler
	AllergyHandler         *handlers.AllergyHandler
	VaccinationHandler     *handlers.VaccinationHandler
	DiagnosisHandler       *handlers.DiagnosisHandler
	DocumentHandler        *handlers.DocumentHandler
	CalendarHandler        *handlers.CalendarHandler
	NotificationHandler    *handlers.NotificationHandler
	FamilyHandler          *handlers.FamilyHandler
	UserHandler            *handlers.UserHandler
	LabHandler             *handlers.LabHandler
	EmergencyHandler       *handlers.EmergencyHandler
	SearchHandler          *handlers.SearchHandler
	AdminHandler           *handlers.AdminHandler
	ContactHandler         *handlers.ContactHandler
	TaskHandler            *handlers.TaskHandler
	AppointmentHandler     *handlers.AppointmentHandler
	SymptomHandler         *handlers.SymptomHandler
	TOTPHandler            *handlers.TOTPHandler
	ExportHandler          *handlers.ExportHandler
	ThresholdHandler       *handlers.ThresholdHandler
	InviteHandler          *handlers.InviteHandler
	WebhookHandler         *handlers.WebhookHandler
	LegalHandler           *handlers.LegalHandler
	GrantHandler           *handlers.GrantHandler
	ActivityHandler        *handlers.ActivityHandler
	ReferenceRangeHandler  *handlers.ReferenceRangeHandler
	PDFHandler             *handlers.PDFHandler
	DoctorShareHandler     *handlers.DoctorShareHandler
	ScheduledExportHandler *handlers.ScheduledExportHandler
}

// NewServer creates a configured HTTP server with all routes.
func NewServer(db *pgxpool.Pool, rdb *redis.Client, logger *zap.Logger, cfg *config.Config, ts *crypto.TokenService) *Server {
	userRepo := postgres.NewUserRepo(db)
	profileRepo := postgres.NewProfileRepo(db)
	vitalRepo := postgres.NewVitalRepo(db)
	diaryRepo := postgres.NewDiaryRepo(db)
	medRepo := postgres.NewMedicationRepo(db)
	allergyRepo := postgres.NewAllergyRepo(db)
	vaccRepo := postgres.NewVaccinationRepo(db)
	diagRepo := postgres.NewDiagnosisRepo(db)
	docRepo := postgres.NewDocumentRepo(db)

	// Derive a 32-byte AES-256 encryption key from the JWT private key.
	// This key is used to encrypt/decrypt TOTP secrets at rest.
	totpEncKey := ts.DeriveEncryptionKey()

	authHandler := handlers.NewAuthHandler(userRepo, ts, db, rdb, logger, cfg.Instance.DefaultQuotaMB, totpEncKey, cfg.Instance.Hostname)
	profileHandler := handlers.NewProfileHandler(profileRepo, logger)
	vitalHandler := handlers.NewVitalHandler(vitalRepo, profileRepo, logger)
	diaryHandler := handlers.NewDiaryHandler(diaryRepo, profileRepo, logger)
	medHandler := handlers.NewMedicationHandler(medRepo, profileRepo, logger)
	allergyHandler := handlers.NewAllergyHandler(allergyRepo, profileRepo, logger)
	vaccHandler := handlers.NewVaccinationHandler(vaccRepo, profileRepo, logger)
	diagHandler := handlers.NewDiagnosisHandler(diagRepo, profileRepo, logger)
	docHandler := handlers.NewDocumentHandler(docRepo, profileRepo, "/data/uploads", logger)

	contactRepo := postgres.NewContactRepo(db)
	symptomRepo := postgres.NewSymptomRepo(db)

	calRepo := postgres.NewCalendarRepo(db)
	apptRepo := postgres.NewAppointmentRepo(db)
	taskRepo := postgres.NewTaskRepo(db)
	calHandler := handlers.NewCalendarHandler(calRepo, apptRepo, taskRepo, vaccRepo, contactRepo, logger, cfg.Instance.Hostname)

	contactHandler := handlers.NewContactHandler(contactRepo, profileRepo, logger)
	taskHandler := handlers.NewTaskHandler(taskRepo, profileRepo, logger)
	apptHandler := handlers.NewAppointmentHandler(apptRepo, profileRepo, logger)
	symptomHandler := handlers.NewSymptomHandler(symptomRepo, profileRepo, logger)

	notifRepo := postgres.NewNotificationRepo(db)
	notifHandler := handlers.NewNotificationHandler(notifRepo, logger)

	familyRepo := postgres.NewFamilyRepo(db)
	familyHandler := handlers.NewFamilyHandler(familyRepo, logger, db)

	userHandler := handlers.NewUserHandler(db, userRepo, logger)
	labRepo := postgres.NewLabRepo(db)
	labHandler := handlers.NewLabHandler(labRepo, profileRepo, logger)
	emergencyHandler := handlers.NewEmergencyHandler(db, logger)
	searchHandler := handlers.NewSearchHandler(db, logger)
	adminHandler := handlers.NewAdminHandler(db, rdb, logger)
	totpHandler := handlers.NewTOTPHandler(userRepo, logger, totpEncKey)
	exportHandler := handlers.NewExportHandler(db, logger)
	thresholdHandler := handlers.NewThresholdHandler(db, profileRepo, logger)
	inviteHandler := handlers.NewInviteHandler(db, logger)
	webhookHandler := handlers.NewWebhookHandler(db, logger)
	legalHandler := handlers.NewLegalHandler(db, logger)
	grantHandler := handlers.NewGrantHandler(db, profileRepo, logger)
	activityHandler := handlers.NewActivityHandler(db, profileRepo, logger)
	referenceRangeHandler := handlers.NewReferenceRangeHandler()
	pdfHandler := handlers.NewPDFHandler(db, profileRepo, logger)
	doctorShareHandler := handlers.NewDoctorShareHandler(db, profileRepo, logger, cfg.Instance.Hostname)
	scheduledExportHandler := handlers.NewScheduledExportHandler(db, logger)

	s := &Server{
		Router:                 chi.NewRouter(),
		DB:                     db,
		Redis:                  rdb,
		Logger:                 logger,
		Config:                 cfg,
		TokenService:           ts,
		AuthHandler:            authHandler,
		ProfileHandler:         profileHandler,
		VitalHandler:           vitalHandler,
		DiaryHandler:           diaryHandler,
		MedicationHandler:      medHandler,
		AllergyHandler:         allergyHandler,
		VaccinationHandler:     vaccHandler,
		DiagnosisHandler:       diagHandler,
		DocumentHandler:        docHandler,
		CalendarHandler:        calHandler,
		NotificationHandler:    notifHandler,
		FamilyHandler:          familyHandler,
		UserHandler:            userHandler,
		LabHandler:             labHandler,
		EmergencyHandler:       emergencyHandler,
		SearchHandler:          searchHandler,
		AdminHandler:           adminHandler,
		ContactHandler:         contactHandler,
		TaskHandler:            taskHandler,
		AppointmentHandler:     apptHandler,
		SymptomHandler:         symptomHandler,
		TOTPHandler:            totpHandler,
		ExportHandler:          exportHandler,
		ThresholdHandler:       thresholdHandler,
		InviteHandler:          inviteHandler,
		WebhookHandler:         webhookHandler,
		LegalHandler:           legalHandler,
		GrantHandler:           grantHandler,
		ActivityHandler:        activityHandler,
		ReferenceRangeHandler:  referenceRangeHandler,
		PDFHandler:             pdfHandler,
		DoctorShareHandler:     doctorShareHandler,
		ScheduledExportHandler: scheduledExportHandler,
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
	s.Router.Use(middleware.MaxBodySize(50 << 20)) // 50MB global limit — covers file uploads; JSON handlers are far smaller in practice
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
				Requests: 10, Window: 5 * time.Minute, BlockDuration: 10 * time.Minute,
			})).Post("/login", s.AuthHandler.HandleLogin)

			r.With(rl.Limit(middleware.RateLimitConfig{
				Requests: 10, Window: 5 * time.Minute, BlockDuration: 10 * time.Minute,
			})).Post("/login/2fa", s.AuthHandler.HandleLogin2FA)

			r.With(rl.Limit(middleware.RateLimitConfig{
				Requests: 30, Window: time.Hour, BlockDuration: 30 * time.Minute,
			})).Post("/refresh", s.AuthHandler.HandleRefresh)
			r.Post("/logout", s.AuthHandler.HandleLogout)

			r.Get("/policy", s.AuthHandler.HandleGetPolicy)

			r.With(rl.Limit(middleware.RateLimitConfig{
				Requests: 3, Window: time.Hour, BlockDuration: 2 * time.Hour,
			})).Post("/recovery", s.AuthHandler.HandleRecovery)
		})

		// Protected routes — JWT required
		r.Group(func(r chi.Router) {
			r.Use(middleware.JWTAuth(s.TokenService))
			r.Use(middleware.ConsentCheck(s.DB, s.Redis))
			r.Use(middleware.SessionTimeout(s.Redis, s.Config.Instance.SessionTimeout))

			// 2FA management (requires authenticated user)
			r.Route("/auth/2fa", func(r chi.Router) {
				r.Get("/setup", s.TOTPHandler.HandleSetup)
				r.Post("/enable", s.TOTPHandler.HandleEnable)
				r.Post("/disable", s.TOTPHandler.HandleDisable)
				r.Get("/recovery-codes", s.TOTPHandler.HandleRegenerateRecoveryCodes)
			})

			// Users
			r.Route("/users", func(r chi.Router) {
				r.Get("/me", s.UserHandler.HandleGetMe)
				r.Patch("/me", s.UserHandler.HandleUpdateMe)
				r.Delete("/me", s.UserHandler.HandleDeleteMe)
				r.Get("/me/sessions", s.UserHandler.HandleGetSessions)
				r.Delete("/me/sessions/{sessionID}", s.UserHandler.HandleRevokeSession)
				r.Delete("/me/sessions/others", s.UserHandler.HandleRevokeOtherSessions)
				r.Post("/me/change-passphrase", s.UserHandler.HandleChangePassphrase)
				r.Patch("/me/keys", s.UserHandler.HandleUpdateKeys)
				r.Get("/me/storage", s.UserHandler.HandleGetStorage)
				r.Get("/me/preferences", s.UserHandler.HandleGetPreferences)
				r.Patch("/me/preferences", s.UserHandler.HandleUpdatePreferences)
				r.Get("/{userID}/identity-pubkey", s.UserHandler.HandleGetPublicKey)
			})

			// Profiles
			r.Route("/profiles", func(r chi.Router) {
				r.Get("/", s.ProfileHandler.HandleList)
				r.Post("/", s.ProfileHandler.HandleCreate)

				r.Route("/{profileID}", func(r chi.Router) {
					r.Get("/", s.ProfileHandler.HandleGet)
					r.Patch("/", s.ProfileHandler.HandleUpdate)
					r.Delete("/", s.ProfileHandler.HandleDelete)
					r.Get("/grants", s.GrantHandler.HandleListGrants)
					r.Post("/grants", s.GrantHandler.HandleCreateGrant)
					r.Delete("/grants/{grantUserID}", s.GrantHandler.HandleRevokeGrant)
					r.Get("/my-grant", s.GrantHandler.HandleGetMyGrant)
					r.Post("/key-rotation", s.GrantHandler.HandleKeyRotation)
					r.Post("/transfer", s.GrantHandler.HandleTransfer)
					r.Post("/archive", s.ProfileHandler.HandleArchive)
					r.Post("/unarchive", s.ProfileHandler.HandleUnarchive)

					// Vitals
					r.Route("/vitals", func(r chi.Router) {
						r.Get("/", s.VitalHandler.HandleList)
						r.Post("/", s.VitalHandler.HandleCreate)
						r.Get("/chart", s.VitalHandler.HandleChart) // 410 Gone — client-side under Stage 2
						r.Get("/{vitalID}", s.VitalHandler.HandleGet)
						r.Patch("/{vitalID}", s.VitalHandler.HandleUpdate)
						r.Delete("/{vitalID}", s.VitalHandler.HandleDelete)
						r.Patch("/{vitalID}/migrate-content", s.VitalHandler.HandleMigrateContent)
					})

					// Labs
					r.Route("/labs", func(r chi.Router) {
						r.Get("/", s.LabHandler.HandleList)
						r.Post("/", s.LabHandler.HandleCreate)
						r.Get("/trends", s.LabHandler.HandleTrends)
						r.Get("/{labID}", s.LabHandler.HandleGet)
						r.Patch("/{labID}", s.LabHandler.HandleUpdate)
						r.Delete("/{labID}", s.LabHandler.HandleDelete)
						r.Get("/{labID}/export/pdf", s.LabHandler.HandleExportPDF)
						r.Patch("/{labID}/migrate-content", s.LabHandler.HandleLabResultMigrateContent)
						r.Patch("/{labID}/values/{valueID}/migrate-content", s.LabHandler.HandleLabValueMigrateContent)
					})

					// Documents
					r.Route("/documents", func(r chi.Router) {
						r.Get("/", s.DocumentHandler.HandleList)
						r.Post("/", s.DocumentHandler.HandleCreate)
						r.Post("/bulk", s.DocumentHandler.HandleBulkUpload)
						r.Get("/search", s.DocumentHandler.HandleSearch)
						r.Get("/{documentID}", s.DocumentHandler.HandleGet)
						r.Get("/{documentID}/download", s.DocumentHandler.HandleDownload)
						r.Patch("/{documentID}", s.DocumentHandler.HandleUpdate)
						r.Delete("/{documentID}", s.DocumentHandler.HandleDelete)
						r.Post("/{documentID}/ocr-index", s.DocumentHandler.HandleCreateOCRIndex)
						r.Delete("/{documentID}/ocr-index", s.DocumentHandler.HandleDeleteOCRIndex)
					})

					// Health Diary
					r.Route("/diary", func(r chi.Router) {
						r.Get("/", s.DiaryHandler.HandleList)
						r.Post("/", s.DiaryHandler.HandleCreate)
						r.Get("/{eventID}", s.DiaryHandler.HandleGet)
						r.Patch("/{eventID}", s.DiaryHandler.HandleUpdate)
						r.Delete("/{eventID}", s.DiaryHandler.HandleDelete)
						r.Patch("/{eventID}/migrate-content", s.DiaryHandler.HandleMigrateContent)
					})

					// Medications
					r.Route("/medications", func(r chi.Router) {
						r.Get("/", s.MedicationHandler.HandleList)
						r.Post("/", s.MedicationHandler.HandleCreate)
						r.Get("/active", s.MedicationHandler.HandleActive)
						r.Get("/adherence", s.MedicationHandler.HandleAdherence)
						r.Patch("/{medicationID}", s.MedicationHandler.HandleUpdate)
						r.Delete("/{medicationID}", s.MedicationHandler.HandleDelete)
						r.Get("/{medicationID}/intake", s.MedicationHandler.HandleListIntake)
						r.Post("/{medicationID}/intake", s.MedicationHandler.HandleCreateIntake)
						r.Patch("/{medicationID}/intake/{intakeID}", s.MedicationHandler.HandleUpdateIntake)
						r.Delete("/{medicationID}/intake/{intakeID}", s.MedicationHandler.HandleDeleteIntake)
						r.Patch("/{medicationID}/migrate-content", s.MedicationHandler.HandleMedicationMigrateContent)
						r.Patch("/{medicationID}/intake/{intakeID}/migrate-content", s.MedicationHandler.HandleMedicationIntakeMigrateContent)
					})

					// Allergies
					r.Route("/allergies", func(r chi.Router) {
						r.Get("/", s.AllergyHandler.HandleList)
						r.Post("/", s.AllergyHandler.HandleCreate)
						r.Patch("/{allergyID}", s.AllergyHandler.HandleUpdate)
						r.Delete("/{allergyID}", s.AllergyHandler.HandleDelete)
						r.Patch("/{allergyID}/migrate-content", s.AllergyHandler.HandleMigrateContent)
					})

					// Vaccinations
					r.Route("/vaccinations", func(r chi.Router) {
						r.Get("/", s.VaccinationHandler.HandleList)
						r.Post("/", s.VaccinationHandler.HandleCreate)
						r.Get("/due", s.VaccinationHandler.HandleDue)
						r.Patch("/{vaccID}", s.VaccinationHandler.HandleUpdate)
						r.Delete("/{vaccID}", s.VaccinationHandler.HandleDelete)
						r.Patch("/{vaccID}/migrate-content", s.VaccinationHandler.HandleMigrateContent)
					})

					// Diagnoses
					r.Route("/diagnoses", func(r chi.Router) {
						r.Get("/", s.DiagnosisHandler.HandleList)
						r.Post("/", s.DiagnosisHandler.HandleCreate)
						r.Patch("/{diagID}", s.DiagnosisHandler.HandleUpdate)
						r.Delete("/{diagID}", s.DiagnosisHandler.HandleDelete)
						r.Patch("/{diagID}/migrate-content", s.DiagnosisHandler.HandleMigrateContent)
					})

					// Medical Contacts
					r.Route("/contacts", func(r chi.Router) {
						r.Get("/", s.ContactHandler.HandleList)
						r.Post("/", s.ContactHandler.HandleCreate)
						r.Patch("/{contactID}", s.ContactHandler.HandleUpdate)
						r.Delete("/{contactID}", s.ContactHandler.HandleDelete)
						r.Patch("/{contactID}/migrate-content", s.ContactHandler.HandleMigrateContent)
					})

					// Tasks
					r.Route("/tasks", func(r chi.Router) {
						r.Get("/", s.TaskHandler.HandleList)
						r.Post("/", s.TaskHandler.HandleCreate)
						r.Get("/open", s.TaskHandler.HandleGetOpen)
						r.Patch("/{taskID}", s.TaskHandler.HandleUpdate)
						r.Delete("/{taskID}", s.TaskHandler.HandleDelete)
						r.Patch("/{taskID}/migrate-content", s.TaskHandler.HandleMigrateContent)
					})

					// Appointments
					r.Route("/appointments", func(r chi.Router) {
						r.Get("/", s.AppointmentHandler.HandleList)
						r.Post("/", s.AppointmentHandler.HandleCreate)
						r.Get("/upcoming", s.AppointmentHandler.HandleGetUpcoming)
						r.Patch("/{apptID}", s.AppointmentHandler.HandleUpdate)
						r.Delete("/{apptID}", s.AppointmentHandler.HandleDelete)
						r.Post("/{apptID}/complete", s.AppointmentHandler.HandleComplete)
						r.Patch("/{apptID}/migrate-content", s.AppointmentHandler.HandleMigrateContent)
					})

					// Symptoms
					r.Route("/symptoms", func(r chi.Router) {
						r.Get("/", s.SymptomHandler.HandleList)
						r.Post("/", s.SymptomHandler.HandleCreate)
						r.Get("/chart", s.SymptomHandler.HandleChart)
						r.Get("/{symptomID}", s.SymptomHandler.HandleGet)
						r.Patch("/{symptomID}", s.SymptomHandler.HandleUpdate)
						r.Delete("/{symptomID}", s.SymptomHandler.HandleDelete)
						r.Patch("/{symptomID}/migrate-content", s.SymptomHandler.HandleSymptomRecordMigrateContent)
						r.Patch("/{symptomID}/entries/{entryID}/migrate-content", s.SymptomHandler.HandleSymptomEntryMigrateContent)
					})

					// Vital Thresholds
					r.Get("/vital-thresholds", s.ThresholdHandler.HandleGet)
					r.Put("/vital-thresholds", s.ThresholdHandler.HandleSet)

					// Emergency
					r.Get("/emergency-card", s.EmergencyHandler.HandleGetEmergencyCard)
					r.Post("/emergency-access", s.EmergencyHandler.HandleConfigureEmergencyAccess)
					r.Get("/emergency-access", s.EmergencyHandler.HandleGetEmergencyAccessConfig)
					r.Delete("/emergency-access", s.EmergencyHandler.HandleDeleteEmergencyAccess)

					// Activity Log
					r.Get("/activity", s.ActivityHandler.HandleList)

					// Export
					r.Get("/export/fhir", s.ExportHandler.HandleExportFHIR)
					r.Post("/import/fhir", s.ExportHandler.HandleImportFHIR)
					r.Get("/export/ics", s.ExportHandler.HandleExportICS)
					r.Get("/export/pdf", s.PDFHandler.HandleDoctorReport)

					// Temporary doctor shares
					r.Post("/share", s.DoctorShareHandler.HandleCreateShare)
					r.Get("/shares", s.DoctorShareHandler.HandleListShares)
					r.Delete("/share/{shareID}", s.DoctorShareHandler.HandleRevokeShare)
				})
			})

			// Families
			r.Route("/families", func(r chi.Router) {
				r.Get("/", s.FamilyHandler.HandleList)
				r.Post("/", s.FamilyHandler.HandleCreate)
				r.Route("/{familyID}", func(r chi.Router) {
					r.Get("/", s.FamilyHandler.HandleGet)
					r.Patch("/", s.FamilyHandler.HandleUpdate)
					r.Get("/members", s.FamilyHandler.HandleGetMembers)
					r.Post("/invite", s.FamilyHandler.HandleInvite)
					r.Post("/accept", s.FamilyHandler.HandleAcceptInvite)
					r.Delete("/members/{memberID}", s.FamilyHandler.HandleRemoveMember)
					r.Post("/dissolve", s.FamilyHandler.HandleDissolve)
				})
			})

			// Notifications
			r.Route("/notifications", func(r chi.Router) {
				r.Get("/", s.NotificationHandler.HandleList)
				r.Post("/{notifID}/read", s.NotificationHandler.HandleMarkRead)
				r.Post("/read-all", s.NotificationHandler.HandleMarkAllRead)
				r.Delete("/{notifID}", s.NotificationHandler.HandleDelete)
				r.Get("/preferences", s.NotificationHandler.HandleGetPreferences)
				r.Patch("/preferences", s.NotificationHandler.HandleUpdatePreferences)
			})

			// Search
			r.Get("/search", s.SearchHandler.HandleSearch)

			// Reference ranges
			r.Get("/reference-ranges", s.ReferenceRangeHandler.HandleList)

			// Calendar feeds
			r.Route("/calendar/feeds", func(r chi.Router) {
				r.Get("/", s.CalendarHandler.HandleListFeeds)
				r.Post("/", s.CalendarHandler.HandleCreateFeed)
				r.Get("/{feedID}", s.CalendarHandler.HandleGetFeed)
				r.Patch("/{feedID}", s.CalendarHandler.HandleUpdateFeed)
				r.Delete("/{feedID}", s.CalendarHandler.HandleDeleteFeed)
			})

			// Export
			r.Route("/export", func(r chi.Router) {
				r.Post("/", s.ExportHandler.HandleExport)
				r.Post("/schedule", s.ScheduledExportHandler.HandleCreateSchedule)
				r.Get("/schedules", s.ScheduledExportHandler.HandleListSchedules)
				r.Delete("/schedules/{scheduleID}", s.ScheduledExportHandler.HandleDeleteSchedule)
			})

			// Emergency management (requires auth)
			r.Get("/emergency/pending", s.EmergencyHandler.HandleGetPendingRequests)
			r.Post("/emergency/approve/{requestID}", s.EmergencyHandler.HandleApproveRequest)
			r.Post("/emergency/deny/{requestID}", s.EmergencyHandler.HandleDenyRequest)

			// Admin
			r.Route("/admin", func(r chi.Router) {
				r.Use(middleware.RequireAdmin)

				r.Get("/users", s.AdminHandler.HandleListUsers)
				r.Post("/users/{userID}/disable", s.AdminHandler.HandleDisableUser)
				r.Post("/users/{userID}/enable", s.AdminHandler.HandleEnableUser)
				r.Delete("/users/{userID}", s.AdminHandler.HandleDeleteUser)
				r.Get("/users/{userID}/sessions", s.AdminHandler.HandleGetUserSessions)
				r.Delete("/users/{userID}/sessions", s.AdminHandler.HandleRevokeUserSessions)
				r.Patch("/users/{userID}/quota", s.AdminHandler.HandleSetQuota)
				r.Get("/storage", s.AdminHandler.HandleGetStorage)
				r.Get("/invites", s.InviteHandler.HandleListInvites)
				r.Post("/invites", s.InviteHandler.HandleCreateInvite)
				r.Delete("/invites/{token}", s.InviteHandler.HandleDeleteInvite)
				r.Get("/system", s.AdminHandler.HandleGetSystem)
				r.Get("/backups", s.AdminHandler.HandleGetBackups)
				r.Post("/backups/trigger", s.AdminHandler.HandleTriggerBackup)
				r.Get("/audit-log", s.AdminHandler.HandleGetAuditLog)
				r.Patch("/settings", s.AdminHandler.HandleGetSettings)

				// Admin legal/consent
				r.Get("/legal/documents", s.LegalHandler.HandleListDocuments)
				r.Post("/legal/documents", s.LegalHandler.HandleCreateDocument)
				r.Get("/legal/consent-records", s.LegalHandler.HandleListConsentRecords)
				r.Get("/legal/consent-records/{userID}", s.LegalHandler.HandleGetUserConsent)

				// Admin webhooks
				r.Route("/webhooks", func(r chi.Router) {
					r.Get("/", s.WebhookHandler.HandleList)
					r.Post("/", s.WebhookHandler.HandleCreate)
					r.Patch("/{webhookID}", s.WebhookHandler.HandleUpdate)
					r.Delete("/{webhookID}", s.WebhookHandler.HandleDelete)
					r.Get("/{webhookID}/logs", s.WebhookHandler.HandleGetLogs)
					r.Post("/{webhookID}/test", s.WebhookHandler.HandleTest)
				})
			})
		})
	})

	// ICS calendar feed — no auth header, token-based
	s.Router.Get("/cal/{token}.ics", s.CalendarHandler.HandleICSFeed)

	// Emergency access request — no auth, token-based
	s.Router.Post("/api/v1/emergency/request/{token}", s.EmergencyHandler.HandleRequestEmergencyAccess)

	// Temporary doctor share data endpoint — no auth, fragment-based key
	s.Router.Get("/api/v1/share/{shareID}", s.DoctorShareHandler.HandleGetShare)
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
