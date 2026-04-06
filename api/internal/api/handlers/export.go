package handlers

import (
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// ExportHandler handles data export and import endpoints.
type ExportHandler struct {
	db     *pgxpool.Pool
	logger *zap.Logger
}

func NewExportHandler(db *pgxpool.Pool, logger *zap.Logger) *ExportHandler {
	return &ExportHandler{db: db, logger: logger}
}

// HandleExportFHIR is deprecated — FHIR export is now generated client-side.
func (h *ExportHandler) HandleExportFHIR(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{
		"error":   "endpoint_removed",
		"message": "This endpoint has been removed. Use client-side rendering instead.",
	})
}

// HandleImportFHIR is a stub for FHIR import.
// POST /profiles/{profileID}/import/fhir
func (h *ExportHandler) HandleImportFHIR(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, errorResponse("not_implemented"))
}

// HandleExportICS is a stub for ICS calendar export.
// GET /profiles/{profileID}/export/ics
func (h *ExportHandler) HandleExportICS(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, errorResponse("not_implemented"))
}

// HandleExport is a stub for generic export.
// POST /export
func (h *ExportHandler) HandleExport(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, errorResponse("not_implemented"))
}

// HandleScheduleExport is a stub for scheduled export.
// POST /export/schedule
func (h *ExportHandler) HandleScheduleExport(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, errorResponse("not_implemented"))
}
