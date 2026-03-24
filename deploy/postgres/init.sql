-- HealthVault — Initial Database Setup
-- Run once on first container start via /docker-entrypoint-initdb.d/

-- Create application user (minimum privilege)
CREATE USER healthvault WITH PASSWORD :'HEALTHVAULT_DB_PASSWORD' LOGIN;

-- Create read-only user for export/reporting
CREATE USER healthvault_readonly WITH PASSWORD :'HEALTHVAULT_DB_READONLY_PASSWORD' LOGIN;

-- Create database
CREATE DATABASE healthvault OWNER healthvault;

-- Connect to the healthvault database
\c healthvault

-- Revoke default public permissions
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO healthvault;
GRANT CREATE ON SCHEMA public TO healthvault;
GRANT USAGE ON SCHEMA public TO healthvault_readonly;

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Grant read-only user SELECT on all future tables
ALTER DEFAULT PRIVILEGES FOR ROLE healthvault IN SCHEMA public
    GRANT SELECT ON TABLES TO healthvault_readonly;
