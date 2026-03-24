# HealthVault Emergency Access

## Overview

HealthVault provides two emergency access mechanisms: a **static emergency card** containing pre-selected health data, and **dynamic emergency access** that allows a designated contact or first responder to request access to a profile through a controlled, time-delayed process.

---

## Static Emergency Card

The emergency card is a pre-encrypted data blob containing critical health information that the profile owner chooses to include.

### Enabling the emergency card

1. Open a profile and navigate to **Emergency Info**.
2. Select which data categories to include (e.g., allergies, medications, conditions, blood type, emergency contacts).
3. Save the emergency card. The client encrypts the selected data and uploads the ciphertext.

### What appears on the card

The card contents are configured per profile. Typical fields include:

- Full name, date of birth, blood type
- Active allergies and drug intolerances
- Current medications with dosages
- Chronic conditions and diagnoses
- Emergency contact information
- Physician contact details

### QR code

The emergency card can generate a QR code that encodes a URL pointing to the card data. A first responder scans the QR code to view the emergency information in a browser without needing a HealthVault account.

---

## Dynamic Emergency Access

Dynamic access allows a third party to request access to a profile's health data. The request goes through a configurable waiting period before approval.

### Configuration options

Each profile can configure emergency access independently:

| Setting | Description |
|---------|-------------|
| `wait_hours` | Hours to delay before auto-approval (gives the owner time to deny) |
| `auto_approve` | Whether requests are auto-approved after the wait period expires |
| `notify_on_request` | Whether the profile owner receives a notification when a request is made |
| `visible_fields` | Which data categories are visible to the requester |

### API endpoints

```
POST   /api/v1/profiles/{profileID}/emergency-access    Configure settings
GET    /api/v1/profiles/{profileID}/emergency-access     View current settings
DELETE /api/v1/profiles/{profileID}/emergency-access     Remove configuration
```

---

## How the Dead Man's Switch Works

The dead man's switch is the core of dynamic emergency access. It ensures that data is only released after a deliberate delay, giving the owner a window to intervene.

### Flow

1. **Token generation** -- The profile owner generates an emergency access token for the profile.
2. **Request** -- A third party submits a request via `POST /api/v1/emergency/request/{token}`. The request enters `pending` status.
3. **Waiting period** -- The system waits for `wait_hours` before taking action. During this time, the owner is notified (if configured).
4. **Owner intervention** -- The owner can approve or deny the request at any time during the waiting period.
5. **Auto-approval** -- If `auto_approve` is enabled and the waiting period expires without owner action, the request is automatically approved.
6. **Access granted** -- Once approved, the requester can view the data categories specified in `visible_fields`.

If `auto_approve` is false and the owner does not respond, the request remains pending indefinitely.

If `wait_hours` is 0 and `auto_approve` is true, access is granted immediately (useful for first-responder scenarios).

---

## What the Emergency Contact Sees

When an emergency access request is approved, the requester sees:

- Only the data categories listed in `visible_fields` -- no more, no less.
- Data is read-only. No modifications can be made.
- Access is time-limited and revocable at any time by the profile owner.
- The requester does not gain access to the profile's encryption keys. Emergency data is served from the pre-encrypted emergency card blob or re-encrypted specifically for the grant.

---

## Revoking Access

### Revoking a pending request

```bash
# Deny a pending request
curl -X POST https://your-host/api/v1/emergency/deny/{requestID} \
  -H "Authorization: Bearer <token>"
```

### Revoking an approved access

- Navigate to the profile's emergency access settings and remove the configuration.
- Or call `DELETE /api/v1/profiles/{profileID}/emergency-access`.
- Revoking deletes the emergency access configuration and invalidates all outstanding tokens.

### Listing pending requests

```bash
curl https://your-host/api/v1/emergency/pending \
  -H "Authorization: Bearer <token>"
```

---

## Security Model

### Trust boundaries

- The emergency card blob is encrypted client-side. The server stores ciphertext only.
- Emergency access tokens are opaque, random identifiers -- they do not contain keys or sensitive data.
- The waiting period provides a dead man's switch: the owner is notified and can deny access before it is granted.
- `visible_fields` restricts exposure to only what the owner has explicitly opted to share.

### Threat mitigations

| Threat | Mitigation |
|--------|------------|
| Stolen emergency token | Configurable wait period + owner notification before access is granted |
| Server compromise | Emergency data is ciphertext; server cannot read it |
| Unauthorized scope expansion | `visible_fields` whitelist enforced server-side |
| Stale access | Time-limited grants; owner can revoke at any time |

For full cryptographic details, see [SECURITY.md](SECURITY.md).
