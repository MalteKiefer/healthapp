#!/bin/bash
# Restore plaintext data from backup into current DB
# Run this inside the backup container or where pg_restore is available

set -e

DB_HOST="healthvault-db-1"
PGPASSWORD="03886cc7dda00600fb5aca303a77436ba79d60b8"
DB_USER="postgres"
DB_NAME="healthvault"

PSQL="docker exec healthvault-db-1 env PGPASSWORD=$PGPASSWORD psql -U $DB_USER -d $DB_NAME"

echo "=== Step 1: Create backup_restore schema and restore backup into it ==="

# Create the schema
$PSQL -c "DROP SCHEMA IF EXISTS backup_restore CASCADE; CREATE SCHEMA backup_restore;"

# Restore backup structure into backup_restore schema
# We use pg_restore with --schema-only first, then --data-only
docker exec healthvault-backup-1 pg_restore \
  --no-owner --no-acl \
  --section=pre-data \
  -f /tmp/backup_schema.sql \
  /tmp/backup.dump 2>/dev/null || true

# We need to modify the schema SQL to use backup_restore schema
# Simpler: restore the whole backup into the backup_restore schema using a creative approach
# Use pg_restore to create a complete SQL, modify search_path, pipe to psql

docker exec healthvault-backup-1 sh -c "pg_restore -f /dev/stdout /tmp/backup.dump 2>/dev/null | sed 's/SET search_path/-- &/' | sed '1i SET search_path = backup_restore, public;'" | \
  docker exec -i healthvault-db-1 env PGPASSWORD=$PGPASSWORD psql -U $DB_USER -d $DB_NAME 2>&1 | tail -5

echo "=== Step 2: Update live tables from backup_restore ==="

# Now update each table
$PSQL <<'EOSQL'

-- vitals
UPDATE vitals v SET
  blood_pressure_systolic = b.blood_pressure_systolic,
  blood_pressure_diastolic = b.blood_pressure_diastolic,
  pulse = b.pulse,
  oxygen_saturation = b.oxygen_saturation,
  weight = b.weight,
  height = b.height,
  body_temperature = b.body_temperature,
  blood_glucose = b.blood_glucose,
  respiratory_rate = b.respiratory_rate,
  waist_circumference = b.waist_circumference,
  hip_circumference = b.hip_circumference,
  body_fat_percentage = b.body_fat_percentage,
  bmi = b.bmi,
  sleep_duration_minutes = b.sleep_duration_minutes,
  sleep_quality = b.sleep_quality,
  device = b.device,
  notes = b.notes
FROM backup_restore.vitals b
WHERE v.id = b.id;

EOSQL

echo "Done!"
