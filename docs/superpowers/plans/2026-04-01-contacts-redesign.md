# Contacts Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add contact type separation (medical/personal), structured address fields with OSM Nominatim autocomplete, and computed backward-compatible `address` field.

**Architecture:** New DB migration adds 7 columns to `medical_contacts`. Go model extended with ComputeAddress() method called before every write. Frontend Contacts.tsx rewritten with type tabs, structured address form, and OSM search overlay. All existing consumers (Calendar, PDF, Appointments) continue reading `address` unchanged.

**Tech Stack:** Go (backend), PostgreSQL (migration), React/TypeScript (frontend), OpenStreetMap Nominatim API (address search)

**Design Spec:** `docs/superpowers/specs/2026-04-01-contacts-redesign-design.md`

---

## File Structure

### Modified Files
- `api/internal/domain/contacts/model.go` — Add new fields + ComputeAddress method
- `api/internal/repository/postgres/contact.go` — Update all SQL queries for new columns
- `api/internal/api/handlers/contacts.go` — Call ComputeAddress before Create/Update
- `web/src/pages/Contacts.tsx` — Complete rewrite: type tabs, structured address, OSM search, notes
- `web/src/pages/Appointments.tsx` — Update Contact interface to include new address fields
- `web/src/i18n/en.json` — New translation keys
- `web/src/i18n/de.json` — New translation keys

### Created Files
- `api/internal/migrations/000005_contacts_type_address.up.sql` — Schema migration
- `api/internal/migrations/000005_contacts_type_address.down.sql` — Rollback migration

### Unchanged Files
- `api/internal/api/handlers/calendar.go` — Reads `address`, still works (computed)
- `api/internal/api/handlers/pdf.go` — Reads `address`, still works
- `api/internal/api/handlers/emergency.go` — Reads `is_emergency_contact`, unchanged
- `api/internal/domain/contacts/repository.go` — Interface unchanged (same 5 methods)

---

### Task 1: Database Migration

**Files:**
- Create: `api/internal/migrations/000005_contacts_type_address.up.sql`
- Create: `api/internal/migrations/000005_contacts_type_address.down.sql`

- [ ] **Step 1: Write up migration**

```sql
-- 000005_contacts_type_address.up.sql
ALTER TABLE medical_contacts
  ADD COLUMN contact_type TEXT NOT NULL DEFAULT 'medical',
  ADD COLUMN street TEXT,
  ADD COLUMN postal_code TEXT,
  ADD COLUMN city TEXT,
  ADD COLUMN country TEXT,
  ADD COLUMN latitude DOUBLE PRECISION,
  ADD COLUMN longitude DOUBLE PRECISION;

-- Migrate existing freetext addresses into street field
UPDATE medical_contacts SET street = address WHERE address IS NOT NULL AND address != '';
```

- [ ] **Step 2: Write down migration**

```sql
-- 000005_contacts_type_address.down.sql
ALTER TABLE medical_contacts
  DROP COLUMN IF EXISTS contact_type,
  DROP COLUMN IF EXISTS street,
  DROP COLUMN IF EXISTS postal_code,
  DROP COLUMN IF EXISTS city,
  DROP COLUMN IF EXISTS country,
  DROP COLUMN IF EXISTS latitude,
  DROP COLUMN IF EXISTS longitude;
```

- [ ] **Step 3: Verify migration files exist**

Run: `ls -la api/internal/migrations/000005_*`
Expected: Both files present

- [ ] **Step 4: Commit**

```bash
git add api/internal/migrations/000005_contacts_type_address.up.sql api/internal/migrations/000005_contacts_type_address.down.sql
git commit -m "feat(contacts): add migration for contact_type and structured address fields"
```

---

### Task 2: Backend Model + ComputeAddress

**Files:**
- Modify: `api/internal/domain/contacts/model.go`

- [ ] **Step 1: Replace model.go with extended struct**

Replace the entire file:

```go
package contacts

import (
	"strings"
	"time"

	"github.com/google/uuid"
)

type Contact struct {
	ID                 uuid.UUID  `json:"id"`
	ProfileID          uuid.UUID  `json:"profile_id"`
	ContactType        string     `json:"contact_type"`
	Name               string     `json:"name"`
	Specialty          *string    `json:"specialty,omitempty"`
	Facility           *string    `json:"facility,omitempty"`
	Phone              *string    `json:"phone,omitempty"`
	Email              *string    `json:"email,omitempty"`
	Street             *string    `json:"street,omitempty"`
	PostalCode         *string    `json:"postal_code,omitempty"`
	City               *string    `json:"city,omitempty"`
	Country            *string    `json:"country,omitempty"`
	Latitude           *float64   `json:"latitude,omitempty"`
	Longitude          *float64   `json:"longitude,omitempty"`
	Address            *string    `json:"address,omitempty"`
	Notes              *string    `json:"notes,omitempty"`
	IsEmergencyContact bool       `json:"is_emergency_contact"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
	DeletedAt          *time.Time `json:"-"`
}

// ComputeAddress builds the address field from structured parts.
// Must be called before Create and Update.
func (c *Contact) ComputeAddress() {
	var parts []string
	if c.Street != nil && *c.Street != "" {
		parts = append(parts, *c.Street)
	}
	if c.PostalCode != nil && *c.PostalCode != "" {
		parts = append(parts, *c.PostalCode)
	}
	if c.City != nil && *c.City != "" {
		parts = append(parts, *c.City)
	}
	if c.Country != nil && *c.Country != "" {
		parts = append(parts, *c.Country)
	}
	if len(parts) > 0 {
		addr := strings.Join(parts, ", ")
		c.Address = &addr
	} else {
		c.Address = nil
	}
}
```

- [ ] **Step 2: Verify build**

Run: `cd api && go build ./...`
Expected: Build fails (repository SQL doesn't match yet — expected, will fix in Task 3)

- [ ] **Step 3: Commit**

```bash
git add api/internal/domain/contacts/model.go
git commit -m "feat(contacts): extend model with contact_type, structured address, ComputeAddress"
```

---

### Task 3: Backend Repository (SQL Queries)

**Files:**
- Modify: `api/internal/repository/postgres/contact.go`

- [ ] **Step 1: Update contact.go with new columns in all queries**

Replace the entire file:

```go
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
	street, postal_code, city, country, latitude, longitude, address,
	notes, is_emergency_contact, created_at, updated_at, deleted_at`

func scanContact(row pgx.Row) (*contacts.Contact, error) {
	var c contacts.Contact
	err := row.Scan(
		&c.ID, &c.ProfileID, &c.ContactType, &c.Name, &c.Specialty, &c.Facility,
		&c.Phone, &c.Email, &c.Street, &c.PostalCode, &c.City, &c.Country,
		&c.Latitude, &c.Longitude, &c.Address, &c.Notes, &c.IsEmergencyContact,
		&c.CreatedAt, &c.UpdatedAt, &c.DeletedAt,
	)
	return &c, err
}

func scanContacts(rows pgx.Rows) ([]contacts.Contact, error) {
	var result []contacts.Contact
	for rows.Next() {
		var c contacts.Contact
		if err := rows.Scan(
			&c.ID, &c.ProfileID, &c.ContactType, &c.Name, &c.Specialty, &c.Facility,
			&c.Phone, &c.Email, &c.Street, &c.PostalCode, &c.City, &c.Country,
			&c.Latitude, &c.Longitude, &c.Address, &c.Notes, &c.IsEmergencyContact,
			&c.CreatedAt, &c.UpdatedAt, &c.DeletedAt,
		); err != nil {
			return nil, err
		}
		result = append(result, c)
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
	if c.ContactType == "" {
		c.ContactType = "medical"
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO medical_contacts (id, profile_id, contact_type, name, specialty, facility,
			phone, email, street, postal_code, city, country, latitude, longitude, address,
			notes, is_emergency_contact, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19)`,
		c.ID, c.ProfileID, c.ContactType, c.Name, c.Specialty, c.Facility,
		c.Phone, c.Email, c.Street, c.PostalCode, c.City, c.Country,
		c.Latitude, c.Longitude, c.Address, c.Notes, c.IsEmergencyContact,
		c.CreatedAt, c.UpdatedAt)
	return err
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
		`SELECT `+contactColumns+` FROM medical_contacts WHERE profile_id = $1 AND deleted_at IS NULL ORDER BY name`, profileID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanContacts(rows)
}

func (r *ContactRepo) Update(ctx context.Context, c *contacts.Contact) error {
	c.UpdatedAt = time.Now().UTC()
	_, err := r.db.Exec(ctx, `
		UPDATE medical_contacts SET contact_type=$2, name=$3, specialty=$4, facility=$5,
			phone=$6, email=$7, street=$8, postal_code=$9, city=$10, country=$11,
			latitude=$12, longitude=$13, address=$14, notes=$15, is_emergency_contact=$16, updated_at=$17
		WHERE id=$1 AND deleted_at IS NULL`,
		c.ID, c.ContactType, c.Name, c.Specialty, c.Facility,
		c.Phone, c.Email, c.Street, c.PostalCode, c.City, c.Country,
		c.Latitude, c.Longitude, c.Address, c.Notes, c.IsEmergencyContact, c.UpdatedAt)
	return err
}

func (r *ContactRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "UPDATE medical_contacts SET deleted_at=$2 WHERE id=$1 AND deleted_at IS NULL", id, time.Now().UTC())
	return err
}
```

- [ ] **Step 2: Verify build**

Run: `cd api && go build ./...`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add api/internal/repository/postgres/contact.go
git commit -m "feat(contacts): update SQL queries for new contact fields"
```

---

### Task 4: Backend Handler (ComputeAddress call)

**Files:**
- Modify: `api/internal/api/handlers/contacts.go`

- [ ] **Step 1: Add ComputeAddress calls in HandleCreate and HandleUpdate**

In `HandleCreate`, add `c.ComputeAddress()` after decoding and before `Create`:

Find this block (around line 89):
```go
	c.ProfileID = profileID

	if err := h.contactRepo.Create(r.Context(), &c); err != nil {
```

Replace with:
```go
	c.ProfileID = profileID
	c.ComputeAddress()

	if err := h.contactRepo.Create(r.Context(), &c); err != nil {
```

In `HandleUpdate`, add `existing.ComputeAddress()` after decoding and before `Update`:

Find this block (around line 142):
```go
	if err := h.contactRepo.Update(r.Context(), existing); err != nil {
```

Replace with:
```go
	existing.ComputeAddress()

	if err := h.contactRepo.Update(r.Context(), existing); err != nil {
```

- [ ] **Step 2: Verify build**

Run: `cd api && go build ./...`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add api/internal/api/handlers/contacts.go
git commit -m "feat(contacts): call ComputeAddress before create/update"
```

---

### Task 5: i18n Keys

**Files:**
- Modify: `web/src/i18n/en.json`
- Modify: `web/src/i18n/de.json`

- [ ] **Step 1: Add new keys to en.json**

Add these keys inside the `"contacts"` section:

```json
"type_medical": "Medical",
"type_personal": "Personal",
"street": "Street",
"postal_code": "Postal Code",
"city": "City",
"country": "Country",
"notes": "Notes",
"search_address": "Search Address",
"search_placeholder": "Search for an address...",
"show_route": "Show route",
"no_results": "No results found"
```

- [ ] **Step 2: Add new keys to de.json**

Add these keys inside the `"contacts"` section:

```json
"type_medical": "Medizinisch",
"type_personal": "Persönlich",
"street": "Straße",
"postal_code": "PLZ",
"city": "Ort",
"country": "Land",
"notes": "Notizen",
"search_address": "Adresse suchen",
"search_placeholder": "Adresse suchen...",
"show_route": "Route anzeigen",
"no_results": "Keine Ergebnisse gefunden"
```

- [ ] **Step 3: Validate JSON**

Run: `cd web && node -e "JSON.parse(require('fs').readFileSync('src/i18n/en.json','utf8')); console.log('en OK')" && node -e "JSON.parse(require('fs').readFileSync('src/i18n/de.json','utf8')); console.log('de OK')"`
Expected: `en OK` and `de OK`

- [ ] **Step 4: Commit**

```bash
git add web/src/i18n/en.json web/src/i18n/de.json
git commit -m "i18n: add contacts redesign translation keys"
```

---

### Task 6: Frontend — Contacts.tsx Rewrite

**Files:**
- Modify: `web/src/pages/Contacts.tsx`

This is the largest frontend task. The page gets:
1. Type tabs (Medical | Personal) filtering the list
2. Structured address fields (street, postal_code, city, country) replacing the textarea
3. OSM Nominatim search overlay (button-triggered)
4. Notes field
5. Conditional Specialty/Facility fields (only for medical type)
6. Map route link when coordinates exist

- [ ] **Step 1: Rewrite Contacts.tsx**

Replace the entire file. Key changes from current:

**Interface:** Add `contact_type`, `street`, `postal_code`, `city`, `country`, `latitude`, `longitude` fields. Keep `address` as read-only computed.

**State:** Add `activeTab` for type filter (`'medical' | 'personal'`), `osmOpen` for search overlay, `osmQuery`/`osmResults` for search state. Add `createType` for contact type selection during create.

**Type tabs:** Two buttons above the card, styled with existing `.radio-group` or `.view-tabs` classes. Filter `sortedItems` by `contact_type === activeTab`.

**Form — Create modal:**
- Radio group at top: Medical | Personal (sets `contact_type` via hidden field or setValue)
- Medical: Name*, Specialty, Facility, Phone, Email, Address (4 fields + search btn), Notes, Emergency checkbox
- Personal: Name*, Phone, Email, Address (4 fields + search btn), Notes, Emergency checkbox
- Specialty/Facility hidden when `createType === 'personal'`

**Form — Edit modal:**
- Same as create but no type selector (type is fixed from the contact)
- Show/hide Specialty/Facility based on `editTarget.contact_type`

**Address fields layout:**
```
[Street                        ] [🔍]
[PLZ      ] [Ort              ]
[Land                          ]
```
Search button opens OSM overlay.

**OSM Search Overlay:**
- Rendered as a modal-overlay with smaller modal (max-width 400px)
- Search input (autofocused) + results list
- Nominatim fetch: `https://nominatim.openstreetmap.org/search?q=${query}&format=jsonv2&addressdetails=1&limit=5`
- Headers: `{ 'User-Agent': 'HealthVault/1.0' }`
- 500ms debounce via setTimeout/clearTimeout
- Each result shows `display_name`
- Click result: extract `road`+`house_number` → street, `postcode` → postal_code, `city`/`town`/`village` → city, `country` → country, `lat` → latitude, `lon` → longitude
- Close overlay, fill form fields via `setValue`

**Contact cards:**
- Show formatted address from `street, postal_code city, country` (not the old `address` field)
- If `latitude`+`longitude` exist: show "Route anzeigen" link → `https://www.openstreetmap.org/directions?mlat={lat}&mlon={lon}`
- Show `notes` if present
- Medical contacts show specialty + facility
- Personal contacts don't show specialty/facility

**Important:** The form must send `contact_type`, `street`, `postal_code`, `city`, `country`, `latitude`, `longitude`, `notes` to the API. Do NOT send the `address` field — the backend computes it.

- [ ] **Step 2: Verify type-check**

Run: `cd web && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add web/src/pages/Contacts.tsx
git commit -m "feat(contacts): rewrite with type tabs, structured address, OSM search"
```

---

### Task 7: Update Appointments Contact Interface

**Files:**
- Modify: `web/src/pages/Appointments.tsx`

- [ ] **Step 1: Extend Contact interface in Appointments.tsx**

The Appointments page has a local `Contact` interface (line 13). Update it to include the new fields so doctor autocomplete and location auto-fill continue working correctly:

Find:
```typescript
interface Contact { id: string; name: string; specialty?: string; facility?: string; address?: string }
```

Replace with:
```typescript
interface Contact { id: string; name: string; specialty?: string; facility?: string; address?: string; street?: string; postal_code?: string; city?: string; country?: string }
```

The `address` field is still computed and returned by the API, so the existing auto-fill logic (`if (match.address) setVal('location', match.address)`) continues to work unchanged.

- [ ] **Step 2: Verify type-check**

Run: `cd web && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add web/src/pages/Appointments.tsx
git commit -m "feat(contacts): update Appointments contact interface for new fields"
```

---

### Task 8: Verification

**Files:** None (verification only)

- [ ] **Step 1: Backend build**

Run: `cd api && go build ./...`
Expected: Succeeds

- [ ] **Step 2: Frontend type-check**

Run: `cd web && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Frontend build**

Run: `cd web && npx vite build`
Expected: Succeeds

- [ ] **Step 4: Run existing tests**

Run: `cd web && npx vitest run --reporter=verbose 2>&1 | tail -10`
Expected: All tests pass

- [ ] **Step 5: Run migration on dev DB**

Restart API container to auto-run migration:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml restart api
```

Check logs for `Schema up to date` with version 5:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs api --tail 10
```

- [ ] **Step 6: Visual QA in browser**

Open `http://localhost:5173`, navigate to Contacts:

- [ ] Medical/Personal tabs filter correctly
- [ ] Create modal shows type selector
- [ ] Medical form shows Specialty + Facility, Personal doesn't
- [ ] Address fields are 4 separate inputs (Street, PLZ, Ort, Land)
- [ ] OSM search button opens overlay
- [ ] Typing in OSM search shows Nominatim results
- [ ] Clicking a result fills all 4 address fields
- [ ] "Route anzeigen" link appears when coordinates exist
- [ ] Notes field visible and works
- [ ] Edit modal pre-populates all fields correctly
- [ ] Existing contacts display properly (migrated from old address → street)
- [ ] Appointments doctor autocomplete still works
