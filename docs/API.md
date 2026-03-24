# HealthVault API Reference

Base URL: `/api/v1`

All endpoints under the protected groups require a valid JWT access token in the `Authorization: Bearer <token>` header unless noted otherwise.

---

## Public Endpoints (No Auth)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /health | Health check (database + Redis status) |
| GET | /cal/{token}.ics | ICS calendar feed (token-based, no JWT) |
| GET | /share/{shareID} | Temporary doctor share (fragment-based key, no JWT) |

---

## Authentication

Rate-limited endpoints. No JWT required.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | /auth/register | Initialize registration (get PEK + auth salts) | No |
| POST | /auth/register/complete | Complete registration (submit keys + auth hash) | No |
| POST | /auth/login | Login with email + auth hash | No |
| POST | /auth/login/2fa | Complete login with TOTP 2FA code | No |
| POST | /auth/refresh | Refresh access token | No (refresh token) |
| POST | /auth/logout | Logout / revoke token | No |
| POST | /auth/recovery | Account recovery via recovery codes | No |
| GET | /auth/2fa/setup | Get TOTP setup (QR code / secret) | No |
| POST | /auth/2fa/enable | Enable TOTP 2FA | No |
| POST | /auth/2fa/disable | Disable TOTP 2FA | No |
| GET | /auth/2fa/recovery-codes | Regenerate recovery codes | No |

---

## Users

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /users/me | Get current user info | Yes |
| PATCH | /users/me | Update current user | Yes |
| DELETE | /users/me | Delete current user account | Yes |
| GET | /users/me/sessions | List active sessions | Yes |
| DELETE | /users/me/sessions/{sessionID} | Revoke a specific session | Yes |
| DELETE | /users/me/sessions/others | Revoke all other sessions | Yes |
| POST | /users/me/change-passphrase | Change passphrase (re-key) | Yes |
| GET | /users/me/storage | Get storage usage and quota | Yes |
| GET | /users/me/preferences | Get user preferences | Yes |
| PATCH | /users/me/preferences | Update user preferences | Yes |
| GET | /users/{userID}/identity-pubkey | Get a user's public identity key | Yes |

---

## Profiles

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles | List all accessible profiles | Yes |
| POST | /profiles | Create a new profile | Yes |
| GET | /profiles/{profileID} | Get a profile | Yes |
| PATCH | /profiles/{profileID} | Update a profile | Yes |
| DELETE | /profiles/{profileID} | Delete a profile | Yes |
| POST | /profiles/{profileID}/grants | Create a profile key grant | Yes |
| DELETE | /profiles/{profileID}/grants/{grantUserID} | Revoke a profile key grant | Yes |
| POST | /profiles/{profileID}/key-rotation | Rotate profile encryption key | Yes |
| POST | /profiles/{profileID}/transfer | Transfer profile ownership | Yes |
| POST | /profiles/{profileID}/archive | Archive a profile | Yes |
| POST | /profiles/{profileID}/unarchive | Unarchive a profile | Yes |

---

## Vitals

All scoped under `/profiles/{profileID}/vitals`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/vitals | List vitals | Yes |
| POST | /profiles/{profileID}/vitals | Create a vital record | Yes |
| GET | /profiles/{profileID}/vitals/chart | Get chart data for vitals | Yes |
| GET | /profiles/{profileID}/vitals/{vitalID} | Get a single vital | Yes |
| PATCH | /profiles/{profileID}/vitals/{vitalID} | Update a vital | Yes |
| DELETE | /profiles/{profileID}/vitals/{vitalID} | Delete a vital | Yes |

---

## Labs

All scoped under `/profiles/{profileID}/labs`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/labs | List lab results | Yes |
| POST | /profiles/{profileID}/labs | Create a lab result | Yes |
| GET | /profiles/{profileID}/labs/{labID} | Get a single lab result | Yes |
| PATCH | /profiles/{profileID}/labs/{labID} | Update a lab result | Yes |
| DELETE | /profiles/{profileID}/labs/{labID} | Delete a lab result | Yes |
| GET | /profiles/{profileID}/labs/{labID}/export/pdf | Export lab result as PDF | Yes |

---

## Documents

All scoped under `/profiles/{profileID}/documents`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/documents | List documents | Yes |
| POST | /profiles/{profileID}/documents | Upload a document | Yes |
| POST | /profiles/{profileID}/documents/bulk | Bulk upload documents | Yes |
| GET | /profiles/{profileID}/documents/search | Search documents | Yes |
| GET | /profiles/{profileID}/documents/{docID} | Get a document | Yes |
| PATCH | /profiles/{profileID}/documents/{docID} | Update document metadata | Yes |
| DELETE | /profiles/{profileID}/documents/{docID} | Delete a document | Yes |
| POST | /profiles/{profileID}/documents/{docID}/ocr-index | Create OCR index for document | Yes |
| DELETE | /profiles/{profileID}/documents/{docID}/ocr-index | Delete OCR index for document | Yes |

---

## Diary

Health diary entries, scoped under `/profiles/{profileID}/diary`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/diary | List diary entries | Yes |
| POST | /profiles/{profileID}/diary | Create a diary entry | Yes |
| GET | /profiles/{profileID}/diary/{eventID} | Get a diary entry | Yes |
| PATCH | /profiles/{profileID}/diary/{eventID} | Update a diary entry | Yes |
| DELETE | /profiles/{profileID}/diary/{eventID} | Delete a diary entry | Yes |

---

## Medications

All scoped under `/profiles/{profileID}/medications`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/medications | List medications | Yes |
| POST | /profiles/{profileID}/medications | Create a medication | Yes |
| GET | /profiles/{profileID}/medications/active | List active medications | Yes |
| GET | /profiles/{profileID}/medications/adherence | Get medication adherence data | Yes |
| PATCH | /profiles/{profileID}/medications/{medID} | Update a medication | Yes |
| DELETE | /profiles/{profileID}/medications/{medID} | Delete a medication | Yes |
| GET | /profiles/{profileID}/medications/{medID}/intake | List intake records | Yes |
| POST | /profiles/{profileID}/medications/{medID}/intake | Record an intake | Yes |
| PATCH | /profiles/{profileID}/medications/{medID}/intake/{intakeID} | Update an intake record | Yes |
| DELETE | /profiles/{profileID}/medications/{medID}/intake/{intakeID} | Delete an intake record | Yes |

---

## Allergies

All scoped under `/profiles/{profileID}/allergies`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/allergies | List allergies | Yes |
| POST | /profiles/{profileID}/allergies | Create an allergy | Yes |
| PATCH | /profiles/{profileID}/allergies/{allergyID} | Update an allergy | Yes |
| DELETE | /profiles/{profileID}/allergies/{allergyID} | Delete an allergy | Yes |

---

## Vaccinations

All scoped under `/profiles/{profileID}/vaccinations`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/vaccinations | List vaccinations | Yes |
| POST | /profiles/{profileID}/vaccinations | Create a vaccination record | Yes |
| GET | /profiles/{profileID}/vaccinations/due | List upcoming/due vaccinations | Yes |
| PATCH | /profiles/{profileID}/vaccinations/{vaccID} | Update a vaccination | Yes |
| DELETE | /profiles/{profileID}/vaccinations/{vaccID} | Delete a vaccination | Yes |

---

## Diagnoses

All scoped under `/profiles/{profileID}/diagnoses`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/diagnoses | List diagnoses | Yes |
| POST | /profiles/{profileID}/diagnoses | Create a diagnosis | Yes |
| PATCH | /profiles/{profileID}/diagnoses/{diagID} | Update a diagnosis | Yes |
| DELETE | /profiles/{profileID}/diagnoses/{diagID} | Delete a diagnosis | Yes |

---

## Contacts

Medical contacts, scoped under `/profiles/{profileID}/contacts`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/contacts | List medical contacts | Yes |
| POST | /profiles/{profileID}/contacts | Create a contact | Yes |
| PATCH | /profiles/{profileID}/contacts/{contactID} | Update a contact | Yes |
| DELETE | /profiles/{profileID}/contacts/{contactID} | Delete a contact | Yes |

---

## Tasks

All scoped under `/profiles/{profileID}/tasks`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/tasks | List tasks | Yes |
| POST | /profiles/{profileID}/tasks | Create a task | Yes |
| GET | /profiles/{profileID}/tasks/open | List open/pending tasks | Yes |
| PATCH | /profiles/{profileID}/tasks/{taskID} | Update a task | Yes |
| DELETE | /profiles/{profileID}/tasks/{taskID} | Delete a task | Yes |

---

## Appointments

All scoped under `/profiles/{profileID}/appointments`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/appointments | List appointments | Yes |
| POST | /profiles/{profileID}/appointments | Create an appointment | Yes |
| GET | /profiles/{profileID}/appointments/upcoming | List upcoming appointments | Yes |
| PATCH | /profiles/{profileID}/appointments/{apptID} | Update an appointment | Yes |
| DELETE | /profiles/{profileID}/appointments/{apptID} | Delete an appointment | Yes |
| POST | /profiles/{profileID}/appointments/{apptID}/complete | Mark appointment as completed | Yes |

---

## Symptoms

All scoped under `/profiles/{profileID}/symptoms`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/symptoms | List symptoms | Yes |
| POST | /profiles/{profileID}/symptoms | Create a symptom record | Yes |
| GET | /profiles/{profileID}/symptoms/chart | Get symptom chart data | Yes |
| GET | /profiles/{profileID}/symptoms/{symptomID} | Get a single symptom | Yes |
| PATCH | /profiles/{profileID}/symptoms/{symptomID} | Update a symptom | Yes |
| DELETE | /profiles/{profileID}/symptoms/{symptomID} | Delete a symptom | Yes |

---

## Vital Thresholds

Scoped under `/profiles/{profileID}`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/vital-thresholds | Get vital alert thresholds | Yes |
| PUT | /profiles/{profileID}/vital-thresholds | Set vital alert thresholds | Yes |

---

## Activity Log

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/activity | List activity log for a profile | Yes |

---

## Emergency (Profile-scoped)

Scoped under `/profiles/{profileID}`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/emergency-card | Get emergency card data | Yes |
| POST | /profiles/{profileID}/emergency-access | Configure emergency access | Yes |
| GET | /profiles/{profileID}/emergency-access | Get emergency access configuration | Yes |
| DELETE | /profiles/{profileID}/emergency-access | Delete emergency access configuration | Yes |

---

## Export (Profile-scoped)

Scoped under `/profiles/{profileID}`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /profiles/{profileID}/export/fhir | Export profile as FHIR R4 Bundle | Yes |
| POST | /profiles/{profileID}/import/fhir | Import data from FHIR R4 Bundle | Yes |
| GET | /profiles/{profileID}/export/ics | Export profile appointments as ICS | Yes |
| GET | /profiles/{profileID}/export/pdf | Generate doctor report PDF | Yes |

---

## Doctor Shares (Profile-scoped)

Temporary read-only share links, scoped under `/profiles/{profileID}`.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | /profiles/{profileID}/share | Create a temporary share link | Yes |
| GET | /profiles/{profileID}/shares | List active share links | Yes |
| DELETE | /profiles/{profileID}/share/{shareID} | Revoke a share link | Yes |

---

## Families

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /families | List families | Yes |
| POST | /families | Create a family | Yes |
| GET | /families/{familyID} | Get family details | Yes |
| PATCH | /families/{familyID} | Update family details | Yes |
| POST | /families/{familyID}/invite | Invite a member to a family | Yes |
| POST | /families/{familyID}/accept | Accept a family invitation | Yes |
| DELETE | /families/{familyID}/members/{memberID} | Remove a family member | Yes |
| POST | /families/{familyID}/dissolve | Dissolve a family | Yes |

---

## Notifications

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /notifications | List notifications | Yes |
| POST | /notifications/{notifID}/read | Mark a notification as read | Yes |
| POST | /notifications/read-all | Mark all notifications as read | Yes |
| DELETE | /notifications/{notifID} | Delete a notification | Yes |
| GET | /notifications/preferences | Get notification preferences | Yes |
| PATCH | /notifications/preferences | Update notification preferences | Yes |

---

## Calendar Feeds

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /calendar/feeds | List calendar feeds | Yes |
| POST | /calendar/feeds | Create a calendar feed | Yes |
| GET | /calendar/feeds/{feedID} | Get a calendar feed | Yes |
| PATCH | /calendar/feeds/{feedID} | Update a calendar feed | Yes |
| DELETE | /calendar/feeds/{feedID} | Delete a calendar feed | Yes |

---

## Search

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /search | Full-text search across all resources | Yes |

---

## Reference Ranges

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /reference-ranges | List standard vital/lab reference ranges | Yes |

---

## Export (Global)

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | /export | Export user data (all profiles) | Yes |
| POST | /export/schedule | Schedule a recurring export | Yes |

---

## Emergency (Global)

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | /emergency/request/{token} | Request emergency access via token | Yes |
| GET | /emergency/pending | List pending emergency access requests | Yes |
| POST | /emergency/approve/{requestID} | Approve an emergency access request | Yes |
| POST | /emergency/deny/{requestID} | Deny an emergency access request | Yes |

---

## Admin

All admin endpoints require JWT with `role: admin`. Protected by `RequireAdmin` middleware.

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | /admin/users | List all users | Admin |
| POST | /admin/users/{userID}/disable | Disable a user account | Admin |
| POST | /admin/users/{userID}/enable | Enable a user account | Admin |
| DELETE | /admin/users/{userID} | Delete a user account | Admin |
| GET | /admin/users/{userID}/sessions | List a user's sessions | Admin |
| DELETE | /admin/users/{userID}/sessions | Revoke all sessions for a user | Admin |
| PATCH | /admin/users/{userID}/quota | Set storage quota for a user | Admin |
| GET | /admin/storage | Get global storage statistics | Admin |
| GET | /admin/invites | List invite codes | Admin |
| POST | /admin/invites | Create an invite code | Admin |
| DELETE | /admin/invites/{token} | Delete an invite code | Admin |
| GET | /admin/system | Get system info (version, uptime) | Admin |
| GET | /admin/backups | List backups | Admin |
| POST | /admin/backups/trigger | Trigger a backup | Admin |
| GET | /admin/audit-log | Get audit log | Admin |
| PATCH | /admin/settings | Update system settings | Admin |
| GET | /admin/legal/documents | List legal/consent documents | Admin |
| POST | /admin/legal/documents | Create a legal/consent document | Admin |
| GET | /admin/legal/consent-records | List all consent records | Admin |
| GET | /admin/legal/consent-records/{userID} | Get consent records for a user | Admin |
| GET | /admin/webhooks | List webhooks | Admin |
| POST | /admin/webhooks | Create a webhook | Admin |
| PATCH | /admin/webhooks/{webhookID} | Update a webhook | Admin |
| DELETE | /admin/webhooks/{webhookID} | Delete a webhook | Admin |
| GET | /admin/webhooks/{webhookID}/logs | Get webhook delivery logs | Admin |
| POST | /admin/webhooks/{webhookID}/test | Send a test webhook | Admin |
