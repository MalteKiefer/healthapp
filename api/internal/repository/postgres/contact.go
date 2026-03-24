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

func (r *ContactRepo) Create(ctx context.Context, c *contacts.Contact) error {
	if c.ID == uuid.Nil {
		c.ID = uuid.New()
	}
	now := time.Now().UTC()
	c.CreatedAt = now
	c.UpdatedAt = now

	_, err := r.db.Exec(ctx, `
		INSERT INTO medical_contacts (id, profile_id, name, specialty, facility, phone, email, address, notes, is_emergency_contact, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
		c.ID, c.ProfileID, c.Name, c.Specialty, c.Facility, c.Phone, c.Email, c.Address, c.Notes, c.IsEmergencyContact, c.CreatedAt, c.UpdatedAt)
	return err
}

func (r *ContactRepo) GetByID(ctx context.Context, id uuid.UUID) (*contacts.Contact, error) {
	var c contacts.Contact
	err := r.db.QueryRow(ctx, `
		SELECT id, profile_id, name, specialty, facility, phone, email, address, notes, is_emergency_contact, created_at, updated_at, deleted_at
		FROM medical_contacts WHERE id = $1 AND deleted_at IS NULL`, id).Scan(
		&c.ID, &c.ProfileID, &c.Name, &c.Specialty, &c.Facility, &c.Phone, &c.Email, &c.Address, &c.Notes, &c.IsEmergencyContact, &c.CreatedAt, &c.UpdatedAt, &c.DeletedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan contact: %w", err)
	}
	return &c, nil
}

func (r *ContactRepo) List(ctx context.Context, profileID uuid.UUID) ([]contacts.Contact, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, profile_id, name, specialty, facility, phone, email, address, notes, is_emergency_contact, created_at, updated_at, deleted_at
		FROM medical_contacts WHERE profile_id = $1 AND deleted_at IS NULL ORDER BY name`, profileID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []contacts.Contact
	for rows.Next() {
		var c contacts.Contact
		if err := rows.Scan(&c.ID, &c.ProfileID, &c.Name, &c.Specialty, &c.Facility, &c.Phone, &c.Email, &c.Address, &c.Notes, &c.IsEmergencyContact, &c.CreatedAt, &c.UpdatedAt, &c.DeletedAt); err != nil {
			return nil, err
		}
		result = append(result, c)
	}
	return result, nil
}

func (r *ContactRepo) Update(ctx context.Context, c *contacts.Contact) error {
	c.UpdatedAt = time.Now().UTC()
	_, err := r.db.Exec(ctx, `
		UPDATE medical_contacts SET name=$2, specialty=$3, facility=$4, phone=$5, email=$6, address=$7, notes=$8, is_emergency_contact=$9, updated_at=$10
		WHERE id=$1 AND deleted_at IS NULL`,
		c.ID, c.Name, c.Specialty, c.Facility, c.Phone, c.Email, c.Address, c.Notes, c.IsEmergencyContact, c.UpdatedAt)
	return err
}

func (r *ContactRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "UPDATE medical_contacts SET deleted_at=$2 WHERE id=$1 AND deleted_at IS NULL", id, time.Now().UTC())
	return err
}
