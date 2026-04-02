package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/documents"
)

type DocumentRepo struct {
	db *pgxpool.Pool
}

func NewDocumentRepo(db *pgxpool.Pool) *DocumentRepo {
	return &DocumentRepo{db: db}
}

func (r *DocumentRepo) Create(ctx context.Context, d *documents.Document) error {
	if d.ID == uuid.Nil {
		d.ID = uuid.New()
	}
	now := time.Now().UTC()
	d.CreatedAt = now
	d.UpdatedAt = now

	query := `
		INSERT INTO documents (
			id, profile_id, filename_enc, mime_type, file_size_bytes,
			storage_path, category, tags, ocr_text_enc, uploaded_by,
			created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`

	_, err := r.db.Exec(ctx, query,
		d.ID, d.ProfileID, d.FilenameEnc, d.MimeType, d.FileSizeBytes,
		d.StoragePath, d.Category, d.Tags, d.OCRTextEnc, d.UploadedBy,
		d.CreatedAt, d.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert document: %w", err)
	}
	return nil
}

func (r *DocumentRepo) GetByID(ctx context.Context, id uuid.UUID) (*documents.Document, error) {
	query := `
		SELECT id, profile_id, filename_enc, mime_type, file_size_bytes,
			storage_path, category, tags, ocr_text_enc, uploaded_by,
			created_at, updated_at, deleted_at
		FROM documents WHERE id = $1 AND deleted_at IS NULL`

	return r.scanDocument(r.db.QueryRow(ctx, query, id))
}

func (r *DocumentRepo) List(ctx context.Context, filter documents.ListFilter) ([]documents.Document, int, error) {
	countQuery := "SELECT COUNT(*) FROM documents WHERE profile_id = $1 AND deleted_at IS NULL"
	args := []interface{}{filter.ProfileID}
	argIdx := 2

	if filter.Category != nil {
		countQuery += fmt.Sprintf(" AND category = $%d", argIdx)
		args = append(args, *filter.Category)
		argIdx++
	}

	var total int
	if err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count documents: %w", err)
	}

	query := `
		SELECT id, profile_id, filename_enc, mime_type, file_size_bytes,
			storage_path, category, tags, ocr_text_enc, uploaded_by,
			created_at, updated_at, deleted_at
		FROM documents WHERE profile_id = $1 AND deleted_at IS NULL`

	listArgs := []interface{}{filter.ProfileID}
	listIdx := 2

	if filter.Category != nil {
		query += fmt.Sprintf(" AND category = $%d", listIdx)
		listArgs = append(listArgs, *filter.Category)
		listIdx++
	}

	query += " ORDER BY created_at DESC"

	if filter.Limit > 0 {
		query += fmt.Sprintf(" LIMIT $%d", listIdx)
		listArgs = append(listArgs, filter.Limit)
		listIdx++
	}
	if filter.Offset > 0 {
		query += fmt.Sprintf(" OFFSET $%d", listIdx)
		listArgs = append(listArgs, filter.Offset)
	}

	rows, err := r.db.Query(ctx, query, listArgs...)
	if err != nil {
		return nil, 0, fmt.Errorf("query documents: %w", err)
	}
	defer rows.Close()

	var result []documents.Document
	for rows.Next() {
		d, err := r.scanDocumentRow(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, *d)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate rows: %w", err)
	}

	return result, total, nil
}

func (r *DocumentRepo) Update(ctx context.Context, d *documents.Document) error {
	d.UpdatedAt = time.Now().UTC()

	query := `
		UPDATE documents SET
			filename_enc = $2, mime_type = $3, category = $4,
			tags = $5, ocr_text_enc = $6, updated_at = $7
		WHERE id = $1 AND deleted_at IS NULL`

	_, err := r.db.Exec(ctx, query,
		d.ID, d.FilenameEnc, d.MimeType, d.Category,
		d.Tags, d.OCRTextEnc, d.UpdatedAt,
	)
	return err
}

func (r *DocumentRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE documents SET deleted_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		id, time.Now().UTC(),
	)
	return err
}

func (r *DocumentRepo) scanDocument(row pgx.Row) (*documents.Document, error) {
	var d documents.Document
	err := row.Scan(
		&d.ID, &d.ProfileID, &d.FilenameEnc, &d.MimeType, &d.FileSizeBytes,
		&d.StoragePath, &d.Category, &d.Tags, &d.OCRTextEnc, &d.UploadedBy,
		&d.CreatedAt, &d.UpdatedAt, &d.DeletedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan document: %w", err)
	}
	return &d, nil
}

func (r *DocumentRepo) scanDocumentRow(rows pgx.Rows) (*documents.Document, error) {
	var d documents.Document
	err := rows.Scan(
		&d.ID, &d.ProfileID, &d.FilenameEnc, &d.MimeType, &d.FileSizeBytes,
		&d.StoragePath, &d.Category, &d.Tags, &d.OCRTextEnc, &d.UploadedBy,
		&d.CreatedAt, &d.UpdatedAt, &d.DeletedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("scan document row: %w", err)
	}
	return &d, nil
}
