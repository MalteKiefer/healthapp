# HealthVault

**Self-hosted, zero-knowledge health data platform.**

Take full ownership of your family's health records with end-to-end encryption, offline access, and no third-party dependencies.

---

## Features

- **Zero-knowledge encryption** -- your data is encrypted client-side before it ever reaches the server
- **Multi-user with family sharing** -- invite family members and share records securely
- **13 health modules** -- vitals, labs, medications, allergies, immunizations, conditions, procedures, appointments, contacts, tasks, symptoms, diary, and emergency info
- **ICS calendar feeds** -- subscribe to appointments and medication schedules from any calendar app
- **FHIR R4 export** -- export your records in the interoperable FHIR R4 format
- **Emergency access** -- grant time-limited read access to first responders or physicians
- **Offline PWA** -- install as a progressive web app and access your data without an internet connection
- **Dark mode** -- full light/dark theme support
- **EN/DE localization** -- English and German interfaces via i18next

---

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/YOUR_USER/healthvault.git
cd healthvault

# 2. Copy the example environment file
cp .env.example .env

# 3. Edit .env with your secrets and configuration
$EDITOR .env

# 4. Launch everything
./setup.sh          # or: docker compose up -d
```

The app will be available behind the Caddy reverse proxy on the port you configured in `.env`.

---

## Architecture

```
┌──────────┐      ┌──────────┐      ┌────────────┐
│  Caddy   │─────▶│  Go API  │─────▶│ PostgreSQL │
│  Proxy   │      │  Server  │      └────────────┘
└──────────┘      └────┬─────┘
                       │           ┌────────────┐
┌──────────┐           └──────────▶│   Redis    │
│ React    │                       └────────────┘
│ PWA      │
└──────────┘
```

Everything runs in Docker Compose. Caddy terminates TLS and proxies requests to the Go API and serves the React PWA static assets. PostgreSQL stores persistent data (with pgbouncer for connection pooling), and Redis handles sessions, caching, and rate limiting.

---

## Tech Stack

| Layer      | Technology                                                      |
|------------|-----------------------------------------------------------------|
| **Backend**  | Go 1.22, chi router, pgx (PostgreSQL driver), Redis, JWT RS256, Argon2id password hashing |
| **Frontend** | React 18, TypeScript, Vite, TanStack Query, Recharts, Zustand, i18next |
| **Infra**    | Docker Compose, Caddy, PostgreSQL, pgbouncer, Redis             |
| **Backup**   | Encrypted backup container with scheduled dumps                 |

---

## API Overview

All endpoints live under `/api/v1`. A quick health check is available at:

```
GET /api/v1/health
```

Modules exposed through the API include authentication, user profiles, vitals, labs, medications, allergies, immunizations, conditions, procedures, appointments, contacts, tasks, symptoms, diary, emergency access, family sharing, FHIR export, notifications, webhooks, search, admin, and 2FA/TOTP management.

---

## Security

| Measure                  | Details                                                        |
|--------------------------|----------------------------------------------------------------|
| Zero-knowledge encryption | Client-side encryption; the server never sees plaintext health data |
| Password hashing          | Argon2id with tuned memory/time/parallelism parameters        |
| Authentication tokens     | JWT signed with RS256 (asymmetric keys)                       |
| Two-factor authentication | TOTP-based 2FA (RFC 6238)                                     |
| Rate limiting             | Redis-backed per-IP and per-user rate limits                  |
| Backups                   | Encrypted database backups on a configurable schedule         |

---

## Development

Start the development environment with hot reload for both the API and the frontend:

```bash
docker compose -f docker-compose.dev.yml up
```

This mounts source directories into the containers so changes are picked up automatically. The API uses a dev Dockerfile with live reload, and Vite serves the frontend with HMR.

---

## License

This project is not yet licensed. Add a `LICENSE` file to declare your terms.
