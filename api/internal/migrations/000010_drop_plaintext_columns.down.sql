-- Stage 2.4 rollback: re-add plaintext columns as nullable.
-- Data is irrecoverably gone; columns are added empty for schema compatibility.

BEGIN;

-- 1. vitals
ALTER TABLE vitals ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE vitals
    ADD COLUMN blood_pressure_systolic INT,
    ADD COLUMN blood_pressure_diastolic INT,
    ADD COLUMN pulse INT,
    ADD COLUMN oxygen_saturation NUMERIC,
    ADD COLUMN weight NUMERIC,
    ADD COLUMN height NUMERIC,
    ADD COLUMN body_temperature NUMERIC,
    ADD COLUMN blood_glucose NUMERIC,
    ADD COLUMN respiratory_rate INT,
    ADD COLUMN waist_circumference NUMERIC,
    ADD COLUMN hip_circumference NUMERIC,
    ADD COLUMN body_fat_percentage NUMERIC,
    ADD COLUMN bmi NUMERIC,
    ADD COLUMN sleep_duration_minutes INT,
    ADD COLUMN sleep_quality INT,
    ADD COLUMN device TEXT,
    ADD COLUMN notes TEXT;

-- 2. allergies
ALTER TABLE allergies ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE allergies
    ADD COLUMN name TEXT,
    ADD COLUMN category TEXT,
    ADD COLUMN reaction_type TEXT,
    ADD COLUMN severity TEXT,
    ADD COLUMN onset_date TIMESTAMPTZ,
    ADD COLUMN diagnosed_by TEXT,
    ADD COLUMN notes TEXT,
    ADD COLUMN status TEXT;

-- 3. diagnoses
ALTER TABLE diagnoses ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE diagnoses
    ADD COLUMN name TEXT,
    ADD COLUMN icd10_code TEXT,
    ADD COLUMN status TEXT,
    ADD COLUMN diagnosed_at TIMESTAMPTZ,
    ADD COLUMN diagnosed_by TEXT,
    ADD COLUMN resolved_at TIMESTAMPTZ,
    ADD COLUMN notes TEXT;

-- 4. diary_events
ALTER TABLE diary_events ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE diary_events
    ADD COLUMN title TEXT,
    ADD COLUMN event_type TEXT,
    ADD COLUMN started_at TIMESTAMPTZ,
    ADD COLUMN ended_at TIMESTAMPTZ,
    ADD COLUMN description TEXT,
    ADD COLUMN severity INT,
    ADD COLUMN location TEXT,
    ADD COLUMN outcome TEXT;

-- 5. medical_contacts
ALTER TABLE medical_contacts ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE medical_contacts
    ADD COLUMN name TEXT,
    ADD COLUMN specialty TEXT,
    ADD COLUMN facility TEXT,
    ADD COLUMN phone TEXT,
    ADD COLUMN email TEXT,
    ADD COLUMN street TEXT,
    ADD COLUMN postal_code TEXT,
    ADD COLUMN city TEXT,
    ADD COLUMN country TEXT,
    ADD COLUMN address TEXT,
    ADD COLUMN latitude NUMERIC,
    ADD COLUMN longitude NUMERIC,
    ADD COLUMN notes TEXT,
    ADD COLUMN is_emergency_contact BOOLEAN,
    ADD COLUMN contact_type TEXT;

-- 6. tasks
ALTER TABLE tasks ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE tasks
    ADD COLUMN title TEXT,
    ADD COLUMN priority TEXT,
    ADD COLUMN notes TEXT;

-- 7. appointments
ALTER TABLE appointments ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE appointments
    ADD COLUMN title TEXT,
    ADD COLUMN appointment_type TEXT,
    ADD COLUMN location TEXT,
    ADD COLUMN preparation_notes TEXT,
    ADD COLUMN reminder_days_before INT[],
    ADD COLUMN recurrence TEXT;

-- 8. medications
ALTER TABLE medications ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE medications
    ADD COLUMN name TEXT,
    ADD COLUMN dosage TEXT,
    ADD COLUMN unit TEXT,
    ADD COLUMN frequency TEXT,
    ADD COLUMN route TEXT,
    ADD COLUMN prescribed_by TEXT,
    ADD COLUMN reason TEXT,
    ADD COLUMN notes TEXT;

-- 9. medication_intake
ALTER TABLE medication_intake ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE medication_intake
    ADD COLUMN dose_taken TEXT,
    ADD COLUMN skipped_reason TEXT,
    ADD COLUMN notes TEXT;

-- 10. vaccinations
ALTER TABLE vaccinations ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE vaccinations
    ADD COLUMN vaccine_name TEXT,
    ADD COLUMN trade_name TEXT,
    ADD COLUMN manufacturer TEXT,
    ADD COLUMN lot_number TEXT,
    ADD COLUMN dose_number INT,
    ADD COLUMN administered_by TEXT,
    ADD COLUMN site TEXT,
    ADD COLUMN notes TEXT;

-- 11. lab_results
ALTER TABLE lab_results ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE lab_results
    ADD COLUMN lab_name TEXT,
    ADD COLUMN ordered_by TEXT,
    ADD COLUMN sample_date TIMESTAMPTZ,
    ADD COLUMN result_date TIMESTAMPTZ,
    ADD COLUMN notes TEXT;

-- 12. lab_values
ALTER TABLE lab_values ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE lab_values
    ADD COLUMN marker TEXT,
    ADD COLUMN value NUMERIC,
    ADD COLUMN value_text TEXT,
    ADD COLUMN unit TEXT,
    ADD COLUMN reference_low NUMERIC,
    ADD COLUMN reference_high NUMERIC,
    ADD COLUMN flag TEXT;

-- 13. symptom_records
ALTER TABLE symptom_records ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE symptom_records
    ADD COLUMN recorded_at TIMESTAMPTZ,
    ADD COLUMN trigger_factors TEXT[],
    ADD COLUMN notes TEXT;

-- 14. symptom_entries
ALTER TABLE symptom_entries ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE symptom_entries
    ADD COLUMN symptom_type TEXT,
    ADD COLUMN custom_label TEXT,
    ADD COLUMN intensity INT,
    ADD COLUMN body_region TEXT,
    ADD COLUMN duration_minutes INT;

COMMIT;
