#!/bin/sh
set -e

BACKUP_DIR="/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/healthvault_${TIMESTAMP}.sql.gz.enc"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

echo "[$(date -Iseconds)] Starting backup..."

# Create compressed dump
pg_dump \
    -h "${DB_HOST:-db}" \
    -p "${DB_PORT:-5432}" \
    -U "${DB_USER:-healthvault}" \
    -d "${DB_NAME:-healthvault}" \
    --format=custom \
    --compress=9 \
    | openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass "pass:${BACKUP_ENCRYPTION_KEY}" \
        -out "${BACKUP_FILE}"

BACKUP_SIZE=$(stat -c %s "${BACKUP_FILE}" 2>/dev/null || stat -f %z "${BACKUP_FILE}")
CHECKSUM=$(sha256sum "${BACKUP_FILE}" | cut -d' ' -f1)

echo "[$(date -Iseconds)] Backup complete: ${BACKUP_FILE} (${BACKUP_SIZE} bytes, SHA256: ${CHECKSUM})"

# Record heartbeat in database
PGPASSWORD="${DB_PASSWORD}" psql \
    -h "${DB_HOST:-db}" \
    -p "${DB_PORT:-5432}" \
    -U "${DB_USER:-healthvault}" \
    -d "${DB_NAME:-healthvault}" \
    -c "INSERT INTO backup_heartbeat (id, backed_up_at, file_size_bytes, encrypted, checksum_sha256)
        VALUES (gen_random_uuid(), NOW(), ${BACKUP_SIZE}, true, '${CHECKSUM}')
        ON CONFLICT DO NOTHING;" 2>/dev/null || echo "Warning: could not write heartbeat record"

# Cleanup old backups
echo "[$(date -Iseconds)] Removing backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "healthvault_*.sql.gz.enc" -mtime "+${RETENTION_DAYS}" -delete

echo "[$(date -Iseconds)] Backup job finished."
