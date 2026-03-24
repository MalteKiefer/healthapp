package family

import (
	"context"

	"github.com/google/uuid"
)

// Repository defines the persistence interface for family management.
type Repository interface {
	Create(ctx context.Context, f *Family) error
	GetByID(ctx context.Context, id uuid.UUID) (*Family, error)
	ListByUserID(ctx context.Context, userID uuid.UUID) ([]Family, error)
	Update(ctx context.Context, f *Family) error
	Dissolve(ctx context.Context, id uuid.UUID) error

	AddMember(ctx context.Context, m *FamilyMembership) error
	RemoveMember(ctx context.Context, familyID, userID uuid.UUID) error
	GetMemberships(ctx context.Context, familyID uuid.UUID) ([]FamilyMembership, error)

	CreateInvite(ctx context.Context, inv *FamilyInvite) error
	GetInviteByToken(ctx context.Context, token string) (*FamilyInvite, error)
	UseInvite(ctx context.Context, id uuid.UUID) error
}
