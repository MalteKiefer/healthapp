# Contacts Redesign — Design Specification

**Date:** 2026-04-01
**Status:** Approved
**Scope:** Contact type separation (medical/personal), structured address fields, OSM address autocomplete, computed address backward compat

## Overview

Redesign the contacts system to support two contact types (medical and personal) with a single `contact_type` field on the existing `medical_contacts` table. Replace the freetext `address` field with structured address fields (`street`, `postal_code`, `city`, `country`) plus coordinates (`latitude`, `longitude`). Add OpenStreetMap Nominatim address search via a button-triggered overlay. The old `address` field becomes computed (read-only), ensuring zero changes to existing consumers (Calendar Feed, PDF Export, Appointments, Emergency Access).

---

## 1. Data Model

### New Fields on `medical_contacts`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `contact_type` | `TEXT NOT NULL` | `'medical'` | `"medical"` or `"personal"` |
| `street` | `TEXT` | NULL | Street + house number |
| `postal_code` | `TEXT` | NULL | Postal code |
| `city` | `TEXT` | NULL | City/town |
| `country` | `TEXT` | NULL | Country |
| `latitude` | `DOUBLE PRECISION` | NULL | Latitude from OSM |
| `longitude` | `DOUBLE PRECISION` | NULL | Longitude from OSM |

### Existing `address` Field

Remains in the table but becomes **computed / read-only**:
- **Write path:** API accepts `street`, `postal_code`, `city`, `country`. Go model computes `address` as `"street, postal_code city, country"` before every Create/Update.
- **Read path:** `address` is returned in JSON as before. All existing consumers (Calendar Feed, PDF, Appointments, Search) work unchanged.

### Computed Address Logic

```go
func (c *Contact) ComputeAddress() {
    parts := []string{}
    if c.Street != nil && *c.Street != "" { parts = append(parts, *c.Street) }
    if c.PostalCode != nil && *c.PostalCode != "" { parts = append(parts, *c.PostalCode) }
    if c.City != nil && *c.City != "" { parts = append(parts, *c.City) }
    if c.Country != nil && *c.Country != "" { parts = append(parts, *c.Country) }
    if len(parts) > 0 {
        addr := strings.Join(parts, ", ")
        c.Address = &addr
    }
}
```

Called in handler before `Create` and `Update`.

### Extended Go Model

```go
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
```

### Migration

```sql
ALTER TABLE medical_contacts
  ADD COLUMN contact_type TEXT NOT NULL DEFAULT 'medical',
  ADD COLUMN street TEXT,
  ADD COLUMN postal_code TEXT,
  ADD COLUMN city TEXT,
  ADD COLUMN country TEXT,
  ADD COLUMN latitude DOUBLE PRECISION,
  ADD COLUMN longitude DOUBLE PRECISION;

-- Migrate existing addresses to street field
UPDATE medical_contacts SET street = address WHERE address IS NOT NULL AND address != '';
```

---

## 2. OSM Address Search

### Nominatim API

- **Endpoint:** `https://nominatim.openstreetmap.org/search`
- **Parameters:** `q={search}&format=jsonv2&addressdetails=1&limit=5`
- **Headers:** `User-Agent: HealthVault/1.0`
- **Cost:** Free, no API key, no registration
- **Rate limit:** Max 1 request/second
- **Privacy:** No personal data transmitted (only search text)

### UX Flow

1. User clicks **search button** (magnifying glass icon) next to address fields
2. **Search overlay** opens (small modal/popover):
   - Search input (autofocused)
   - User types e.g. "Berliner Str 42 München"
   - Search triggered after 500ms debounce or on Enter
3. **Results list** shows max 5 suggestions with formatted address
4. User clicks a suggestion
5. **Fields auto-filled:**
   - `street` ← Nominatim `road` + `house_number`
   - `postal_code` ← `postcode`
   - `city` ← `city` / `town` / `village`
   - `country` ← `country`
   - `latitude` ← `lat`
   - `longitude` ← `lon`
6. Overlay closes, address fields are populated
7. User can manually edit any field after

### Technical Implementation

- Frontend-only — no backend proxy needed (Nominatim is public)
- Direct `fetch()` from browser
- 500ms debounce on keystrokes
- No API key, no secret, no backend endpoint

### Manual Entry

Address fields are always freely editable. OSM search is optional — users who don't want to search can type directly into the fields.

---

## 3. Frontend UI

### Contacts Page (Contacts.tsx)

**Filter tabs at top:** Two tabs above contact list — `Medical` | `Personal`. Filters by `contact_type`. Default: `medical`.

**Contact cards:**
- **Medical contacts** show: Name, Specialty, Facility, Phone, Email, formatted address (from structured fields), Notes, Emergency badge
- **Personal contacts** show: Name, Phone, Email, formatted address, Notes, Emergency badge — no Specialty/Facility

**Map link:** When coordinates exist, small link below address: "Show route" → opens `https://www.openstreetmap.org/directions?mlat={lat}&mlon={lon}` in new tab.

### Contact Form (Create/Edit Modal)

**Type selection** (Create only, not Edit):
- Segmented control / radio-group at top: `Medical` | `Personal`
- Controls which fields are shown

**Fields — Medical:**
- Name * (text)
- Specialty (text, placeholder "e.g. Cardiology")
- Facility (text)
- Phone (tel)
- Email (email)
- Address: `Street`, `Postal Code`, `City`, `Country` — 4 fields in 2 rows + search button (magnifying glass)
- Notes (textarea)
- Emergency contact (checkbox)

**Fields — Personal:**
- Name * (text)
- Phone (tel)
- Email (email)
- Address: same 4 fields + search button
- Notes (textarea)
- Emergency contact (checkbox)

No Specialty/Facility for personal contacts.

### OSM Search Overlay

- Opens as small modal (similar to notification dropdown)
- Search input + results list (max 5 entries)
- Each entry shows formatted address
- Click fills the 4 address fields + coordinates and closes overlay

---

## 4. Backend Changes

### API Changes

Existing endpoints unchanged, only accepted/returned fields expand:

- `POST /profiles/{profileID}/contacts` — accepts `contact_type`, `street`, `postal_code`, `city`, `country`, `latitude`, `longitude`, `notes`
- `PATCH /profiles/{profileID}/contacts/{contactID}` — same
- `GET /profiles/{profileID}/contacts` — returns all new fields + computed `address`

No new endpoints needed.

### Consumer Impact

| Consumer | Reads | Change needed? |
|----------|-------|----------------|
| Calendar Feed (ICS) | `contact.Address` | No — computed, stays populated |
| PDF Export | `contact.Address` | No |
| Appointments (doctor autocomplete) | `contact.Name`, `contact.Address` | No |
| Emergency Access | `is_emergency_contact` filter | No |
| Search | searches `address` | No |

Zero changes to existing consumers.

---

## 5. i18n Keys

### New keys needed

**English:**
```json
"contacts.type_medical": "Medical",
"contacts.type_personal": "Personal",
"contacts.street": "Street",
"contacts.postal_code": "Postal Code",
"contacts.city": "City",
"contacts.country": "Country",
"contacts.notes": "Notes",
"contacts.search_address": "Search Address",
"contacts.search_placeholder": "Search for an address...",
"contacts.show_route": "Show route",
"contacts.no_results": "No results found"
```

**German:**
```json
"contacts.type_medical": "Medizinisch",
"contacts.type_personal": "Persönlich",
"contacts.street": "Straße",
"contacts.postal_code": "PLZ",
"contacts.city": "Ort",
"contacts.country": "Land",
"contacts.notes": "Notizen",
"contacts.search_address": "Adresse suchen",
"contacts.search_placeholder": "Adresse suchen...",
"contacts.show_route": "Route anzeigen",
"contacts.no_results": "Keine Ergebnisse gefunden"
```

---

## 6. Implementation Scope

### What Changes

- `api/internal/migrations/` — new migration file for schema changes
- `api/internal/domain/contacts/model.go` — extended struct + ComputeAddress method
- `api/internal/repository/postgres/contact.go` — updated SQL queries for new fields
- `api/internal/api/handlers/contacts.go` — call ComputeAddress before Create/Update
- `web/src/pages/Contacts.tsx` — complete UI rewrite (type tabs, structured address, OSM search, notes field)
- `web/src/i18n/en.json` — new translation keys
- `web/src/i18n/de.json` — new translation keys

### What Stays Unchanged

- All API endpoints (same URLs, same methods)
- Calendar Feed handler
- PDF Export handler
- Appointments page (doctor autocomplete reads `address` — still works)
- Emergency Access system
- Search handler
- Database table name (`medical_contacts`)
