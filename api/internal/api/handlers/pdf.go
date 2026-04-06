package handlers

import (
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/profiles"
)

// PDFHandler generates doctor-ready PDF reports.
type PDFHandler struct {
	db          *pgxpool.Pool
	profileRepo profiles.Repository
	logger      *zap.Logger
}

// NewPDFHandler creates a new PDFHandler.
func NewPDFHandler(db *pgxpool.Pool, pr profiles.Repository, logger *zap.Logger) *PDFHandler {
	return &PDFHandler{db: db, profileRepo: pr, logger: logger}
}

// HandleDoctorReport is deprecated — PDF reports are now generated client-side.
func (h *PDFHandler) HandleDoctorReport(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{
		"error":   "endpoint_removed",
		"message": "This endpoint has been removed. Use client-side rendering instead.",
	})
}
