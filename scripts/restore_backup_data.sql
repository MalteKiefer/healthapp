-- ============================================================================
-- Restore plaintext data from the April 5 backup into the newly-added columns.
-- This creates a temp schema, restores the backup into it, then UPDATEs
-- the live tables using matching IDs.
-- ============================================================================

BEGIN;

-- Create a temporary schema for the backup data
CREATE SCHEMA IF NOT EXISTS backup_restore;

COMMIT;
