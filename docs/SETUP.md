# HealthVault Setup Guide

## Prerequisites

- **Docker Engine** 24.0+ with the Compose plugin (`docker compose`)
- A machine with at least 1 GB RAM and 10 GB disk space
- A hostname or domain pointed at your server (or `localhost` for local use)

Verify Docker is installed:

```bash
docker compose version
```

---

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/MalteKiefer/healthapp.git
cd healthvault

# 2. Copy the example environment file
cp .env.example .env

# 3. Edit .env with your secrets
$EDITOR .env

# 4. Run setup
./setup.sh
```

The setup script will start the database, run initial schema migrations, create the admin invite, and bring up the full stack. Check the output for your admin registration link.

---

## Detailed Setup

### 1. Configure `.env`

Copy `.env.example` to `.env` and fill in all required values. Key settings:

| Variable | Description | Example |
|----------|-------------|---------|
| `INSTANCE_HOSTNAME` | Hostname for your instance | `healthvault.home` |
| `REGISTRATION_MODE` | `open`, `invite_only`, or `closed` | `invite_only` |
| `DB_SUPERUSER_PASSWORD` | PostgreSQL superuser password (setup only) | *(generate a strong password)* |
| `DB_PASSWORD` | Application database password | *(generate a strong password)* |
| `REDIS_PASSWORD` | Redis authentication password | *(generate a strong password)* |
| `BACKUP_ENCRYPTION_KEY` | AES-256 key for backups | `openssl rand -base64 32` |
| `ACME_EMAIL` | Email for Let's Encrypt (if using ACME mode) | `you@example.com` |

Generate strong passwords:

```bash
openssl rand -base64 24   # for DB_PASSWORD, REDIS_PASSWORD, etc.
openssl rand -base64 32   # for BACKUP_ENCRYPTION_KEY
```

### 2. Run `setup.sh`

```bash
./setup.sh
```

The script performs the following steps:

1. Verifies Docker Compose is available.
2. Creates `.env` from `.env.example` if it does not exist (and exits for you to edit it).
3. Starts the database and Redis containers.
4. Waits for PostgreSQL to be ready.
5. Runs `healthvault setup` inside the API container (schema migration + admin bootstrap).
6. Starts all remaining services.

### 3. Alternative: Manual Start

If you prefer not to use `setup.sh`:

```bash
docker compose up -d db redis
# Wait for DB to be ready
docker compose run --rm api healthvault setup
docker compose up -d
```

---

## Admin Account Bootstrap

On first run, `healthvault setup` creates an admin invite code. The output will show a registration link:

```
Admin registration link: https://healthvault.home/register?invite=XXXXXX
```

1. Open the link in your browser.
2. Create your admin account with a strong passphrase.
3. Your passphrase generates the encryption keys client-side -- it is never sent to the server.

After registration, you can manage users, invite codes, and system settings from the admin panel.

---

## TLS Configuration

Caddy handles TLS automatically. Three modes are available:

### Mode 1: Internal CA (default)

Self-signed certificate from Caddy's built-in CA. Best for LAN and home servers.

```
tls internal
```

No external connectivity required. Trust the CA on your devices -- see [TLS.md](TLS.md).

### Mode 2: ACME / Let's Encrypt

Automated certificates from Let's Encrypt. Requires port 80 to be reachable from the internet and `INSTANCE_HOSTNAME` to resolve to your server.

Edit `proxy/Caddyfile`: comment out `tls internal` and uncomment the ACME line:

```
tls {$ACME_EMAIL}
```

Set `ACME_EMAIL` in `.env`.

### Mode 3: Custom Certificate

Bring your own certificate and key files.

Edit `proxy/Caddyfile`: comment out `tls internal` and uncomment the custom cert line:

```
tls /custom/server.crt /custom/server.key
```

Mount the certificate files into the proxy container via `docker-compose.yml`.

For detailed TLS management, see [TLS.md](TLS.md).

---

## Post-Setup Verification

After setup completes, verify that all services are running:

```bash
# Check container health
docker compose ps

# Test the health endpoint
curl -k https://localhost/api/v1/health
```

Expected health response:

```json
{
  "status": "ok",
  "database": "connected",
  "redis": "connected"
}
```

### Checklist

- [ ] All 8 containers show `healthy` or `running` status
- [ ] Health endpoint returns `"status": "ok"`
- [ ] Admin registration link works in the browser
- [ ] TLS certificate is served (check browser padlock or `curl -v`)
- [ ] Backup container logs show successful first backup

View logs for any service:

```bash
docker compose logs -f api
docker compose logs -f proxy
docker compose logs -f backup
```
