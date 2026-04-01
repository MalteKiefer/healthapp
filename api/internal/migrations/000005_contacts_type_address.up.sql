ALTER TABLE medical_contacts
  ADD COLUMN contact_type TEXT NOT NULL DEFAULT 'medical',
  ADD COLUMN street TEXT,
  ADD COLUMN postal_code TEXT,
  ADD COLUMN city TEXT,
  ADD COLUMN country TEXT,
  ADD COLUMN latitude DOUBLE PRECISION,
  ADD COLUMN longitude DOUBLE PRECISION;

UPDATE medical_contacts SET street = address WHERE address IS NOT NULL AND address != '';
