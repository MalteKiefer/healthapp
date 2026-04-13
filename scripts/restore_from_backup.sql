-- Step 1: Create temp tables matching the backup schema
-- Step 2: We'll COPY data into them from pg_restore output
-- Step 3: UPDATE live tables from temp tables

-- This file handles Step 3 only. Steps 1+2 are done via shell script.

-- ── vitals ──────────────────────────────────────────────────────────
UPDATE vitals v SET
  blood_pressure_systolic = b.blood_pressure_systolic,
  blood_pressure_diastolic = b.blood_pressure_diastolic,
  pulse = b.pulse,
  oxygen_saturation = b.oxygen_saturation,
  weight = b.weight,
  height = b.height,
  body_temperature = b.body_temperature,
  blood_glucose = b.blood_glucose,
  respiratory_rate = b.respiratory_rate,
  waist_circumference = b.waist_circumference,
  hip_circumference = b.hip_circumference,
  body_fat_percentage = b.body_fat_percentage,
  bmi = b.bmi,
  sleep_duration_minutes = b.sleep_duration_minutes,
  sleep_quality = b.sleep_quality,
  device = b.device,
  notes = b.notes
FROM bak_vitals b WHERE v.id = b.id;

-- ── allergies ───────────────────────────────────────────────────────
UPDATE allergies a SET
  name = b.name,
  category = b.category,
  reaction_type = b.reaction_type,
  severity = b.severity,
  onset_date = b.onset_date,
  diagnosed_by = b.diagnosed_by,
  notes = b.notes,
  status = b.status
FROM bak_allergies b WHERE a.id = b.id;

-- ── appointments ────────────────────────────────────────────────────
UPDATE appointments a SET
  title = b.title,
  appointment_type = b.appointment_type,
  location = b.location,
  preparation_notes = b.preparation_notes,
  reminder_days_before = b.reminder_days_before,
  recurrence = b.recurrence
FROM bak_appointments b WHERE a.id = b.id;

-- ── diagnoses ───────────────────────────────────────────────────────
UPDATE diagnoses d SET
  name = b.name,
  icd10_code = b.icd10_code,
  status = b.status,
  diagnosed_at = b.diagnosed_at,
  diagnosed_by = b.diagnosed_by,
  resolved_at = b.resolved_at,
  notes = b.notes
FROM bak_diagnoses b WHERE d.id = b.id;

-- ── diary_events ────────────────────────────────────────────────────
UPDATE diary_events d SET
  title = b.title,
  event_type = b.event_type,
  started_at = b.started_at,
  ended_at = b.ended_at,
  description = b.description,
  severity = b.severity,
  location = b.location,
  outcome = b.outcome
FROM bak_diary_events b WHERE d.id = b.id;

-- ── medical_contacts ────────────────────────────────────────────────
UPDATE medical_contacts c SET
  name = b.name,
  specialty = b.specialty,
  facility = b.facility,
  phone = b.phone,
  email = b.email,
  address = b.address,
  notes = b.notes,
  is_emergency_contact = b.is_emergency_contact,
  contact_type = b.contact_type,
  street = b.street,
  postal_code = b.postal_code,
  city = b.city,
  country = b.country,
  latitude = b.latitude,
  longitude = b.longitude
FROM bak_medical_contacts b WHERE c.id = b.id;

-- ── medications ─────────────────────────────────────────────────────
UPDATE medications m SET
  name = b.name,
  dosage = b.dosage,
  unit = b.unit,
  frequency = b.frequency,
  route = b.route,
  prescribed_by = b.prescribed_by,
  reason = b.reason,
  notes = b.notes
FROM bak_medications b WHERE m.id = b.id;

-- ── medication_intake ───────────────────────────────────────────────
UPDATE medication_intake m SET
  dose_taken = b.dose_taken,
  skipped_reason = b.skipped_reason,
  notes = b.notes
FROM bak_medication_intake b WHERE m.id = b.id;

-- ── vaccinations ────────────────────────────────────────────────────
UPDATE vaccinations v SET
  vaccine_name = b.vaccine_name,
  trade_name = b.trade_name,
  manufacturer = b.manufacturer,
  lot_number = b.lot_number,
  dose_number = b.dose_number,
  administered_by = b.administered_by,
  site = b.site,
  notes = b.notes
FROM bak_vaccinations b WHERE v.id = b.id;

-- ── symptom_records ─────────────────────────────────────────────────
UPDATE symptom_records s SET
  recorded_at = b.recorded_at,
  trigger_factors = b.trigger_factors,
  notes = b.notes
FROM bak_symptom_records b WHERE s.id = b.id;

-- ── symptom_entries ─────────────────────────────────────────────────
UPDATE symptom_entries s SET
  symptom_type = b.symptom_type,
  custom_label = b.custom_label,
  intensity = b.intensity,
  body_region = b.body_region,
  duration_minutes = b.duration_minutes
FROM bak_symptom_entries b WHERE s.id = b.id;

-- ── tasks ───────────────────────────────────────────────────────────
UPDATE tasks t SET
  title = b.title,
  priority = b.priority,
  notes = b.notes
FROM bak_tasks b WHERE t.id = b.id;

-- ── lab_results ─────────────────────────────────────────────────────
UPDATE lab_results l SET
  lab_name = b.lab_name,
  ordered_by = b.ordered_by,
  sample_date = b.sample_date,
  result_date = b.result_date,
  notes = b.notes
FROM bak_lab_results b WHERE l.id = b.id;

-- ── lab_values ──────────────────────────────────────────────────────
UPDATE lab_values l SET
  marker = b.marker,
  value = b.value,
  value_text = b.value_text,
  unit = b.unit,
  reference_low = b.reference_low,
  reference_high = b.reference_high,
  flag = b.flag
FROM bak_lab_values b WHERE l.id = b.id;

-- ── documents: copy filename_enc to filename ────────────────────────
UPDATE documents SET filename = filename_enc WHERE filename IS NULL;
UPDATE documents SET ocr_text = ocr_text_enc WHERE ocr_text IS NULL;

-- ── Clear content_enc on rows that now have plaintext data ──────────
-- (Only clear where we successfully restored plaintext)
UPDATE vitals SET content_enc = NULL WHERE blood_pressure_systolic IS NOT NULL OR pulse IS NOT NULL OR weight IS NOT NULL OR notes IS NOT NULL;
UPDATE allergies SET content_enc = NULL WHERE name IS NOT NULL;
UPDATE appointments SET content_enc = NULL WHERE title IS NOT NULL;
UPDATE diagnoses SET content_enc = NULL WHERE name IS NOT NULL;
UPDATE diary_events SET content_enc = NULL WHERE title IS NOT NULL;
UPDATE medical_contacts SET content_enc = NULL WHERE name IS NOT NULL;
UPDATE medications SET content_enc = NULL WHERE name IS NOT NULL;
UPDATE medication_intake SET content_enc = NULL WHERE dose_taken IS NOT NULL OR skipped_reason IS NOT NULL OR notes IS NOT NULL;
UPDATE vaccinations SET content_enc = NULL WHERE vaccine_name IS NOT NULL;
UPDATE symptom_records SET content_enc = NULL WHERE recorded_at IS NOT NULL;
UPDATE symptom_entries SET content_enc = NULL WHERE symptom_type IS NOT NULL;
UPDATE tasks SET content_enc = NULL WHERE title IS NOT NULL;
UPDATE lab_results SET content_enc = NULL WHERE lab_name IS NOT NULL OR sample_date IS NOT NULL;
UPDATE lab_values SET content_enc = NULL WHERE marker IS NOT NULL;
UPDATE profiles SET content_enc = NULL;
