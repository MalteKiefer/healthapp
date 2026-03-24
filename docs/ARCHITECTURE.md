# HealthVault Architecture

## Overview

HealthVault is a self-hosted, zero-knowledge health data platform. All services run in Docker Compose with two isolated networks. The client performs all encryption and decryption -- the server never sees plaintext health data.

```
                         ┌─────────────────────────────────────────────┐
                         │              frontend network               │
                         │                                             │
  Browser ──────────▶  ┌──────────┐      ┌──────────┐                 │
                       │  Caddy   │─────▶│  React   │                 │
                       │  Proxy   │      │  PWA     │                 │
                       └────┬─────┘      └──────────┘                 │
                            │                                         │
                       ┌────▼─────┐                                   │
                       │  Go API  │                                   │
                       │  Server  │                                   │
                       └────┬─────┘                                   │
                         ┌──┼─────────────────────────────────────────┘
                         │  │       internal network
                         │  │
              ┌──────────┤  ├──────────┐
              │          │  │          │
         ┌────▼────┐  ┌──▼──▼──┐  ┌───▼────┐
         │  Redis  │  │PgBouncer│  │ Backup │
         └─────────┘  └───┬────┘  └───┬────┘
                          │           │
                     ┌────▼───────────▼──┐
                     │    PostgreSQL     │
                     │    (primary)      │
                     └──────────────────┘
```

---

## Docker Services

| # | Service | Image / Build | Role |
|---|---------|---------------|------|
| 1 | **proxy** | `./proxy` (Caddy) | TLS termination, reverse proxy, security headers |
| 2 | **web** | `./web` (Caddy) | Serves the React PWA static assets |
| 3 | **api** | `./api` (Go) | Business logic, REST API, authentication, authorization |
| 4 | **pgbouncer** | `bitnami/pgbouncer:1.23.1` | Connection pooling (transaction mode, 20 default pool size) |
| 5 | **db** | `postgres:16-alpine` | Primary data store -- users, profiles, encrypted health records |
| 6 | **redis** | `redis:7-alpine` | Sessions, JWT denylist, rate limiting, caching |
| 7 | **backup** | `./backup` | Scheduled `pg_dump` with AES-256-CBC encryption and retention cleanup |
| 8 | **backup-verify** | `./backup` (verify) | Weekly automated restore test against a temporary database |

---

## Network Topology

### `internal` (isolated, no external access)

- **db** -- PostgreSQL, reachable only by pgbouncer, backup, backup-verify, and api
- **pgbouncer** -- connection pooler, sits between api and db
- **redis** -- session store and rate limiter
- **backup** -- scheduled dump container
- **backup-verify** -- weekly restore verification
- **api** -- also on this network to reach db, pgbouncer, and redis

### `frontend` (exposed to the host)

- **proxy** -- binds ports 80, 443, 443/udp (HTTP/3) on the host
- **web** -- serves static assets to proxy
- **api** -- receives proxied API requests from proxy

Only the proxy container exposes ports. All other services communicate over internal Docker networks.

---

## Data Flow

### Request Path

```
Browser  ──HTTPS──▶  Caddy Proxy (:443)
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
        /api/*       /cal/*        /*
        /health      /share/*      (static)
            │            │            │
            ▼            ▼            ▼
        Go API       Go API       React PWA
        (:8080)      (:8080)      (web:80)
            │
            ▼
        PgBouncer (:6432)
            │
            ▼
        PostgreSQL (:5432)
```

1. The browser connects to the Caddy proxy over HTTPS (TLS 1.3).
2. Caddy routes `/api/*`, `/health`, `/cal/*`, and `/share/*` to the Go API on port 8080.
3. All other paths are forwarded to the web container serving the React PWA.
4. The API connects to PostgreSQL through PgBouncer (transaction pooling on port 6432).
5. Redis is accessed directly by the API for sessions, rate limits, and the JWT denylist.

---

## Encryption Flow

HealthVault follows a zero-knowledge architecture. The server never possesses decryption keys.

```
  ┌──────────────────────────────────┐
  │            Browser               │
  │                                  │
  │  Passphrase ──┬──▶ PEK          │
  │               │    (AES-256)     │
  │               │                  │
  │               └──▶ Auth Hash ──────▶ Server (Argon2id)
  │                                  │
  │  PEK encrypts private keys      │
  │  Profile Key encrypts records    │
  │                                  │
  │  Plaintext ──▶ Encrypt ──▶ Ciphertext ──▶ API ──▶ DB
  │  Ciphertext ◀── Decrypt ◀── Ciphertext ◀── API ◀── DB
  └──────────────────────────────────┘
```

1. The user enters their passphrase in the browser.
2. Two keys are derived via PBKDF2-SHA256 (600,000 iterations) with separate salts: the **PEK** (Personal Encryption Key) and the **Auth Hash**.
3. The Auth Hash is sent to the server for authentication; the PEK never leaves the browser.
4. Health records are encrypted client-side with the profile's AES-256-GCM key before transmission.
5. The server stores only ciphertext. On read, the browser fetches ciphertext and decrypts locally.

---

## Key Hierarchy Summary

| Key | Algorithm | Purpose |
|-----|-----------|---------|
| **PEK** | PBKDF2 → AES-256-GCM | Encrypts the user's private keys; derived from passphrase |
| **Profile Key** | Random AES-256-GCM | Encrypts all health records within a profile |
| **Identity Keypair** | ECDH P-256 | Key exchange for granting profile access to other users |
| **Signing Keypair** | Ed25519 (reserved) | Future record signing |

Profile keys are shared between users via ECDH key agreement -- the granter and grantee derive a shared secret to wrap/unwrap the profile key. See [SECURITY.md](SECURITY.md) for full details.
