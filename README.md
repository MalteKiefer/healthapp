# HealthVault

[![Donate](https://img.shields.io/liberapay/receives/beli3ver.svg?logo=liberapay)](https://de.liberapay.com/beli3ver)

**Self-hosted, zero-knowledge health data platform.**

Take full ownership of your family's health records with end-to-end encryption, offline access, and no third-party dependencies.

## Features

- **Zero-knowledge encryption** -- your data is encrypted client-side before it ever reaches the server
- **Multi-user with family sharing** -- invite family members and share records securely
- **13 health modules** -- vitals, labs, medications, allergies, immunizations, conditions, procedures, appointments, contacts, tasks, symptoms, diary, and emergency info
- **Lab trend visualization** -- track lab markers over time with interactive charts and statistical analysis
- **ICS calendar feeds** -- subscribe to appointments and medication schedules from any calendar app
- **FHIR R4 export** -- export your records in the interoperable FHIR R4 format
- **Emergency access** -- grant time-limited read access to first responders or physicians
- **Offline PWA** -- install as a progressive web app and access your data without an internet connection
- **Dark mode** -- full light/dark theme support
- **EN/DE localization** -- English and German interfaces via i18next

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/MalteKiefer/healthapp.git
cd healthapp

# 2. Copy the example environment file
cp .env.example .env

# 3. Edit .env with your secrets and configuration
$EDITOR .env

# 4. Run the setup script (installs dependencies, generates keys, etc.)
./setup.sh

# 5. Launch everything
docker compose up -d
```

After startup, the **API** is available at `127.0.0.1:3101` and the **Web UI** at `127.0.0.1:3100`. Both bind to localhost only -- you need a reverse proxy in front to handle TLS and public access.

## Architecture

```
                          ┌────────────┐
  ┌──────────────┐        │ PostgreSQL │
  │ Reverse      │  ┌────▶│            │
  │ Proxy        │  │     └────────────┘
  │ (your choice)│  │
  └──┬───────┬───┘  │     ┌────────────┐
     │       │      │  ┌──▶│   Redis    │
     │       │      │  │  └────────────┘
     ▼       ▼      │  │
  ┌──────┐ ┌────────┴──┴┐
  │ Web  │ │  Go API    │
  │ :3100│ │  :3101     │
  └──────┘ └────────────┘
```

HealthVault runs as a set of Docker containers. You bring your own reverse proxy (Caddy, Nginx, Apache, or Traefik) to terminate TLS and route traffic. The Web container serves the React PWA as static files. The API container runs the Go backend. PostgreSQL stores persistent data (with PgBouncer for connection pooling), and Redis handles sessions, caching, and rate limiting.

## Reverse Proxy Setup

HealthVault exposes two services on localhost:

| Service | Address | Purpose |
|---|---|---|
| Web (frontend) | `127.0.0.1:3100` | React PWA static files |
| API (backend) | `127.0.0.1:3101` | REST API, health check at `/health` |

Your reverse proxy must route:
- `/api/*` and `/health` to the **API** (`127.0.0.1:3101`)
- `/cal/*` to the **API** (calendar feed endpoints)
- Everything else to the **Web** (`127.0.0.1:3100`)

### Caddy

```
health.example.com {
    handle /api/* {
        reverse_proxy 127.0.0.1:3101
    }

    handle /health {
        reverse_proxy 127.0.0.1:3101
    }

    handle /cal/* {
        reverse_proxy 127.0.0.1:3101
    }

    handle {
        reverse_proxy 127.0.0.1:3100
    }
}
```

Caddy handles TLS automatically via Let's Encrypt. No further configuration needed.

### Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name health.example.com;

    ssl_certificate     /etc/letsencrypt/live/health.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/health.example.com/privkey.pem;
    ssl_protocols       TLSv1.3;

    # API routes
    location /api/ {
        proxy_pass http://127.0.0.1:3101;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /health {
        proxy_pass http://127.0.0.1:3101;
    }

    location /cal/ {
        proxy_pass http://127.0.0.1:3101;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Frontend (everything else)
    location / {
        proxy_pass http://127.0.0.1:3100;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTP -> HTTPS redirect
server {
    listen 80;
    server_name health.example.com;
    return 301 https://$host$request_uri;
}
```

Obtain certificates with [certbot](https://certbot.eff.org/): `certbot certonly --nginx -d health.example.com`

### Apache

```apache
<VirtualHost *:443>
    ServerName health.example.com

    SSLEngine on
    SSLCertificateFile    /etc/letsencrypt/live/health.example.com/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/health.example.com/privkey.pem
    SSLProtocol           -all +TLSv1.3

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"

    # API routes
    ProxyPass        /api/ http://127.0.0.1:3101/api/
    ProxyPassReverse /api/ http://127.0.0.1:3101/api/

    ProxyPass        /health http://127.0.0.1:3101/health
    ProxyPassReverse /health http://127.0.0.1:3101/health

    ProxyPass        /cal/ http://127.0.0.1:3101/cal/
    ProxyPassReverse /cal/ http://127.0.0.1:3101/cal/

    # Frontend (everything else)
    ProxyPass        / http://127.0.0.1:3100/
    ProxyPassReverse / http://127.0.0.1:3100/
</VirtualHost>

<VirtualHost *:80>
    ServerName health.example.com
    Redirect permanent / https://health.example.com/
</VirtualHost>
```

Enable required modules: `a2enmod proxy proxy_http ssl headers`

### Traefik

Add labels to the `api` and `web` services in a `docker-compose.override.yml`:

```yaml
services:
  web:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.healthvault-web.rule=Host(`health.example.com`)"
      - "traefik.http.routers.healthvault-web.entrypoints=websecure"
      - "traefik.http.routers.healthvault-web.tls.certresolver=letsencrypt"
      - "traefik.http.routers.healthvault-web.priority=1"
      - "traefik.http.services.healthvault-web.loadbalancer.server.port=80"
    networks:
      - frontend
      - traefik

  api:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.healthvault-api.rule=Host(`health.example.com`) && (PathPrefix(`/api`) || PathPrefix(`/health`) || PathPrefix(`/cal`))"
      - "traefik.http.routers.healthvault-api.entrypoints=websecure"
      - "traefik.http.routers.healthvault-api.tls.certresolver=letsencrypt"
      - "traefik.http.routers.healthvault-api.priority=2"
      - "traefik.http.services.healthvault-api.loadbalancer.server.port=8080"
    networks:
      - internal
      - frontend
      - traefik

networks:
  traefik:
    external: true
```

This assumes you have a Traefik instance running with a `traefik` network and a `letsencrypt` certificate resolver configured.

## Tech Stack

| Layer | Technology |
|---|---|
| **Backend** | Go 1.26.1, chi router, pgx (PostgreSQL driver), Redis, JWT RS256, Argon2id |
| **Frontend** | React 19, TypeScript, Vite, TanStack Query, Recharts, Zustand, i18next |
| **Database** | PostgreSQL 16, PgBouncer (connection pooling), Redis 7 |
| **Backup** | Encrypted backup container with scheduled dumps and verification |

## API Overview

All endpoints live under `/api/v1`. Health check:

```
GET /health
```

Modules: authentication, user profiles, vitals, labs (with trends), medications, allergies, immunizations, conditions, procedures, appointments, contacts, tasks, symptoms, diary, emergency access, family sharing, FHIR export, notifications, webhooks, search, admin, and TOTP 2FA.

## Security

| Measure | Details |
|---|---|
| Zero-knowledge encryption | Client-side encryption; the server never sees plaintext health data |
| Password hashing | Argon2id with tuned memory/time/parallelism parameters |
| Authentication tokens | JWT signed with RS256 (asymmetric keys) |
| Two-factor authentication | TOTP-based 2FA (RFC 6238) |
| Rate limiting | Redis-backed per-IP and per-user rate limits |
| Backups | AES-256 encrypted database backups on a configurable schedule |

## Development

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

This mounts source directories into the containers for hot reload. The API uses live reload and Vite serves the frontend with HMR.

## License

[MIT](LICENSE)
