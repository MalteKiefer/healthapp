# HealthVault Upgrade Guide

## Standard Update

Pull the latest images and restart all services:

```bash
cd /path/to/healthvault
git pull
docker compose build
docker compose up -d
```

If you are running from pre-built images:

```bash
docker compose pull
docker compose up -d
```

Docker Compose performs a rolling restart. Services with unchanged images are not restarted.

---

## Schema Migrations

The API server checks the database schema version on startup and applies any pending migrations automatically.

### How it works

1. On startup, the API reads the current schema version from the database.
2. If the running application version requires a newer schema, migrations are applied sequentially.
3. If the schema is already up to date, the API starts normally.
4. If the schema is newer than the application expects (e.g., after a rollback), the API refuses to start and logs an error.

### Safety guarantees

- Migrations run inside a transaction. If any step fails, the entire migration is rolled back.
- The API will not start if the schema version does not match, preventing data corruption from version mismatches.
- Migration status is logged to stdout -- check `docker compose logs api` after an upgrade.

---

## Pre-Migration Backup

Always create a backup before upgrading, especially for releases that include schema changes.

### Automatic backup

If the backup container is running, you already have scheduled backups. Verify the most recent backup:

```bash
docker compose exec db psql -U healthvault -d healthvault \
  -c "SELECT backed_up_at, file_size_bytes FROM backup_heartbeat ORDER BY backed_up_at DESC LIMIT 1;"
```

### Manual backup before upgrade

```bash
# Trigger an immediate backup
docker compose exec backup /backup.sh

# Or via the admin API
curl -X POST https://your-host/api/v1/admin/backups/trigger \
  -H "Authorization: Bearer <admin_token>"
```

Wait for the backup to complete before proceeding with the upgrade.

---

## CLI Migration Commands

The API binary includes built-in migration management:

```bash
# Check current schema version
docker compose run --rm api healthvault migrate status

# Apply all pending migrations
docker compose run --rm api healthvault migrate up

# Roll back the last migration
docker compose run --rm api healthvault migrate down

# Migrate to a specific version
docker compose run --rm api healthvault migrate to <version>
```

In normal operation, you do not need to run these manually -- the API applies migrations on startup. These commands are useful for debugging or controlled rollouts.

---

## Breaking Changes

Releases that contain breaking changes follow this format in the release notes:

```
## Breaking Changes

### vX.Y.Z

- **Migration required:** Brief description of the schema change.
- **Config change:** `NEW_VARIABLE` added to `.env.example` -- copy it to your `.env`.
- **Action required:** Description of any manual steps.
```

Before upgrading across multiple versions, read the release notes for every version in between to identify cumulative breaking changes.

---

## Rollback Procedure

If an upgrade causes issues, roll back to the previous version.

### 1. Stop the current deployment

```bash
docker compose down
```

### 2. Restore the previous application version

```bash
# If using git
git checkout <previous-tag>
docker compose build
```

### 3. Restore the database (if schema changed)

If the upgrade applied schema migrations, you must restore the database from the pre-upgrade backup:

```bash
# Decrypt the backup
openssl enc -aes-256-cbc -d -salt -pbkdf2 \
  -pass "pass:YOUR_BACKUP_ENCRYPTION_KEY" \
  -in /path/to/pre-upgrade-backup.sql.gz.enc \
  -out restore.sql

# Start only the database
docker compose up -d db
# Wait for it to be ready

# Restore
docker compose exec -T db pg_restore \
  -U healthvault -d healthvault \
  --clean --if-exists --no-owner --no-privileges \
  < restore.sql
```

### 4. Start the previous version

```bash
docker compose up -d
```

### 5. Verify

```bash
docker compose ps
curl -k https://localhost/api/v1/health
```

---

## Upgrade Checklist

- [ ] Read the release notes for all versions between your current and target version
- [ ] Verify backup is recent (or trigger a manual backup)
- [ ] Pull and build the new images
- [ ] Run `docker compose up -d`
- [ ] Check `docker compose logs api` for migration output
- [ ] Verify the health endpoint returns `"status": "ok"`
- [ ] Test core functionality (login, view records)
- [ ] Confirm backup container is still running normally

---

## Version Pinning

To pin to a specific release, check out the corresponding git tag:

```bash
git checkout v1.2.3
docker compose build
docker compose up -d
```

This ensures reproducible deployments and makes rollbacks straightforward.
