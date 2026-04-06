package handlers

import (
	"net/http"
	"strings"
	"unicode"

	"github.com/google/uuid"
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

// searchResult represents a single search hit.
type searchResult struct {
	ID        uuid.UUID `json:"id"`
	ProfileID uuid.UUID `json:"profile_id"`
	Name      string    `json:"name"`
	Subtitle  string    `json:"subtitle,omitempty"`
	Type      string    `json:"type"`
	Rank      float64   `json:"rank"`
}

// searchableType defines how to search a specific table.
type searchableType struct {
	typeName    string
	table       string
	nameColumn  string
	extraColumn string // optional secondary column for subtitle
}

var searchableTypes = []searchableType{
	{typeName: "medications", table: "medications", nameColumn: "name", extraColumn: "dosage"},
	{typeName: "allergies", table: "allergies", nameColumn: "name", extraColumn: "severity"},
	{typeName: "diagnoses", table: "diagnoses", nameColumn: "name", extraColumn: "icd_code"},
	{typeName: "vaccinations", table: "vaccinations", nameColumn: "name", extraColumn: "manufacturer"},
	{typeName: "contacts", table: "emergency_contacts", nameColumn: "name", extraColumn: "relationship"},
	{typeName: "diary", table: "diary_entries", nameColumn: "title", extraColumn: ""},
}

// sanitizeTsqueryWord removes tsquery-special characters to prevent parsing errors.
// Only allows alphanumeric, hyphens, and dots.
func sanitizeTsqueryWord(word string) string {
	var buf strings.Builder
	for _, r := range word {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == '-' || r == '.' {
			buf.WriteRune(r)
		}
	}
	return buf.String()
}

// HandleSearch is deprecated — search now operates client-side on decrypted data.
func (h *SearchHandler) HandleSearch(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{
		"error":   "endpoint_removed",
		"message": "This endpoint has been removed. Use client-side rendering instead.",
	})
}
