-- Doctor Shares — Temporary access links for doctor visits

CREATE TABLE doctor_shares (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    share_id        TEXT NOT NULL UNIQUE,
    profile_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_by      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_data  TEXT NOT NULL,
    label           TEXT,
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_shares_share_id ON doctor_shares (share_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_shares_profile ON doctor_shares (profile_id, created_at DESC);

CREATE TABLE doctor_share_access_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    share_id    TEXT NOT NULL,
    ip_address  TEXT,
    user_agent  TEXT,
    accessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_share_access_share ON doctor_share_access_log (share_id, accessed_at DESC);

INSERT INTO schema_migrations (version, dirty) VALUES (2, FALSE);
