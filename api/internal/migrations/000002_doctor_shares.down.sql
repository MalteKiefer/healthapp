DROP TABLE IF EXISTS doctor_share_access_log CASCADE;
DROP TABLE IF EXISTS doctor_shares CASCADE;
DELETE FROM schema_migrations WHERE version = 2;
