package handlers

import (
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// SearchHandler handles global search endpoints.
type SearchHandler struct {
	db     *pgxpool.Pool
	logger *zap.Logger
}

func NewSearchHandler(db *pgxpool.Pool, logger *zap.Logger) *SearchHandler {
	return &SearchHandler{db: db, logger: logger}
}

// HandleSearch is deprecated — search now operates client-side on decrypted data.
func (h *SearchHandler) HandleSearch(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{
		"error":   "endpoint_removed",
		"message": "This endpoint has been removed. Use client-side rendering instead.",
	})
}
