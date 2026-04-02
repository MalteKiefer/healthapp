package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/domain/documents"
	"github.com/healthvault/healthvault/internal/domain/profiles"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// DocumentHandler handles health document endpoints.
type DocumentHandler struct {
	docRepo     documents.Repository
	profileRepo profiles.Repository
	uploadDir   string
	logger      *zap.Logger
}

func NewDocumentHandler(dr documents.Repository, pr profiles.Repository, uploadDir string, logger *zap.Logger) *DocumentHandler {
	return &DocumentHandler{docRepo: dr, profileRepo: pr, uploadDir: uploadDir, logger: logger}
}

// HandleList returns documents for a profile with optional filtering and pagination.
func (h *DocumentHandler) HandleList(w http.ResponseWriter, r *http.Request) {
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

	filter := documents.ListFilter{
		ProfileID: profileID,
		Limit:     50,
	}

	if v := r.URL.Query().Get("limit"); v != "" {
		if l, err := strconv.Atoi(v); err == nil && l > 0 && l <= 200 {
			filter.Limit = l
		}
	}
	if v := r.URL.Query().Get("offset"); v != "" {
		if o, err := strconv.Atoi(v); err == nil && o >= 0 {
			filter.Offset = o
		}
	}
	if v := r.URL.Query().Get("category"); v != "" {
		cat := documents.Category(v)
		filter.Category = &cat
	}

	items, total, err := h.docRepo.List(r.Context(), filter)
	if err != nil {
		h.logger.Error("list documents", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}

// HandleCreate handles multipart file upload and creates a document record.
func (h *DocumentHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
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

	// 32 MB max memory for multipart parsing
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_multipart"))
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("file_required"))
		return
	}
	defer file.Close()

	docID := uuid.New()

	// Build storage path: <uploadDir>/<profileID>/<docID>
	profileDir := filepath.Join(h.uploadDir, profileID.String())
	if err := os.MkdirAll(profileDir, 0o750); err != nil {
		h.logger.Error("create upload dir", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	storagePath := filepath.Join(profileDir, docID.String())
	dst, err := os.Create(storagePath)
	if err != nil {
		h.logger.Error("create file", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}
	defer dst.Close()

	written, err := io.Copy(dst, file)
	if err != nil {
		h.logger.Error("write file", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	d := documents.Document{
		ID:            docID,
		ProfileID:     profileID,
		FilenameEnc:   r.FormValue("filename_enc"),
		MimeType:      header.Header.Get("Content-Type"),
		FileSizeBytes: written,
		StoragePath:   storagePath,
		Category:      documents.Category(r.FormValue("category")),
		UploadedBy:    claims.UserID,
	}

	if v := r.FormValue("ocr_text_enc"); v != "" {
		d.OCRTextEnc = &v
	}

	// Parse tags from repeated form field or JSON-encoded string.
	if tags := r.Form["tags"]; len(tags) > 0 {
		d.Tags = tags
	} else if v := r.FormValue("tags_json"); v != "" {
		var tags []string
		if err := json.Unmarshal([]byte(v), &tags); err == nil {
			d.Tags = tags
		}
	}

	if d.FilenameEnc == "" {
		d.FilenameEnc = header.Filename
	}
	if d.MimeType == "" {
		d.MimeType = "application/octet-stream"
	}
	if d.Category == "" {
		d.Category = documents.CategoryOther
	}

	if err := h.docRepo.Create(r.Context(), &d); err != nil {
		h.logger.Error("create document", zap.Error(err))
		// Clean up the stored file on DB failure.
		os.Remove(storagePath)
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.Header().Set("Location", fmt.Sprintf("/api/v1/profiles/%s/documents/%s", profileID, d.ID))
	writeJSON(w, http.StatusCreated, d)
}

// HandleBulkUpload returns 501 as bulk document upload is not yet implemented.
func (h *DocumentHandler) HandleBulkUpload(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, map[string]string{
		"error":   "not_implemented",
		"message": "bulk document upload coming soon",
	})
}

// HandleSearch returns 501 as document search is not yet implemented.
func (h *DocumentHandler) HandleSearch(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, map[string]string{
		"error":   "not_implemented",
		"message": "document search coming soon",
	})
}

// HandleCreateOCRIndex returns 501 as OCR indexing is not yet implemented.
func (h *DocumentHandler) HandleCreateOCRIndex(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, map[string]string{
		"error":   "not_implemented",
		"message": "OCR indexing coming soon",
	})
}

// HandleDeleteOCRIndex returns 501 as OCR index deletion is not yet implemented.
func (h *DocumentHandler) HandleDeleteOCRIndex(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, map[string]string{
		"error":   "not_implemented",
		"message": "OCR index deletion coming soon",
	})
}

// HandleGet returns a single document's metadata.
func (h *DocumentHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
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

	docID, err := uuid.Parse(chi.URLParam(r, "documentID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_document_id"))
		return
	}

	d, err := h.docRepo.GetByID(r.Context(), docID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get document", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if d.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	writeJSON(w, http.StatusOK, d)
}

// HandleUpdate updates document metadata (not the file content).
func (h *DocumentHandler) HandleUpdate(w http.ResponseWriter, r *http.Request) {
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

	docID, err := uuid.Parse(chi.URLParam(r, "documentID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_document_id"))
		return
	}

	existing, err := h.docRepo.GetByID(r.Context(), docID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get document", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	// Decode patch -- only provided fields are updated.
	var patch struct {
		FilenameEnc *string            `json:"filename_enc,omitempty"`
		MimeType    *string            `json:"mime_type,omitempty"`
		Category    *documents.Category `json:"category,omitempty"`
		Tags        []string           `json:"tags,omitempty"`
		OCRTextEnc  *string            `json:"ocr_text_enc,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&patch); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_request"))
		return
	}

	if patch.FilenameEnc != nil {
		existing.FilenameEnc = *patch.FilenameEnc
	}
	if patch.MimeType != nil {
		existing.MimeType = *patch.MimeType
	}
	if patch.Category != nil {
		existing.Category = *patch.Category
	}
	if patch.Tags != nil {
		existing.Tags = patch.Tags
	}
	if patch.OCRTextEnc != nil {
		existing.OCRTextEnc = patch.OCRTextEnc
	}

	if err := h.docRepo.Update(r.Context(), existing); err != nil {
		h.logger.Error("update document", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, existing)
}

// HandleDelete soft-deletes a document.
func (h *DocumentHandler) HandleDelete(w http.ResponseWriter, r *http.Request) {
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

	docID, err := uuid.Parse(chi.URLParam(r, "documentID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_document_id"))
		return
	}

	existing, err := h.docRepo.GetByID(r.Context(), docID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get document", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if existing.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	if err := h.docRepo.SoftDelete(r.Context(), docID); err != nil {
		h.logger.Error("delete document", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleDownload streams the encrypted file content to the client.
func (h *DocumentHandler) HandleDownload(w http.ResponseWriter, r *http.Request) {
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

	docID, err := uuid.Parse(chi.URLParam(r, "documentID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_document_id"))
		return
	}

	d, err := h.docRepo.GetByID(r.Context(), docID)
	if err != nil {
		if errors.Is(err, postgres.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
			return
		}
		h.logger.Error("get document", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	if d.ProfileID != profileID {
		writeJSON(w, http.StatusNotFound, errorResponse("not_found"))
		return
	}

	f, err := os.Open(d.StoragePath)
	if err != nil {
		h.logger.Error("open file", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("file_unavailable"))
		return
	}
	defer f.Close()

	w.Header().Set("Content-Type", d.MimeType)
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, strings.ReplaceAll(d.FilenameEnc, `"`, `\"`)))
	w.Header().Set("Content-Length", strconv.FormatInt(d.FileSizeBytes, 10))
	io.Copy(w, f)
}
