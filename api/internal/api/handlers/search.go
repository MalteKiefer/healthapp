package handlers

import (
	"fmt"
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

// HandleSearch performs a global full-text and fuzzy search across health data types.
// GET /search?q=...&types=...&profiles=...
func (h *SearchHandler) HandleSearch(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if q == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse("query_required"))
		return
	}

	// Parse requested types (default: all)
	requestedTypes := make(map[string]bool)
	if typesParam := r.URL.Query().Get("types"); typesParam != "" {
		for _, t := range strings.Split(typesParam, ",") {
			requestedTypes[strings.TrimSpace(t)] = true
		}
	}

	// Parse requested profile IDs (default: all accessible)
	var profileFilter []uuid.UUID
	if profilesParam := r.URL.Query().Get("profiles"); profilesParam != "" {
		for _, p := range strings.Split(profilesParam, ",") {
			pid, err := uuid.Parse(strings.TrimSpace(p))
			if err != nil {
				continue
			}
			profileFilter = append(profileFilter, pid)
		}
	}

	// Get all profile IDs the user has access to via profile_key_grants
	accessibleRows, err := h.db.Query(r.Context(),
		`SELECT DISTINCT profile_id FROM profile_key_grants WHERE grantee_user_id = $1`,
		claims.UserID,
	)
	if err != nil {
		h.logger.Error("query accessible profiles", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer accessibleRows.Close()

	accessibleSet := make(map[uuid.UUID]bool)
	for accessibleRows.Next() {
		var pid uuid.UUID
		if err := accessibleRows.Scan(&pid); err != nil {
			h.logger.Error("scan accessible profile", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		accessibleSet[pid] = true
	}
	if err := accessibleRows.Err(); err != nil {
		h.logger.Error("iterate accessible profiles", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Also include profiles owned by the user
	ownedRows, err := h.db.Query(r.Context(),
		`SELECT id FROM profiles WHERE owner_user_id = $1`,
		claims.UserID,
	)
	if err != nil {
		h.logger.Error("query owned profiles", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer ownedRows.Close()

	for ownedRows.Next() {
		var pid uuid.UUID
		if err := ownedRows.Scan(&pid); err != nil {
			h.logger.Error("scan owned profile", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
			return
		}
		accessibleSet[pid] = true
	}
	if err := ownedRows.Err(); err != nil {
		h.logger.Error("iterate owned profiles", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	// Determine which profiles to actually search
	var searchProfiles []uuid.UUID
	if len(profileFilter) > 0 {
		for _, pid := range profileFilter {
			if accessibleSet[pid] {
				searchProfiles = append(searchProfiles, pid)
			}
		}
	} else {
		for pid := range accessibleSet {
			searchProfiles = append(searchProfiles, pid)
		}
	}

	if len(searchProfiles) == 0 {
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"results": map[string][]searchResult{},
		})
		return
	}

	// Build profile ID placeholders for SQL
	profilePlaceholders := make([]string, len(searchProfiles))
	profileArgs := make([]interface{}, len(searchProfiles))
	for i, pid := range searchProfiles {
		profilePlaceholders[i] = fmt.Sprintf("$%d", i+1)
		profileArgs[i] = pid
	}
	profileInClause := strings.Join(profilePlaceholders, ", ")

	// Prepare tsquery from search term
	// Split words, sanitize, and join with & for AND matching
	words := strings.Fields(q)
	tsqueryParts := make([]string, 0, len(words))
	for _, w := range words {
		sanitized := sanitizeTsqueryWord(w)
		if sanitized != "" {
			tsqueryParts = append(tsqueryParts, sanitized+":*")
		}
	}
	if len(tsqueryParts) == 0 {
		// No valid search terms after sanitization
		writeJSON(w, http.StatusOK, map[string]interface{}{"results": map[string]interface{}{}})
		return
	}
	tsquery := strings.Join(tsqueryParts, " & ")

	results := make(map[string][]searchResult)

	for _, st := range searchableTypes {
		// Skip if type filtering is active and this type is not requested
		if len(requestedTypes) > 0 && !requestedTypes[st.typeName] {
			continue
		}

		subtitleExpr := "''"
		subtitleScan := true
		if st.extraColumn != "" {
			subtitleExpr = fmt.Sprintf("COALESCE(%s, '')", st.extraColumn)
		} else {
			subtitleScan = true
		}

		// Full-text search combined with trigram similarity for fuzzy matching.
		// The query uses UNION to get results from both methods, deduplicating by id.
		argOffset := len(searchProfiles)
		query := fmt.Sprintf(
			`SELECT DISTINCT ON (id) id, profile_id, %s AS name, %s AS subtitle, rank
			 FROM (
			   SELECT id, profile_id, %s, %s, ts_rank(to_tsvector('simple', %s), to_tsquery('simple', $%d)) AS rank
			   FROM %s
			   WHERE profile_id IN (%s)
			     AND to_tsvector('simple', %s) @@ to_tsquery('simple', $%d)
			     AND deleted_at IS NULL
			   UNION ALL
			   SELECT id, profile_id, %s, %s, similarity(%s, $%d)::float8 AS rank
			   FROM %s
			   WHERE profile_id IN (%s)
			     AND similarity(%s, $%d) > 0.1
			     AND deleted_at IS NULL
			 ) sub
			 ORDER BY id, rank DESC
			 LIMIT 20`,
			st.nameColumn, subtitleExpr,
			// FTS subquery
			st.nameColumn, st.extraColumn, st.nameColumn, argOffset+1,
			st.table, profileInClause,
			st.nameColumn, argOffset+1,
			// Trigram subquery
			st.nameColumn, st.extraColumn, st.nameColumn, argOffset+2,
			st.table, profileInClause,
			st.nameColumn, argOffset+2,
		)

		// For tables without an extra column, adjust the query
		if st.extraColumn == "" {
			query = fmt.Sprintf(
				`SELECT DISTINCT ON (id) id, profile_id, %s AS name, '' AS subtitle, rank
				 FROM (
				   SELECT id, profile_id, %s, ts_rank(to_tsvector('simple', %s), to_tsquery('simple', $%d)) AS rank
				   FROM %s
				   WHERE profile_id IN (%s)
				     AND to_tsvector('simple', %s) @@ to_tsquery('simple', $%d)
				     AND deleted_at IS NULL
				   UNION ALL
				   SELECT id, profile_id, %s, similarity(%s, $%d)::float8 AS rank
				   FROM %s
				   WHERE profile_id IN (%s)
				     AND similarity(%s, $%d) > 0.1
				     AND deleted_at IS NULL
				 ) sub
				 ORDER BY id, rank DESC
				 LIMIT 20`,
				st.nameColumn,
				// FTS subquery
				st.nameColumn, st.nameColumn, argOffset+1,
				st.table, profileInClause,
				st.nameColumn, argOffset+1,
				// Trigram subquery
				st.nameColumn, st.nameColumn, argOffset+2,
				st.table, profileInClause,
				st.nameColumn, argOffset+2,
			)
		}

		args := make([]interface{}, 0, len(profileArgs)+2)
		args = append(args, profileArgs...)
		args = append(args, tsquery)
		args = append(args, q)

		rows, err := h.db.Query(r.Context(), query, args...)
		if err != nil {
			h.logger.Error("search query failed",
				zap.String("type", st.typeName),
				zap.Error(err),
			)
			// Continue to other types rather than failing entirely
			continue
		}

		var typeResults []searchResult
		for rows.Next() {
			var sr searchResult
			if subtitleScan {
				if err := rows.Scan(&sr.ID, &sr.ProfileID, &sr.Name, &sr.Subtitle, &sr.Rank); err != nil {
					h.logger.Error("scan search result", zap.String("type", st.typeName), zap.Error(err))
					break
				}
			} else {
				if err := rows.Scan(&sr.ID, &sr.ProfileID, &sr.Name, &sr.Subtitle, &sr.Rank); err != nil {
					h.logger.Error("scan search result", zap.String("type", st.typeName), zap.Error(err))
					break
				}
			}
			sr.Type = st.typeName
			typeResults = append(typeResults, sr)
		}
		rows.Close()

		if typeResults != nil {
			results[st.typeName] = typeResults
		}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"results": results,
	})
}
