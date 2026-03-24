CREATE TABLE export_schedules (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    profile_ids UUID[] NOT NULL,
    format      TEXT NOT NULL CHECK (format IN ('native', 'json', 'fhir')),
    frequency   TEXT NOT NULL CHECK (frequency IN ('weekly', 'monthly', 'quarterly')),
    last_run_at TIMESTAMPTZ,
    next_run_at TIMESTAMPTZ,
    enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO schema_migrations (version, dirty) VALUES (3, FALSE);
