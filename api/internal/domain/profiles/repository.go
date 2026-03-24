package profiles

import (
	"context"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for profiles.
type Repository interface {
	Create(ctx context.Context, p *Profile) error
	GetByID(ctx context.Context, id uuid.UUID) (*Profile, error)
	GetByOwnerID(ctx context.Context, ownerUserID uuid.UUID) ([]Profile, error)
	GetAccessibleByUserID(ctx context.Context, userID uuid.UUID) ([]Profile, error)
	Update(ctx context.Context, p *Profile) error
	Delete(ctx context.Context, id uuid.UUID) error
	Archive(ctx context.Context, id uuid.UUID) error
	Unarchive(ctx context.Context, id uuid.UUID) error

	// Key grants
	CreateKeyGrant(ctx context.Context, g *KeyGrant) error
	RevokeKeyGrant(ctx context.Context, profileID, granteeUserID uuid.UUID) error
	GetKeyGrantsForProfile(ctx context.Context, profileID uuid.UUID) ([]KeyGrant, error)
	HasAccess(ctx context.Context, profileID, userID uuid.UUID) (bool, error)
}
