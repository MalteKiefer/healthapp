package documents

import (
	"time"

	"github.com/google/uuid"
)

// Category enumerates the kinds of health documents.
type Category string

const (
	CategoryLabResult        Category = "lab_result"
	CategoryImaging          Category = "imaging"
	CategoryPrescription     Category = "prescription"
	CategoryReferral         Category = "referral"
	CategoryVaccinationRecord Category = "vaccination_record"
	CategoryDischargeSummary Category = "discharge_summary"
	CategoryReport           Category = "report"
	CategoryLegal            Category = "legal"
	CategoryOther            Category = "other"
)

// Document represents an uploaded health document with encrypted metadata.
type Document struct {
	ID            uuid.UUID  `json:"id"`
	ProfileID     uuid.UUID  `json:"profile_id"`
	FilenameEnc   string     `json:"filename_enc"`
	MimeType      string     `json:"mime_type"`
	FileSizeBytes int64      `json:"file_size_bytes"`
	StoragePath   string     `json:"-"`
	Category      Category   `json:"category"`
	Tags          []string   `json:"tags,omitempty"`
	OCRTextEnc    *string    `json:"ocr_text_enc,omitempty"`
	UploadedBy    uuid.UUID  `json:"uploaded_by"`
	EncryptedAt   *time.Time `json:"encrypted_at,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
	DeletedAt     *time.Time `json:"-"`
}

// ListFilter defines query parameters for listing documents.
type ListFilter struct {
	ProfileID uuid.UUID
	Category  *Category
	Limit     int
	Offset    int
}
