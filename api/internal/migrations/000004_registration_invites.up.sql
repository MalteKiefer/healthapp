CREATE TABLE registration_invites (
    token       TEXT PRIMARY KEY,
    email       TEXT,
    note        TEXT,
    created_by  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    used_at     TIMESTAMPTZ,
    used_by     UUID REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_reg_invites_unused ON registration_invites (created_at DESC) WHERE used_at IS NULL;
