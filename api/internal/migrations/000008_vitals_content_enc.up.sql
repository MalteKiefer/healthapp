-- Stage 2.0: encrypt vitals content at rest.
-- content_enc holds base64(iv || ciphertext || tag) produced by the client
-- using AES-256-GCM under the profile key. Nullable during lazy backfill;
-- a later migration drops the plaintext columns and enforces NOT NULL.
ALTER TABLE vitals ADD COLUMN content_enc TEXT;
