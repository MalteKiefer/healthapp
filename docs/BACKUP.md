# HealthVault Backup and Restore

## Overview

HealthVault runs automated, encrypted database backups on a configurable schedule. A separate verification container performs weekly restore tests to ensure backup integrity. Because the database stores only ciphertext (zero-knowledge architecture), backups are encrypted at rest by design -- the backup encryption layer adds defense-in-depth for the metadata and schema.

---

## Automatic Backups

The `backup` container runs a `pg_dump` on a fixed interval and encrypts the output with AES-256-CBC.

**Process:**

1. `pg_dump` creates a compressed custom-format dump of the database.
2. The dump is piped through `openssl enc -aes-256-cbc -salt -pbkdf2` using the configured encryption key.
3. The encrypted file is written to the `/backups` volume as `healthvault_YYYYMMDD_HHMMSS.sql.gz.enc`.
4. A SHA-256 checksum and file size are recorded in the `backup_heartbeat` table.
5. Backups older than `BACKUP_RETENTION_DAYS` are deleted.

**Output format:** `healthvault_20260324_030000.sql.gz.enc`

---

## Configuration

Set the following variables in your `.env` file:

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_ENCRYPTION_KEY` | *(required)* | AES-256 key for backup encryption. Generate with `openssl rand -base64 32` |
| `BACKUP_INTERVAL` | `86400` (24h) | Seconds between backup runs |
| `BACKUP_RETENTION_DAYS` | `30` | Days to keep old backup files |
| `VERIFY_INTERVAL` | `604800` (7d) | Seconds between automated restore tests |

Store `BACKUP_ENCRYPTION_KEY` securely. If lost, existing backups cannot be decrypted.

---

## Manual Backup

Trigger a backup at any time through the admin panel or the API:

```bash
# Via API (admin token required)
curl -X POST https://your-host/api/v1/admin/backups/trigger \
  -H "Authorization: Bearer <admin_token>"

# Via Docker directly
docker compose exec backup /backup.sh
```

---

## Restore Procedure

### 1. Decrypt the backup

```bash
openssl enc -aes-256-cbc -d -salt -pbkdf2 \
  -pass "pass:YOUR_BACKUP_ENCRYPTION_KEY" \
  -in healthvault_20260324_030000.sql.gz.enc \
  -out healthvault_restore.sql
```

### 2. Restore into PostgreSQL

```bash
# Stop the API to prevent writes during restore
docker compose stop api pgbouncer

# Restore the dump
docker compose exec -T db pg_restore \
  -U healthvault \
  -d healthvault \
  --clean --if-exists --no-owner --no-privileges \
  < healthvault_restore.sql

# Restart services
docker compose up -d
```

### 3. Verify the restore

```bash
docker compose exec db psql -U healthvault -d healthvault \
  -c "SELECT COUNT(*) FROM users;"
```

---

## Backup Verification

The `backup-verify` container runs an automated restore test on a weekly cycle (configurable via `VERIFY_INTERVAL`).

**Verification steps:**

1. Finds the most recent `.sql.gz.enc` file in the backup volume.
2. Decrypts the backup using the same `BACKUP_ENCRYPTION_KEY`.
3. Creates a temporary database (`healthvault_verify_*`).
4. Runs `pg_restore` into the temporary database.
5. Checks that core tables exist (`users`, `profiles`, `vitals`, `lab_results`, etc.).
6. Validates row counts for critical tables.
7. Drops the temporary database and logs the result to `backup_verification_log`.

Check verification history:

```bash
docker compose exec db psql -U healthvault -d healthvault \
  -c "SELECT verified_at, status, backup_filename, duration_ms
      FROM backup_verification_log ORDER BY verified_at DESC LIMIT 5;"
```

---

## Disaster Recovery

### Full instance recovery from backup

1. Deploy a fresh HealthVault instance (clone repo, copy `.env`).
2. Start only the database: `docker compose up -d db`
3. Wait for PostgreSQL to be ready.
4. Decrypt the backup file (see Restore Procedure above).
5. Restore the dump into the fresh database.
6. Start the full stack: `docker compose up -d`
7. Verify by logging in and checking data integrity.

### Key points

- Backups contain only ciphertext -- a stolen backup without `BACKUP_ENCRYPTION_KEY` yields encrypted data that itself contains only encrypted health records.
- The `BACKUP_ENCRYPTION_KEY` and your `.env` file should be stored in a separate, secure location (e.g., a password manager or offline vault).
- User passphrases are not stored anywhere. Users must know their own passphrases to decrypt their data after a restore.

---

## Monitoring

| What to monitor | How |
|-----------------|-----|
| Last successful backup | Query `backup_heartbeat` for the latest `backed_up_at` timestamp |
| Last verification result | Query `backup_verification_log` for the latest status |
| Backup volume disk usage | `docker compose exec backup du -sh /backups` |
| Backup file count | `docker compose exec backup ls -1 /backups/*.enc \| wc -l` |
