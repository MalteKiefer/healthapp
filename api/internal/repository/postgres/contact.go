package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/contacts"
)

type ContactRepo struct{ db *pgxpool.Pool }

func NewContactRepo(db *pgxpool.Pool) *ContactRepo { return &ContactRepo{db: db} }

const contactColumns = `id, profile_id, contact_type, name, specialty, facility, phone, email,
	street, postal_code, city, country, latitude, longitude, address, notes,
	is_emergency_contact, created_at, updated_at, deleted_at`

func scanContact(row pgx.Row) (*contacts.Contact, error) {
	var c contacts.Contact
	err := row.Scan(
		&c.ID, &c.ProfileID, &c.ContactType, &c.Name, &c.Specialty, &c.Facility, &c.Phone, &c.Email,
		&c.Street, &c.PostalCode, &c.City, &c.Country, &c.Latitude, &c.Longitude, &c.Address, &c.Notes,
		&c.IsEmergencyContact, &c.CreatedAt, &c.UpdatedAt, &c.DeletedAt,
	)
	return &c, err
}

func scanContacts(rows pgx.Rows) ([]contacts.Contact, error) {
	var result []contacts.Contact
	for rows.Next() {
		var c contacts.Contact
		if err := rows.Scan(
			&c.ID, &c.ProfileID, &c.ContactType, &c.Name, &c.Specialty, &c.Facility, &c.Phone, &c.Email,
			&c.Street, &c.PostalCode, &c.City, &c.Country, &c.Latitude, &c.Longitude, &c.Address, &c.Notes,
			&c.IsEmergencyContact, &c.CreatedAt, &c.UpdatedAt, &c.DeletedAt,
		); err != nil {
			return nil, fmt.Errorf("scan contact row: %w", err)
		}
		result = append(result, c)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}
	return result, nil
}

func (r *ContactRepo) Create(ctx context.Context, c *contacts.Contact) error {
	if c.ID == uuid.Nil {
		c.ID = uuid.New()
	}
	now := time.Now().UTC()
	c.CreatedAt = now
	c.UpdatedAt = now
	c.ComputeAddress()

	_, err := r.db.Exec(ctx, `
		INSERT INTO medical_contacts (id, profile_id, contact_type, name, specialty, facility, phone, email,
			street, postal_code, city, country, latitude, longitude, address, notes,
			is_emergency_contact, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19)`,
		c.ID, c.ProfileID, c.ContactType, c.Name, c.Specialty, c.Facility, c.Phone, c.Email,
		c.Street, c.PostalCode, c.City, c.Country, c.Latitude, c.Longitude, c.Address, c.Notes,
		c.IsEmergencyContact, c.CreatedAt, c.UpdatedAt)
	if err != nil {
		return fmt.Errorf("create contact: %w", err)
	}
	return nil
}

func (r *ContactRepo) GetByID(ctx context.Context, id uuid.UUID) (*contacts.Contact, error) {
	c, err := scanContact(r.db.QueryRow(ctx,
		`SELECT `+contactColumns+` FROM medical_contacts WHERE id = $1 AND deleted_at IS NULL`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan contact: %w", err)
	}
	return c, nil
}

func (r *ContactRepo) List(ctx context.Context, profileID uuid.UUID) ([]contacts.Contact, error) {
	rows, err := r.db.Query(ctx,
		`SELECT `+contactColumns+` FROM medical_contacts WHERE profile_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC`, profileID)
	if err != nil {
		return nil, fmt.Errorf("query contacts: %w", err)
	}
	defer rows.Close()
	return scanContacts(rows)
}

func (r *ContactRepo) Update(ctx context.Context, c *contacts.Contact) error {
	c.UpdatedAt = time.Now().UTC()
	c.ComputeAddress()
	_, err := r.db.Exec(ctx, `
		UPDATE medical_contacts SET contact_type=$2, name=$3, specialty=$4, facility=$5, phone=$6, email=$7,
			street=$8, postal_code=$9, city=$10, country=$11, latitude=$12, longitude=$13, address=$14, notes=$15,
			is_emergency_contact=$16, updated_at=$17
		WHERE id=$1 AND deleted_at IS NULL`,
		c.ID, c.ContactType, c.Name, c.Specialty, c.Facility, c.Phone, c.Email,
		c.Street, c.PostalCode, c.City, c.Country, c.Latitude, c.Longitude, c.Address, c.Notes,
		c.IsEmergencyContact, c.UpdatedAt)
	if err != nil {
		return fmt.Errorf("update contact: %w", err)
	}
	return nil
}

func (r *ContactRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "UPDATE medical_contacts SET deleted_at=$2 WHERE id=$1 AND deleted_at IS NULL", id, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("soft delete contact: %w", err)
	}
	return nil
}
