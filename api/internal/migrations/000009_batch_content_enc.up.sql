-- Stage 2.1 batch: add content_enc to every profile-scoped health entity.
-- Nullable during dual-read/lazy backfill. A later migration drops the
-- plaintext columns and enforces NOT NULL.
ALTER TABLE lab_results        ADD COLUMN content_enc TEXT;
ALTER TABLE lab_values         ADD COLUMN content_enc TEXT;
ALTER TABLE medications        ADD COLUMN content_enc TEXT;
ALTER TABLE medication_intake  ADD COLUMN content_enc TEXT;
ALTER TABLE allergies          ADD COLUMN content_enc TEXT;
ALTER TABLE vaccinations       ADD COLUMN content_enc TEXT;
ALTER TABLE diagnoses          ADD COLUMN content_enc TEXT;
ALTER TABLE diary_events       ADD COLUMN content_enc TEXT;
ALTER TABLE symptom_records    ADD COLUMN content_enc TEXT;
ALTER TABLE symptom_entries    ADD COLUMN content_enc TEXT;
ALTER TABLE medical_contacts   ADD COLUMN content_enc TEXT;
ALTER TABLE tasks              ADD COLUMN content_enc TEXT;
ALTER TABLE appointments       ADD COLUMN content_enc TEXT;
