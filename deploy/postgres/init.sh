#!/bin/bash
set -e

# HealthVault — Initial Database Setup
# Run once on first container start via /docker-entrypoint-initdb.d/
# Uses environment variables passed by Docker Compose.

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create application user
    CREATE USER ${HEALTHVAULT_DB_USER:-healthvault}
        WITH PASSWORD '${HEALTHVAULT_DB_PASSWORD}'
        LOGIN;

    -- Create read-only user for export/reporting
    CREATE USER ${HEALTHVAULT_DB_READONLY_USER:-healthvault_readonly}
        WITH PASSWORD '${HEALTHVAULT_DB_READONLY_PASSWORD:-readonly_change_me}'
        LOGIN;

    -- Revoke default public permissions
    REVOKE ALL ON SCHEMA public FROM PUBLIC;
    GRANT USAGE ON SCHEMA public TO ${HEALTHVAULT_DB_USER:-healthvault};
    GRANT CREATE ON SCHEMA public TO ${HEALTHVAULT_DB_USER:-healthvault};
    GRANT USAGE ON SCHEMA public TO ${HEALTHVAULT_DB_READONLY_USER:-healthvault_readonly};

    -- Enable required extensions
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";

    -- Grant read-only user SELECT on all future tables
    ALTER DEFAULT PRIVILEGES FOR ROLE ${HEALTHVAULT_DB_USER:-healthvault} IN SCHEMA public
        GRANT SELECT ON TABLES TO ${HEALTHVAULT_DB_READONLY_USER:-healthvault_readonly};
EOSQL
