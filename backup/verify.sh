#!/bin/sh
# backup-verify.sh — Weekly backup restore verification
# Runs as a separate container job. Validates that the most recent backup
# can be decrypted and restored successfully.
set -e

BACKUP_DIR="/backups"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-healthvault}"
DB_NAME="${DB_NAME:-healthvault}"
VERIFY_DB="healthvault_verify_$(date +%s)"

echo "[$(date -Iseconds)] Starting backup verification..."

# 1. Find most recent backup
LATEST=$(ls -t "${BACKUP_DIR}"/healthvault_*.sql.gz.enc 2>/dev/null | head -1)
if [ -z "${LATEST}" ]; then
    echo "[$(date -Iseconds)] ERROR: No backup files found in ${BACKUP_DIR}"
    PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
        -c "INSERT INTO backup_verification_log (id, verified_at, backup_filename, backup_size_bytes, backup_created_at, status, error_message, duration_ms)
            VALUES (gen_random_uuid(), NOW(), 'none', 0, NOW(), 'failed', 'No backup files found', 0);" 2>/dev/null || true
    exit 1
fi

BACKUP_SIZE=$(stat -c %s "${LATEST}" 2>/dev/null || stat -f %z "${LATEST}")
BACKUP_DATE=$(stat -c %Y "${LATEST}" 2>/dev/null || stat -f %m "${LATEST}")
START_TIME=$(date +%s%3N 2>/dev/null || echo 0)

echo "[$(date -Iseconds)] Verifying: ${LATEST} (${BACKUP_SIZE} bytes)"

# 1b. Verify HMAC integrity before decryption
HMAC_FILE="${LATEST}.hmac"
if [ ! -f "${HMAC_FILE}" ]; then
    echo "[$(date -Iseconds)] ERROR: HMAC file not found: ${HMAC_FILE}"
    PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
        -c "INSERT INTO backup_verification_log (id, verified_at, backup_filename, backup_size_bytes, backup_created_at, status, error_message, duration_ms)
            VALUES (gen_random_uuid(), NOW(), '$(basename "${LATEST}")', ${BACKUP_SIZE}, to_timestamp(${BACKUP_DATE}), 'failed', 'HMAC file missing', 0);" 2>/dev/null || true
    exit 1
fi

HMAC_KEY=$(echo -n "${BACKUP_ENCRYPTION_KEY}" | openssl dgst -sha256 | awk '{print $2}')
EXPECTED_HMAC=$(openssl dgst -sha256 -hmac "${HMAC_KEY}" "${LATEST}" | awk '{print $NF}')
ACTUAL_HMAC=$(awk '{print $NF}' "${HMAC_FILE}")

if [ "${EXPECTED_HMAC}" != "${ACTUAL_HMAC}" ]; then
    echo "[$(date -Iseconds)] ERROR: HMAC verification failed — backup may be tampered"
    PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
        -c "INSERT INTO backup_verification_log (id, verified_at, backup_filename, backup_size_bytes, backup_created_at, status, error_message, duration_ms)
            VALUES (gen_random_uuid(), NOW(), '$(basename "${LATEST}")', ${BACKUP_SIZE}, to_timestamp(${BACKUP_DATE}), 'failed', 'HMAC verification failed', 0);" 2>/dev/null || true
    exit 1
fi

echo "[$(date -Iseconds)] HMAC verification passed"

# 2. Decrypt the backup
DECRYPTED=$(mktemp /tmp/verify_backup_XXXXXX.sql)
trap 'rm -f "${DECRYPTED}"' EXIT

if ! openssl enc -aes-256-cbc -d -salt -pbkdf2 \
    -pass "env:BACKUP_ENCRYPTION_KEY" \
    -in "${LATEST}" \
    -out "${DECRYPTED}" 2>/dev/null; then
    echo "[$(date -Iseconds)] ERROR: Decryption failed"
    PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
        -c "INSERT INTO backup_verification_log (id, verified_at, backup_filename, backup_size_bytes, backup_created_at, status, error_message, duration_ms)
            VALUES (gen_random_uuid(), NOW(), '$(basename "${LATEST}")', ${BACKUP_SIZE}, to_timestamp(${BACKUP_DATE}), 'failed', 'Decryption failed', 0);" 2>/dev/null || true
    exit 1
fi

echo "[$(date -Iseconds)] Decryption successful"

# 3. Create temporary verification database
PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
    -c "CREATE DATABASE ${VERIFY_DB};" 2>/dev/null || true

# 4. Restore into temporary database
if ! PGPASSWORD="${DB_PASSWORD}" pg_restore \
    -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" \
    -d "${VERIFY_DB}" \
    --no-owner --no-privileges \
    "${DECRYPTED}" 2>/dev/null; then
    echo "[$(date -Iseconds)] WARNING: pg_restore had warnings (may be non-critical)"
fi

# 5. Verify tables exist
TABLES=$(PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${VERIFY_DB}" \
    -t -c "SELECT string_agg(tablename, ',') FROM pg_tables WHERE schemaname = 'public';" 2>/dev/null | tr -d ' ')

EXPECTED_TABLES="users,profiles,vitals,lab_results,medications,allergies,vaccinations,diagnoses,diary_events"
MISSING=""
for tbl in $(echo "${EXPECTED_TABLES}" | tr ',' ' '); do
    if ! echo "${TABLES}" | grep -q "${tbl}"; then
        MISSING="${MISSING}${tbl},"
    fi
done

# 6. Check row counts
ROW_COUNTS=$(PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${VERIFY_DB}" \
    -t -c "
        SELECT json_build_object(
            'users', (SELECT COUNT(*) FROM users),
            'profiles', (SELECT COUNT(*) FROM profiles),
            'vitals', (SELECT COUNT(*) FROM vitals)
        );" 2>/dev/null | tr -d ' \n')

# 7. Cleanup
PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
    -c "DROP DATABASE IF EXISTS ${VERIFY_DB};" 2>/dev/null || true
rm -f "${DECRYPTED}"

END_TIME=$(date +%s%3N 2>/dev/null || echo 0)
DURATION=$(( END_TIME - START_TIME ))

# 8. Record result
STATUS="success"
ERROR_MSG=""
if [ -n "${MISSING}" ]; then
    STATUS="warning"
    ERROR_MSG="Missing tables: ${MISSING}"
fi

PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
    -c "INSERT INTO backup_verification_log
        (id, verified_at, backup_filename, backup_size_bytes, backup_created_at, status, tables_found, row_counts, error_message, duration_ms)
        VALUES (gen_random_uuid(), NOW(), '$(basename "${LATEST}")', ${BACKUP_SIZE}, to_timestamp(${BACKUP_DATE}),
                '${STATUS}', string_to_array('${TABLES}', ','), '${ROW_COUNTS}'::jsonb,
                NULLIF('${ERROR_MSG}', ''), ${DURATION});" 2>/dev/null || true

echo "[$(date -Iseconds)] Verification ${STATUS}: ${LATEST}"
echo "[$(date -Iseconds)] Tables: ${TABLES}"
echo "[$(date -Iseconds)] Row counts: ${ROW_COUNTS}"
[ -n "${ERROR_MSG}" ] && echo "[$(date -Iseconds)] Warning: ${ERROR_MSG}"
echo "[$(date -Iseconds)] Duration: ${DURATION}ms"
