-- Stage 2.4: Drop plaintext health-data columns.
-- All rows already have content_enc populated; these columns are no longer read.

BEGIN;

-- 1. vitals
ALTER TABLE vitals
    DROP COLUMN blood_pressure_systolic,
    DROP COLUMN blood_pressure_diastolic,
    DROP COLUMN pulse,
    DROP COLUMN oxygen_saturation,
    DROP COLUMN weight,
    DROP COLUMN height,
    DROP COLUMN body_temperature,
    DROP COLUMN blood_glucose,
    DROP COLUMN respiratory_rate,
    DROP COLUMN waist_circumference,
    DROP COLUMN hip_circumference,
    DROP COLUMN body_fat_percentage,
    DROP COLUMN bmi,
    DROP COLUMN sleep_duration_minutes,
    DROP COLUMN sleep_quality,
    DROP COLUMN device,
    DROP COLUMN notes;
ALTER TABLE vitals ALTER COLUMN content_enc SET NOT NULL;

-- 2. allergies
ALTER TABLE allergies
    DROP COLUMN name,
    DROP COLUMN category,
    DROP COLUMN reaction_type,
    DROP COLUMN severity,
    DROP COLUMN onset_date,
    DROP COLUMN diagnosed_by,
    DROP COLUMN notes,
    DROP COLUMN status;
ALTER TABLE allergies ALTER COLUMN content_enc SET NOT NULL;

-- 3. diagnoses
ALTER TABLE diagnoses
    DROP COLUMN name,
    DROP COLUMN icd10_code,
    DROP COLUMN status,
    DROP COLUMN diagnosed_at,
    DROP COLUMN diagnosed_by,
    DROP COLUMN resolved_at,
    DROP COLUMN notes;
ALTER TABLE diagnoses ALTER COLUMN content_enc SET NOT NULL;

-- 4. diary_events
ALTER TABLE diary_events
    DROP COLUMN title,
    DROP COLUMN event_type,
    DROP COLUMN started_at,
    DROP COLUMN ended_at,
    DROP COLUMN description,
    DROP COLUMN severity,
    DROP COLUMN location,
    DROP COLUMN outcome;
ALTER TABLE diary_events ALTER COLUMN content_enc SET NOT NULL;

-- 5. medical_contacts
ALTER TABLE medical_contacts
    DROP COLUMN name,
    DROP COLUMN specialty,
    DROP COLUMN facility,
    DROP COLUMN phone,
    DROP COLUMN email,
    DROP COLUMN street,
    DROP COLUMN postal_code,
    DROP COLUMN city,
    DROP COLUMN country,
    DROP COLUMN address,
    DROP COLUMN latitude,
    DROP COLUMN longitude,
    DROP COLUMN notes,
    DROP COLUMN is_emergency_contact,
    DROP COLUMN contact_type;
ALTER TABLE medical_contacts ALTER COLUMN content_enc SET NOT NULL;

-- 6. tasks
ALTER TABLE tasks
    DROP COLUMN title,
    DROP COLUMN priority,
    DROP COLUMN notes;
ALTER TABLE tasks ALTER COLUMN content_enc SET NOT NULL;

-- 7. appointments
ALTER TABLE appointments
    DROP COLUMN title,
    DROP COLUMN appointment_type,
    DROP COLUMN location,
    DROP COLUMN preparation_notes,
    DROP COLUMN reminder_days_before,
    DROP COLUMN recurrence;
ALTER TABLE appointments ALTER COLUMN content_enc SET NOT NULL;

-- 8. medications
ALTER TABLE medications
    DROP COLUMN name,
    DROP COLUMN dosage,
    DROP COLUMN unit,
    DROP COLUMN frequency,
    DROP COLUMN route,
    DROP COLUMN prescribed_by,
    DROP COLUMN reason,
    DROP COLUMN notes;
ALTER TABLE medications ALTER COLUMN content_enc SET NOT NULL;

-- 9. medication_intake
ALTER TABLE medication_intake
    DROP COLUMN dose_taken,
    DROP COLUMN skipped_reason,
    DROP COLUMN notes;
ALTER TABLE medication_intake ALTER COLUMN content_enc SET NOT NULL;

-- 10. vaccinations
ALTER TABLE vaccinations
    DROP COLUMN vaccine_name,
    DROP COLUMN trade_name,
    DROP COLUMN manufacturer,
    DROP COLUMN lot_number,
    DROP COLUMN dose_number,
    DROP COLUMN administered_by,
    DROP COLUMN site,
    DROP COLUMN notes;
ALTER TABLE vaccinations ALTER COLUMN content_enc SET NOT NULL;

-- 11. lab_results
ALTER TABLE lab_results
    DROP COLUMN lab_name,
    DROP COLUMN ordered_by,
    DROP COLUMN sample_date,
    DROP COLUMN result_date,
    DROP COLUMN notes;
ALTER TABLE lab_results ALTER COLUMN content_enc SET NOT NULL;

-- 12. lab_values
ALTER TABLE lab_values
    DROP COLUMN marker,
    DROP COLUMN value,
    DROP COLUMN value_text,
    DROP COLUMN unit,
    DROP COLUMN reference_low,
    DROP COLUMN reference_high,
    DROP COLUMN flag;
ALTER TABLE lab_values ALTER COLUMN content_enc SET NOT NULL;

-- 13. symptom_records
ALTER TABLE symptom_records
    DROP COLUMN recorded_at,
    DROP COLUMN trigger_factors,
    DROP COLUMN notes;
ALTER TABLE symptom_records ALTER COLUMN content_enc SET NOT NULL;

-- 14. symptom_entries
ALTER TABLE symptom_entries
    DROP COLUMN symptom_type,
    DROP COLUMN custom_label,
    DROP COLUMN intensity,
    DROP COLUMN body_region,
    DROP COLUMN duration_minutes;
ALTER TABLE symptom_entries ALTER COLUMN content_enc SET NOT NULL;

COMMIT;
