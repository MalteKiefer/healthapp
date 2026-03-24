package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/user"
)

// UserRepo implements user.Repository backed by PostgreSQL.
type UserRepo struct {
	db *pgxpool.Pool
}

func NewUserRepo(db *pgxpool.Pool) *UserRepo {
	return &UserRepo{db: db}
}

var ErrNotFound = errors.New("not found")

func (r *UserRepo) Create(ctx context.Context, u *user.User) error {
	query := `
		INSERT INTO users (
			id, email, display_name, auth_hash, pek_salt, auth_salt,
			identity_pubkey, identity_privkey_enc, signing_pubkey, signing_privkey_enc,
			role, is_disabled, totp_enabled, created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`

	now := time.Now().UTC()
	if u.ID == uuid.Nil {
		u.ID = uuid.New()
	}
	u.CreatedAt = now
	u.UpdatedAt = now

	_, err := r.db.Exec(ctx, query,
		u.ID, u.Email, u.DisplayName, u.AuthHash, u.PEKSalt, u.AuthSalt,
		u.IdentityPubkey, u.IdentityPrivkeyEnc, u.SigningPubkey, u.SigningPrivkeyEnc,
		u.Role, u.IsDisabled, u.TOTPEnabled, u.CreatedAt, u.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert user: %w", err)
	}
	return nil
}

func (r *UserRepo) GetByID(ctx context.Context, id uuid.UUID) (*user.User, error) {
	return r.getUser(ctx, "SELECT * FROM users WHERE id = $1", id)
}

func (r *UserRepo) GetByEmail(ctx context.Context, email string) (*user.User, error) {
	return r.getUser(ctx, "SELECT * FROM users WHERE email = $1", email)
}

func (r *UserRepo) getUser(ctx context.Context, query string, arg interface{}) (*user.User, error) {
	row := r.db.QueryRow(ctx, query, arg)

	var u user.User
	err := row.Scan(
		&u.ID, &u.Email, &u.DisplayName, &u.AuthHash, &u.PEKSalt, &u.AuthSalt,
		&u.IdentityPubkey, &u.IdentityPrivkeyEnc, &u.SigningPubkey, &u.SigningPrivkeyEnc,
		&u.Role, &u.IsDisabled, &u.TOTPSecretEnc, &u.TOTPEnabled,
		&u.OnboardingCompletedAt, &u.CreatedAt, &u.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan user: %w", err)
	}
	return &u, nil
}

func (r *UserRepo) Update(ctx context.Context, u *user.User) error {
	u.UpdatedAt = time.Now().UTC()
	query := `
		UPDATE users SET
			display_name = $2, auth_hash = $3, identity_pubkey = $4,
			identity_privkey_enc = $5, signing_pubkey = $6, signing_privkey_enc = $7,
			totp_secret_enc = $8, totp_enabled = $9, onboarding_completed_at = $10,
			updated_at = $11
		WHERE id = $1`

	_, err := r.db.Exec(ctx, query,
		u.ID, u.DisplayName, u.AuthHash, u.IdentityPubkey,
		u.IdentityPrivkeyEnc, u.SigningPubkey, u.SigningPrivkeyEnc,
		u.TOTPSecretEnc, u.TOTPEnabled, u.OnboardingCompletedAt,
		u.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("update user: %w", err)
	}
	return nil
}

func (r *UserRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "DELETE FROM users WHERE id = $1", id)
	if err != nil {
		return fmt.Errorf("delete user: %w", err)
	}
	return nil
}

func (r *UserRepo) SetDisabled(ctx context.Context, id uuid.UUID, disabled bool) error {
	_, err := r.db.Exec(ctx,
		"UPDATE users SET is_disabled = $2, updated_at = $3 WHERE id = $1",
		id, disabled, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("set disabled: %w", err)
	}
	return nil
}

// ── Sessions ────────────────────────────────────────────────────────

func (r *UserRepo) CreateSession(ctx context.Context, s *user.Session) error {
	query := `
		INSERT INTO user_sessions (id, user_id, jti, device_hint, ip_address, created_at, last_active_at, expires_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`

	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	now := time.Now().UTC()
	s.CreatedAt = now
	s.LastActiveAt = now

	_, err := r.db.Exec(ctx, query,
		s.ID, s.UserID, s.JTI, s.DeviceHint, s.IPAddress,
		s.CreatedAt, s.LastActiveAt, s.ExpiresAt,
	)
	if err != nil {
		return fmt.Errorf("insert session: %w", err)
	}
	return nil
}

func (r *UserRepo) GetSessionsByUserID(ctx context.Context, userID uuid.UUID) ([]user.Session, error) {
	query := `
		SELECT id, user_id, jti, device_hint, ip_address, created_at, last_active_at, expires_at, revoked_at
		FROM user_sessions WHERE user_id = $1 AND revoked_at IS NULL
		ORDER BY last_active_at DESC`

	rows, err := r.db.Query(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("query sessions: %w", err)
	}
	defer rows.Close()

	var sessions []user.Session
	for rows.Next() {
		var s user.Session
		if err := rows.Scan(&s.ID, &s.UserID, &s.JTI, &s.DeviceHint, &s.IPAddress,
			&s.CreatedAt, &s.LastActiveAt, &s.ExpiresAt, &s.RevokedAt); err != nil {
			return nil, fmt.Errorf("scan session: %w", err)
		}
		sessions = append(sessions, s)
	}
	return sessions, nil
}

func (r *UserRepo) GetSessionByJTI(ctx context.Context, jti string) (*user.Session, error) {
	query := `
		SELECT id, user_id, jti, device_hint, ip_address, created_at, last_active_at, expires_at, revoked_at
		FROM user_sessions WHERE jti = $1`

	var s user.Session
	err := r.db.QueryRow(ctx, query, jti).Scan(
		&s.ID, &s.UserID, &s.JTI, &s.DeviceHint, &s.IPAddress,
		&s.CreatedAt, &s.LastActiveAt, &s.ExpiresAt, &s.RevokedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan session: %w", err)
	}
	return &s, nil
}

func (r *UserRepo) RevokeSession(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE user_sessions SET revoked_at = $2 WHERE id = $1",
		id, time.Now().UTC(),
	)
	return err
}

func (r *UserRepo) RevokeAllSessions(ctx context.Context, userID uuid.UUID, exceptID *uuid.UUID) error {
	if exceptID != nil {
		_, err := r.db.Exec(ctx,
			"UPDATE user_sessions SET revoked_at = $3 WHERE user_id = $1 AND id != $2 AND revoked_at IS NULL",
			userID, *exceptID, time.Now().UTC(),
		)
		return err
	}
	_, err := r.db.Exec(ctx,
		"UPDATE user_sessions SET revoked_at = $2 WHERE user_id = $1 AND revoked_at IS NULL",
		userID, time.Now().UTC(),
	)
	return err
}

func (r *UserRepo) UpdateSessionActivity(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE user_sessions SET last_active_at = $2 WHERE id = $1",
		id, time.Now().UTC(),
	)
	return err
}

// ── Recovery Codes ──────────────────────────────────────────────────

func (r *UserRepo) StoreRecoveryCodes(ctx context.Context, userID uuid.UUID, codeHashes []string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Delete existing codes
	if _, err := tx.Exec(ctx, "DELETE FROM user_recovery_codes WHERE user_id = $1", userID); err != nil {
		return fmt.Errorf("delete old codes: %w", err)
	}

	for _, hash := range codeHashes {
		_, err := tx.Exec(ctx,
			"INSERT INTO user_recovery_codes (user_id, code_hash) VALUES ($1, $2)",
			userID, hash,
		)
		if err != nil {
			return fmt.Errorf("insert recovery code: %w", err)
		}
	}

	return tx.Commit(ctx)
}

func (r *UserRepo) GetUnusedRecoveryCodes(ctx context.Context, userID uuid.UUID) ([]user.RecoveryCode, error) {
	rows, err := r.db.Query(ctx,
		"SELECT id, user_id, code_hash, used_at, created_at FROM user_recovery_codes WHERE user_id = $1 AND used_at IS NULL",
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("query recovery codes: %w", err)
	}
	defer rows.Close()

	var codes []user.RecoveryCode
	for rows.Next() {
		var c user.RecoveryCode
		if err := rows.Scan(&c.ID, &c.UserID, &c.CodeHash, &c.UsedAt, &c.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan recovery code: %w", err)
		}
		codes = append(codes, c)
	}
	return codes, nil
}

func (r *UserRepo) MarkRecoveryCodeUsed(ctx context.Context, codeID uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE user_recovery_codes SET used_at = $2 WHERE id = $1",
		codeID, time.Now().UTC(),
	)
	return err
}

func (r *UserRepo) DeleteRecoveryCodes(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.Exec(ctx, "DELETE FROM user_recovery_codes WHERE user_id = $1", userID)
	return err
}

// ── Preferences ─────────────────────────────────────────────────────

func (r *UserRepo) GetPreferences(ctx context.Context, userID uuid.UUID) (*user.Preferences, error) {
	var p user.Preferences
	err := r.db.QueryRow(ctx,
		`SELECT user_id, language, date_format, weight_unit, height_unit,
		        temperature_unit, blood_glucose_unit, week_start, timezone
		 FROM user_preferences WHERE user_id = $1`, userID,
	).Scan(&p.UserID, &p.Language, &p.DateFormat, &p.WeightUnit, &p.HeightUnit,
		&p.TemperatureUnit, &p.BloodGlucoseUnit, &p.WeekStart, &p.Timezone,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan preferences: %w", err)
	}
	return &p, nil
}

func (r *UserRepo) UpsertPreferences(ctx context.Context, p *user.Preferences) error {
	query := `
		INSERT INTO user_preferences (user_id, language, date_format, weight_unit, height_unit,
			temperature_unit, blood_glucose_unit, week_start, timezone)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
		ON CONFLICT (user_id) DO UPDATE SET
			language = EXCLUDED.language, date_format = EXCLUDED.date_format,
			weight_unit = EXCLUDED.weight_unit, height_unit = EXCLUDED.height_unit,
			temperature_unit = EXCLUDED.temperature_unit, blood_glucose_unit = EXCLUDED.blood_glucose_unit,
			week_start = EXCLUDED.week_start, timezone = EXCLUDED.timezone`

	_, err := r.db.Exec(ctx, query,
		p.UserID, p.Language, p.DateFormat, p.WeightUnit, p.HeightUnit,
		p.TemperatureUnit, p.BloodGlucoseUnit, p.WeekStart, p.Timezone,
	)
	return err
}

// ── Storage ─────────────────────────────────────────────────────────

func (r *UserRepo) GetStorage(ctx context.Context, userID uuid.UUID) (*user.StorageInfo, error) {
	var s user.StorageInfo
	err := r.db.QueryRow(ctx,
		"SELECT user_id, used_bytes, quota_bytes, last_calculated_at FROM user_storage WHERE user_id = $1",
		userID,
	).Scan(&s.UserID, &s.UsedBytes, &s.QuotaBytes, &s.LastCalculatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan storage: %w", err)
	}
	return &s, nil
}

func (r *UserRepo) InitStorage(ctx context.Context, userID uuid.UUID, quotaBytes int64) error {
	_, err := r.db.Exec(ctx,
		"INSERT INTO user_storage (user_id, quota_bytes) VALUES ($1, $2) ON CONFLICT DO NOTHING",
		userID, quotaBytes,
	)
	return err
}
