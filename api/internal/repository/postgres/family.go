package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/family"
)

// FamilyRepo implements family.Repository backed by PostgreSQL.
type FamilyRepo struct {
	db *pgxpool.Pool
}

func NewFamilyRepo(db *pgxpool.Pool) *FamilyRepo {
	return &FamilyRepo{db: db}
}

func (r *FamilyRepo) Create(ctx context.Context, f *family.Family) error {
	if f.ID == uuid.Nil {
		f.ID = uuid.New()
	}
	now := time.Now().UTC()
	f.CreatedAt = now
	f.UpdatedAt = now

	query := `
		INSERT INTO families (id, name, created_by, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5)`

	_, err := r.db.Exec(ctx, query,
		f.ID, f.Name, f.CreatedBy, f.CreatedAt, f.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert family: %w", err)
	}
	return nil
}

func (r *FamilyRepo) GetByID(ctx context.Context, id uuid.UUID) (*family.Family, error) {
	query := `
		SELECT id, name, created_by, dissolved_at, created_at, updated_at
		FROM families WHERE id = $1`

	var f family.Family
	err := r.db.QueryRow(ctx, query, id).Scan(
		&f.ID, &f.Name, &f.CreatedBy, &f.DissolvedAt, &f.CreatedAt, &f.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan family: %w", err)
	}
	return &f, nil
}

func (r *FamilyRepo) ListByUserID(ctx context.Context, userID uuid.UUID) ([]family.Family, error) {
	query := `
		SELECT f.id, f.name, f.created_by, f.dissolved_at, f.created_at, f.updated_at
		FROM families f
		JOIN family_memberships fm ON fm.family_id = f.id
		WHERE fm.user_id = $1 AND fm.left_at IS NULL AND f.dissolved_at IS NULL
		ORDER BY f.created_at DESC`

	rows, err := r.db.Query(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("query families: %w", err)
	}
	defer rows.Close()

	var families []family.Family
	for rows.Next() {
		var f family.Family
		if err := rows.Scan(
			&f.ID, &f.Name, &f.CreatedBy, &f.DissolvedAt, &f.CreatedAt, &f.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan family row: %w", err)
		}
		families = append(families, f)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}
	return families, nil
}

func (r *FamilyRepo) Update(ctx context.Context, f *family.Family) error {
	f.UpdatedAt = time.Now().UTC()

	query := `
		UPDATE families SET name = $2, updated_at = $3
		WHERE id = $1 AND dissolved_at IS NULL`

	_, err := r.db.Exec(ctx, query, f.ID, f.Name, f.UpdatedAt)
	if err != nil {
		return fmt.Errorf("update family: %w", err)
	}
	return nil
}

func (r *FamilyRepo) Dissolve(ctx context.Context, id uuid.UUID) error {
	now := time.Now().UTC()
	_, err := r.db.Exec(ctx,
		"UPDATE families SET dissolved_at = $2, updated_at = $2 WHERE id = $1 AND dissolved_at IS NULL",
		id, now,
	)
	if err != nil {
		return fmt.Errorf("dissolve family: %w", err)
	}
	return nil
}

// ── Memberships ─────────────────────────────────────────────────────

func (r *FamilyRepo) AddMember(ctx context.Context, m *family.FamilyMembership) error {
	if m.ID == uuid.Nil {
		m.ID = uuid.New()
	}
	m.JoinedAt = time.Now().UTC()

	query := `
		INSERT INTO family_memberships (id, user_id, family_id, role, joined_at)
		VALUES ($1, $2, $3, $4, $5)`

	_, err := r.db.Exec(ctx, query,
		m.ID, m.UserID, m.FamilyID, m.Role, m.JoinedAt,
	)
	if err != nil {
		return fmt.Errorf("insert membership: %w", err)
	}
	return nil
}

func (r *FamilyRepo) RemoveMember(ctx context.Context, familyID, userID uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE family_memberships SET left_at = $3 WHERE family_id = $1 AND user_id = $2 AND left_at IS NULL",
		familyID, userID, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("remove member: %w", err)
	}
	return nil
}

func (r *FamilyRepo) GetMemberships(ctx context.Context, familyID uuid.UUID) ([]family.FamilyMembership, error) {
	query := `
		SELECT id, user_id, family_id, role, joined_at, left_at
		FROM family_memberships
		WHERE family_id = $1 AND left_at IS NULL
		ORDER BY joined_at ASC`

	rows, err := r.db.Query(ctx, query, familyID)
	if err != nil {
		return nil, fmt.Errorf("query memberships: %w", err)
	}
	defer rows.Close()

	var memberships []family.FamilyMembership
	for rows.Next() {
		var m family.FamilyMembership
		if err := rows.Scan(
			&m.ID, &m.UserID, &m.FamilyID, &m.Role, &m.JoinedAt, &m.LeftAt,
		); err != nil {
			return nil, fmt.Errorf("scan membership: %w", err)
		}
		memberships = append(memberships, m)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}
	return memberships, nil
}

// ── Invites ─────────────────────────────────────────────────────────

func (r *FamilyRepo) CreateInvite(ctx context.Context, inv *family.FamilyInvite) error {
	if inv.ID == uuid.Nil {
		inv.ID = uuid.New()
	}
	inv.CreatedAt = time.Now().UTC()

	query := `
		INSERT INTO family_invites (id, family_id, token, created_by, expires_at, created_at)
		VALUES ($1, $2, $3, $4, $5, $6)`

	_, err := r.db.Exec(ctx, query,
		inv.ID, inv.FamilyID, inv.Token, inv.CreatedBy, inv.ExpiresAt, inv.CreatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert invite: %w", err)
	}
	return nil
}

func (r *FamilyRepo) GetInviteByToken(ctx context.Context, token string) (*family.FamilyInvite, error) {
	query := `
		SELECT id, family_id, token, created_by, expires_at, used_at, created_at
		FROM family_invites WHERE token = $1`

	var inv family.FamilyInvite
	err := r.db.QueryRow(ctx, query, token).Scan(
		&inv.ID, &inv.FamilyID, &inv.Token, &inv.CreatedBy, &inv.ExpiresAt, &inv.UsedAt, &inv.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan invite: %w", err)
	}
	return &inv, nil
}

func (r *FamilyRepo) UseInvite(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE family_invites SET used_at = $2 WHERE id = $1",
		id, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("use invite: %w", err)
	}
	return nil
}
