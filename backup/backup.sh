#!/bin/sh
set -e

BACKUP_DIR="/backups"
UPLOADS_DIR="/data/uploads"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_BACKUP_FILE="${BACKUP_DIR}/healthvault_db_${TIMESTAMP}.sql.gz.enc"
FILES_BACKUP_FILE="${BACKUP_DIR}/healthvault_files_${TIMESTAMP}.tar.gz.enc"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

echo "[$(date -Iseconds)] Starting backup..."

# ── 1. Database backup ──
echo "[$(date -Iseconds)] Backing up database..."
pg_dump \
    -h "${DB_HOST:-db}" \
    -p "${DB_PORT:-5432}" \
    -U "${DB_USER:-healthvault}" \
    -d "${DB_NAME:-healthvault}" \
    --format=custom \
    --compress=9 \
    | openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass "env:BACKUP_ENCRYPTION_KEY" \
        -out "${DB_BACKUP_FILE}"

# Generate HMAC for integrity verification (authenticated encryption)
# NOTE: We derive a separate HMAC key from the encryption key to avoid
# reusing the same secret for both encryption and authentication.
# A future improvement would be to use a dedicated HMAC secret or switch
# to an AEAD cipher (e.g. aes-256-gcm) that provides built-in authentication.
HMAC_KEY=$(echo -n "${BACKUP_ENCRYPTION_KEY}" | openssl dgst -sha256 | awk '{print $2}')
openssl dgst -sha256 -hmac "${HMAC_KEY}" \
    -out "${DB_BACKUP_FILE}.hmac" "${DB_BACKUP_FILE}"

DB_SIZE=$(stat -c %s "${DB_BACKUP_FILE}" 2>/dev/null || stat -f %z "${DB_BACKUP_FILE}")
DB_CHECKSUM=$(sha256sum "${DB_BACKUP_FILE}" | cut -d' ' -f1)

echo "[$(date -Iseconds)] Database backup: ${DB_BACKUP_FILE} (${DB_SIZE} bytes, SHA256: ${DB_CHECKSUM})"

# ── 2. File uploads backup ──
FILES_SIZE=0
FILES_CHECKSUM="none"
if [ -d "${UPLOADS_DIR}" ] && [ "$(ls -A ${UPLOADS_DIR} 2>/dev/null)" ]; then
    echo "[$(date -Iseconds)] Backing up uploaded files..."
    tar -czf - -C "${UPLOADS_DIR}" . \
        | openssl enc -aes-256-cbc -salt -pbkdf2 \
            -pass "env:BACKUP_ENCRYPTION_KEY" \
            -out "${FILES_BACKUP_FILE}"
    # Generate HMAC for integrity verification (authenticated encryption)
    openssl dgst -sha256 -hmac "${HMAC_KEY}" \
        -out "${FILES_BACKUP_FILE}.hmac" "${FILES_BACKUP_FILE}"
    FILES_SIZE=$(stat -c %s "${FILES_BACKUP_FILE}" 2>/dev/null || stat -f %z "${FILES_BACKUP_FILE}")
    FILES_CHECKSUM=$(sha256sum "${FILES_BACKUP_FILE}" | cut -d' ' -f1)
    echo "[$(date -Iseconds)] Files backup: ${FILES_BACKUP_FILE} (${FILES_SIZE} bytes, SHA256: ${FILES_CHECKSUM})"
else
    echo "[$(date -Iseconds)] No uploaded files to back up, skipping."
fi

TOTAL_SIZE=$((DB_SIZE + FILES_SIZE))

# ── 3. Record heartbeat in database ──
# Validate inputs to prevent SQL injection
if ! echo "${TOTAL_SIZE}" | grep -qE '^[0-9]+$'; then
    echo "ERROR: Invalid backup size value: ${TOTAL_SIZE}"
    exit 1
fi
if ! echo "${DB_CHECKSUM}" | grep -qE '^[a-f0-9]{64}$'; then
    echo "ERROR: Invalid checksum value"
    exit 1
fi

PGPASSWORD="${DB_PASSWORD}" psql \
    -h "${DB_HOST:-db}" \
    -p "${DB_PORT:-5432}" \
    -U "${DB_USER:-healthvault}" \
    -d "${DB_NAME:-healthvault}" \
    -v total_size="${TOTAL_SIZE}" \
    -v checksum="'${DB_CHECKSUM}'" \
    -c "INSERT INTO backup_heartbeat (id, backed_up_at, file_size_bytes, encrypted, checksum_sha256)
        VALUES (gen_random_uuid(), NOW(), :total_size, true, :checksum)
        ON CONFLICT DO NOTHING;" 2>/dev/null || echo "Warning: could not write heartbeat record"

# ── 4. Cleanup old backups ──
echo "[$(date -Iseconds)] Removing backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "healthvault_*.enc" -mtime "+${RETENTION_DAYS}" -delete
find "${BACKUP_DIR}" -name "healthvault_*.enc.hmac" -mtime "+${RETENTION_DAYS}" -delete
find "${BACKUP_DIR}" -name "healthvault_*.rdb" -mtime "+${RETENTION_DAYS}" -delete

# ── 5. Redis state backup ──
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_BACKUP_FILE="${BACKUP_DIR}/healthvault_redis_${TIMESTAMP}.rdb"

echo "[$(date -Iseconds)] Backing up Redis state..."
if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" BGSAVE 2>/dev/null; then
    # Wait for background save to complete (up to 30 seconds)
    WAIT=0
    while [ "${WAIT}" -lt 30 ]; do
        BGSAVE_STATUS=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" INFO persistence 2>/dev/null | grep rdb_bgsave_in_progress | tr -d '\r' | cut -d: -f2)
        if [ "${BGSAVE_STATUS}" = "0" ]; then
            break
        fi
        sleep 1
        WAIT=$((WAIT + 1))
    done
    # Copy the dump file from the Redis data directory
    REDIS_DATA_DIR="${REDIS_DATA_DIR:-/data}"
    if [ -f "${REDIS_DATA_DIR}/dump.rdb" ]; then
        cp "${REDIS_DATA_DIR}/dump.rdb" "${REDIS_BACKUP_FILE}"
        REDIS_SIZE=$(stat -c %s "${REDIS_BACKUP_FILE}" 2>/dev/null || stat -f %z "${REDIS_BACKUP_FILE}")
        echo "[$(date -Iseconds)] Redis backup: ${REDIS_BACKUP_FILE} (${REDIS_SIZE} bytes)"
    else
        echo "[$(date -Iseconds)] Warning: Redis dump.rdb not found at ${REDIS_DATA_DIR}/dump.rdb"
    fi
else
    echo "[$(date -Iseconds)] Warning: Could not connect to Redis, skipping Redis backup"
fi

# ── 6. Off-site backup transfer ──
# TODO: Enable off-site backup transfer to a remote storage provider.
# Uncomment and configure the rclone command below, or replace with your
# preferred transfer tool (aws s3 cp, gsutil cp, etc.).
#
# Prerequisites:
#   - Install rclone: https://rclone.org/install/
#   - Configure a remote: rclone config (e.g. "offsite" pointing to S3/GCS/B2)
#   - Mount the rclone config into the backup container
#
# Example using rclone:
#   OFFSITE_REMOTE="${OFFSITE_REMOTE:-offsite:healthvault-backups}"
#   echo "[$(date -Iseconds)] Transferring backups to off-site storage..."
#   rclone copy "${BACKUP_DIR}/" "${OFFSITE_REMOTE}/$(date +%Y/%m)/" \
#       --include "healthvault_*_${TIMESTAMP}.*" \
#       --transfers 4 \
#       --retries 3 \
#       --log-level INFO
#   echo "[$(date -Iseconds)] Off-site transfer complete"

echo "[$(date -Iseconds)] Backup complete. DB: ${DB_SIZE} bytes, Files: ${FILES_SIZE} bytes, Total: ${TOTAL_SIZE} bytes"
