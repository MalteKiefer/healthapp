package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/profiles"
)

// ProfileRepo implements profiles.Repository backed by PostgreSQL.
type ProfileRepo struct {
	db *pgxpool.Pool
}

func NewProfileRepo(db *pgxpool.Pool) *ProfileRepo {
	return &ProfileRepo{db: db}
}

func (r *ProfileRepo) Create(ctx context.Context, p *profiles.Profile) error {
	query := `
		INSERT INTO profiles (
			id, owner_user_id, display_name, date_of_birth, biological_sex,
			blood_type, rhesus_factor, avatar_color, avatar_image_enc,
			archived_at, onboarding_completed_at, rotation_state,
			rotation_started_at, rotation_progress, created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)`

	now := time.Now().UTC()
	if p.ID == uuid.Nil {
		p.ID = uuid.New()
	}
	p.CreatedAt = now
	p.UpdatedAt = now

	if p.RotationState == "" {
		p.RotationState = "idle"
	}
	if p.BiologicalSex == "" {
		p.BiologicalSex = "unspecified"
	}

	_, err := r.db.Exec(ctx, query,
		p.ID, p.OwnerUserID, p.DisplayName, p.DateOfBirth, p.BiologicalSex,
		p.BloodType, p.RhesusFactor, p.AvatarColor, p.AvatarImageEnc,
		p.ArchivedAt, p.OnboardingCompletedAt, p.RotationState,
		p.RotationStartedAt, p.RotationProgress, p.CreatedAt, p.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert profile: %w", err)
	}
	return nil
}

func (r *ProfileRepo) GetByID(ctx context.Context, id uuid.UUID) (*profiles.Profile, error) {
	query := `
		SELECT id, owner_user_id, display_name, date_of_birth, biological_sex,
		       blood_type, rhesus_factor, avatar_color, avatar_image_enc,
		       archived_at, onboarding_completed_at, rotation_state,
		       rotation_started_at, rotation_progress, created_at, updated_at
		FROM profiles WHERE id = $1`

	var p profiles.Profile
	err := r.db.QueryRow(ctx, query, id).Scan(
		&p.ID, &p.OwnerUserID, &p.DisplayName, &p.DateOfBirth, &p.BiologicalSex,
		&p.BloodType, &p.RhesusFactor, &p.AvatarColor, &p.AvatarImageEnc,
		&p.ArchivedAt, &p.OnboardingCompletedAt, &p.RotationState,
		&p.RotationStartedAt, &p.RotationProgress, &p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan profile: %w", err)
	}
	return &p, nil
}

func (r *ProfileRepo) GetByOwnerID(ctx context.Context, ownerUserID uuid.UUID) ([]profiles.Profile, error) {
	query := `
		SELECT id, owner_user_id, display_name, date_of_birth, biological_sex,
		       blood_type, rhesus_factor, avatar_color, avatar_image_enc,
		       archived_at, onboarding_completed_at, rotation_state,
		       rotation_started_at, rotation_progress, created_at, updated_at
		FROM profiles WHERE owner_user_id = $1
		ORDER BY created_at ASC`

	rows, err := r.db.Query(ctx, query, ownerUserID)
	if err != nil {
		return nil, fmt.Errorf("query profiles by owner: %w", err)
	}
	defer rows.Close()

	return scanProfiles(rows)
}

func (r *ProfileRepo) GetAccessibleByUserID(ctx context.Context, userID uuid.UUID) ([]profiles.Profile, error) {
	query := `
		SELECT DISTINCT p.id, p.owner_user_id, p.display_name, p.date_of_birth, p.biological_sex,
		       p.blood_type, p.rhesus_factor, p.avatar_color, p.avatar_image_enc,
		       p.archived_at, p.onboarding_completed_at, p.rotation_state,
		       p.rotation_started_at, p.rotation_progress, p.created_at, p.updated_at
		FROM profiles p
		LEFT JOIN profile_key_grants pkg ON p.id = pkg.profile_id
		    AND pkg.grantee_user_id = $1
		    AND pkg.revoked_at IS NULL
		WHERE p.owner_user_id = $1
		   OR pkg.id IS NOT NULL
		ORDER BY p.created_at ASC`

	rows, err := r.db.Query(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("query accessible profiles: %w", err)
	}
	defer rows.Close()

	return scanProfiles(rows)
}

func (r *ProfileRepo) Update(ctx context.Context, p *profiles.Profile) error {
	p.UpdatedAt = time.Now().UTC()
	query := `
		UPDATE profiles SET
			display_name = $2, date_of_birth = $3, biological_sex = $4,
			blood_type = $5, rhesus_factor = $6, avatar_color = $7,
			avatar_image_enc = $8, onboarding_completed_at = $9,
			rotation_state = $10, rotation_started_at = $11,
			rotation_progress = $12, updated_at = $13
		WHERE id = $1`

	_, err := r.db.Exec(ctx, query,
		p.ID, p.DisplayName, p.DateOfBirth, p.BiologicalSex,
		p.BloodType, p.RhesusFactor, p.AvatarColor,
		p.AvatarImageEnc, p.OnboardingCompletedAt,
		p.RotationState, p.RotationStartedAt,
		p.RotationProgress, p.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("update profile: %w", err)
	}
	return nil
}

func (r *ProfileRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "DELETE FROM profiles WHERE id = $1", id)
	if err != nil {
		return fmt.Errorf("delete profile: %w", err)
	}
	return nil
}

func (r *ProfileRepo) Archive(ctx context.Context, id uuid.UUID) error {
	now := time.Now().UTC()
	_, err := r.db.Exec(ctx,
		"UPDATE profiles SET archived_at = $2, updated_at = $3 WHERE id = $1",
		id, now, now,
	)
	if err != nil {
		return fmt.Errorf("archive profile: %w", err)
	}
	return nil
}

func (r *ProfileRepo) Unarchive(ctx context.Context, id uuid.UUID) error {
	now := time.Now().UTC()
	_, err := r.db.Exec(ctx,
		"UPDATE profiles SET archived_at = NULL, updated_at = $2 WHERE id = $1",
		id, now,
	)
	if err != nil {
		return fmt.Errorf("unarchive profile: %w", err)
	}
	return nil
}

// ── Key Grants ──────────────────────────────────────────────────────

func (r *ProfileRepo) CreateKeyGrant(ctx context.Context, g *profiles.KeyGrant) error {
	query := `
		INSERT INTO profile_key_grants (
			id, profile_id, grantee_user_id, encrypted_key,
			grant_signature, granted_by_user_id, granted_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7)`

	if g.ID == uuid.Nil {
		g.ID = uuid.New()
	}
	if g.GrantedAt.IsZero() {
		g.GrantedAt = time.Now().UTC()
	}

	_, err := r.db.Exec(ctx, query,
		g.ID, g.ProfileID, g.GranteeUserID, g.EncryptedKey,
		g.GrantSignature, g.GrantedByUserID, g.GrantedAt,
	)
	if err != nil {
		return fmt.Errorf("insert key grant: %w", err)
	}
	return nil
}

func (r *ProfileRepo) RevokeKeyGrant(ctx context.Context, profileID, granteeUserID uuid.UUID) error {
	now := time.Now().UTC()
	_, err := r.db.Exec(ctx,
		"UPDATE profile_key_grants SET revoked_at = $3 WHERE profile_id = $1 AND grantee_user_id = $2 AND revoked_at IS NULL",
		profileID, granteeUserID, now,
	)
	if err != nil {
		return fmt.Errorf("revoke key grant: %w", err)
	}
	return nil
}

func (r *ProfileRepo) GetKeyGrantsForProfile(ctx context.Context, profileID uuid.UUID) ([]profiles.KeyGrant, error) {
	query := `
		SELECT id, profile_id, grantee_user_id, encrypted_key,
		       grant_signature, granted_by_user_id, granted_at, revoked_at
		FROM profile_key_grants
		WHERE profile_id = $1 AND revoked_at IS NULL
		ORDER BY granted_at ASC`

	rows, err := r.db.Query(ctx, query, profileID)
	if err != nil {
		return nil, fmt.Errorf("query key grants: %w", err)
	}
	defer rows.Close()

	var grants []profiles.KeyGrant
	for rows.Next() {
		var g profiles.KeyGrant
		if err := rows.Scan(
			&g.ID, &g.ProfileID, &g.GranteeUserID, &g.EncryptedKey,
			&g.GrantSignature, &g.GrantedByUserID, &g.GrantedAt, &g.RevokedAt,
		); err != nil {
			return nil, fmt.Errorf("scan key grant: %w", err)
		}
		grants = append(grants, g)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}
	return grants, nil
}

func (r *ProfileRepo) HasAccess(ctx context.Context, profileID, userID uuid.UUID) (bool, error) {
	query := `
		SELECT EXISTS (
			SELECT 1 FROM profiles WHERE id = $1 AND owner_user_id = $2
			UNION ALL
			SELECT 1 FROM profile_key_grants
			WHERE profile_id = $1 AND grantee_user_id = $2 AND revoked_at IS NULL
		)`

	var exists bool
	err := r.db.QueryRow(ctx, query, profileID, userID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check access: %w", err)
	}
	return exists, nil
}

// ── Helpers ─────────────────────────────────────────────────────────

func scanProfiles(rows pgx.Rows) ([]profiles.Profile, error) {
	var result []profiles.Profile
	for rows.Next() {
		var p profiles.Profile
		if err := rows.Scan(
			&p.ID, &p.OwnerUserID, &p.DisplayName, &p.DateOfBirth, &p.BiologicalSex,
			&p.BloodType, &p.RhesusFactor, &p.AvatarColor, &p.AvatarImageEnc,
			&p.ArchivedAt, &p.OnboardingCompletedAt, &p.RotationState,
			&p.RotationStartedAt, &p.RotationProgress, &p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan profile: %w", err)
		}
		result = append(result, p)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}
	return result, nil
}
