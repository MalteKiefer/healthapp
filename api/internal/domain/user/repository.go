package user

import (
	"context"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for users.
type Repository interface {
	Create(ctx context.Context, u *User) error
	GetByID(ctx context.Context, id uuid.UUID) (*User, error)
	GetByEmail(ctx context.Context, email string) (*User, error)
	Update(ctx context.Context, u *User) error
	Delete(ctx context.Context, id uuid.UUID) error
	SetDisabled(ctx context.Context, id uuid.UUID, disabled bool) error

	// Sessions
	CreateSession(ctx context.Context, s *Session) error
	GetSessionsByUserID(ctx context.Context, userID uuid.UUID) ([]Session, error)
	GetSessionByJTI(ctx context.Context, jti string) (*Session, error)
	RevokeSession(ctx context.Context, id uuid.UUID) error
	RevokeAllSessions(ctx context.Context, userID uuid.UUID, exceptID *uuid.UUID) error
	UpdateSessionActivity(ctx context.Context, id uuid.UUID) error

	// Recovery codes
	StoreRecoveryCodes(ctx context.Context, userID uuid.UUID, codeHashes []string) error
	GetUnusedRecoveryCodes(ctx context.Context, userID uuid.UUID) ([]RecoveryCode, error)
	MarkRecoveryCodeUsed(ctx context.Context, codeID uuid.UUID) error
	DeleteRecoveryCodes(ctx context.Context, userID uuid.UUID) error

	// Preferences
	GetPreferences(ctx context.Context, userID uuid.UUID) (*Preferences, error)
	UpsertPreferences(ctx context.Context, p *Preferences) error

	// Storage
	GetStorage(ctx context.Context, userID uuid.UUID) (*StorageInfo, error)
	InitStorage(ctx context.Context, userID uuid.UUID, quotaBytes int64) error
}
