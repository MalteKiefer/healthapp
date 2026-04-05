DROP INDEX IF EXISTS idx_profile_key_grants_via_family;
ALTER TABLE profile_key_grants DROP COLUMN IF EXISTS via_family_id;
