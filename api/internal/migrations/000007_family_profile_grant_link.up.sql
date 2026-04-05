ALTER TABLE profile_key_grants
  ADD COLUMN via_family_id UUID REFERENCES families(id) ON DELETE SET NULL;

CREATE INDEX idx_profile_key_grants_via_family
  ON profile_key_grants (via_family_id)
  WHERE revoked_at IS NULL;
