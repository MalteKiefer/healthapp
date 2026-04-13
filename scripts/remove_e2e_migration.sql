-- ============================================================================
-- Migration: Remove E2E encryption, restore plaintext columns
-- Date: 2026-04-13
-- Description: Adds back all plaintext columns that were removed during
--   Stage 2.4 E2E encryption migration. Does NOT drop content_enc yet.
-- ============================================================================

BEGIN;

-- ── vitals ──────────────────────────────────────────────────────────
ALTER TABLE vitals
  ADD COLUMN IF NOT EXISTS blood_pressure_systolic integer,
  ADD COLUMN IF NOT EXISTS blood_pressure_diastolic integer,
  ADD COLUMN IF NOT EXISTS pulse integer,
  ADD COLUMN IF NOT EXISTS oxygen_saturation numeric(5,2),
  ADD COLUMN IF NOT EXISTS weight numeric(7,3),
  ADD COLUMN IF NOT EXISTS height numeric(6,1),
  ADD COLUMN IF NOT EXISTS body_temperature numeric(4,1),
  ADD COLUMN IF NOT EXISTS blood_glucose numeric(6,2),
  ADD COLUMN IF NOT EXISTS respiratory_rate integer,
  ADD COLUMN IF NOT EXISTS waist_circumference numeric(5,1),
  ADD COLUMN IF NOT EXISTS hip_circumference numeric(5,1),
  ADD COLUMN IF NOT EXISTS body_fat_percentage numeric(4,1),
  ADD COLUMN IF NOT EXISTS bmi numeric(4,1),
  ADD COLUMN IF NOT EXISTS sleep_duration_minutes integer,
  ADD COLUMN IF NOT EXISTS sleep_quality integer,
  ADD COLUMN IF NOT EXISTS device text,
  ADD COLUMN IF NOT EXISTS notes text;

-- Add sleep quality check if it doesn't exist
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vitals_sleep_quality_check'
  ) THEN
    ALTER TABLE vitals ADD CONSTRAINT vitals_sleep_quality_check
      CHECK (sleep_quality IS NULL OR (sleep_quality >= 1 AND sleep_quality <= 5));
  END IF;
END $$;

-- ── allergies ───────────────────────────────────────────────────────
ALTER TABLE allergies
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS category text,
  ADD COLUMN IF NOT EXISTS reaction_type text,
  ADD COLUMN IF NOT EXISTS severity text,
  ADD COLUMN IF NOT EXISTS onset_date date,
  ADD COLUMN IF NOT EXISTS diagnosed_by text,
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'active';

-- Add check constraints if not exist
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'allergies_category_check') THEN
    ALTER TABLE allergies ADD CONSTRAINT allergies_category_check
      CHECK (category = ANY (ARRAY['medication','food','environmental','contact','other']));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'allergies_reaction_type_check') THEN
    ALTER TABLE allergies ADD CONSTRAINT allergies_reaction_type_check
      CHECK (reaction_type = ANY (ARRAY['anaphylaxis','urticaria','angioedema','respiratory','gastrointestinal','skin','other']));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'allergies_severity_check') THEN
    ALTER TABLE allergies ADD CONSTRAINT allergies_severity_check
      CHECK (severity = ANY (ARRAY['mild','moderate','severe','life_threatening']));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'allergies_status_check') THEN
    ALTER TABLE allergies ADD CONSTRAINT allergies_status_check
      CHECK (status = ANY (ARRAY['active','resolved','unconfirmed']));
  END IF;
END $$;

-- ── appointments ────────────────────────────────────────────────────
ALTER TABLE appointments
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS appointment_type text,
  ADD COLUMN IF NOT EXISTS location text,
  ADD COLUMN IF NOT EXISTS preparation_notes text,
  ADD COLUMN IF NOT EXISTS reminder_days_before integer[],
  ADD COLUMN IF NOT EXISTS recurrence text DEFAULT 'none';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'appointments_appointment_type_check') THEN
    ALTER TABLE appointments ADD CONSTRAINT appointments_appointment_type_check
      CHECK (appointment_type = ANY (ARRAY['examination','surgery','vaccination','follow_up','lab','specialist','general_practice','therapy','other']));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'appointments_recurrence_check') THEN
    ALTER TABLE appointments ADD CONSTRAINT appointments_recurrence_check
      CHECK (recurrence = ANY (ARRAY['none','weekly','monthly','quarterly','yearly','custom']));
  END IF;
END $$;

-- ── diagnoses ───────────────────────────────────────────────────────
ALTER TABLE diagnoses
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS icd10_code text,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS diagnosed_at date,
  ADD COLUMN IF NOT EXISTS diagnosed_by text,
  ADD COLUMN IF NOT EXISTS resolved_at date,
  ADD COLUMN IF NOT EXISTS notes text;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'diagnoses_status_check') THEN
    ALTER TABLE diagnoses ADD CONSTRAINT diagnoses_status_check
      CHECK (status = ANY (ARRAY['active','resolved','chronic','in_remission','suspected']));
  END IF;
END $$;

-- ── diary_events ────────────────────────────────────────────────────
ALTER TABLE diary_events
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS event_type text,
  ADD COLUMN IF NOT EXISTS started_at timestamp with time zone,
  ADD COLUMN IF NOT EXISTS ended_at timestamp with time zone,
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS severity integer,
  ADD COLUMN IF NOT EXISTS location text,
  ADD COLUMN IF NOT EXISTS outcome text;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'diary_events_event_type_check') THEN
    ALTER TABLE diary_events ADD CONSTRAINT diary_events_event_type_check
      CHECK (event_type = ANY (ARRAY['accident','illness','surgery','hospital_stay','emergency','doctor_visit','vaccination','medication_change','symptom','other']));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'diary_events_severity_check') THEN
    ALTER TABLE diary_events ADD CONSTRAINT diary_events_severity_check
      CHECK (severity IS NULL OR (severity >= 1 AND severity <= 10));
  END IF;
END $$;

-- ── medical_contacts ────────────────────────────────────────────────
ALTER TABLE medical_contacts
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS specialty text,
  ADD COLUMN IF NOT EXISTS facility text,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS email text,
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS is_emergency_contact boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS contact_type text DEFAULT 'medical',
  ADD COLUMN IF NOT EXISTS street text,
  ADD COLUMN IF NOT EXISTS postal_code text,
  ADD COLUMN IF NOT EXISTS city text,
  ADD COLUMN IF NOT EXISTS country text,
  ADD COLUMN IF NOT EXISTS latitude double precision,
  ADD COLUMN IF NOT EXISTS longitude double precision;

-- ── medications ─────────────────────────────────────────────────────
ALTER TABLE medications
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS dosage text,
  ADD COLUMN IF NOT EXISTS unit text,
  ADD COLUMN IF NOT EXISTS frequency text,
  ADD COLUMN IF NOT EXISTS route text,
  ADD COLUMN IF NOT EXISTS prescribed_by text,
  ADD COLUMN IF NOT EXISTS reason text,
  ADD COLUMN IF NOT EXISTS notes text;

-- ── medication_intake ───────────────────────────────────────────────
ALTER TABLE medication_intake
  ADD COLUMN IF NOT EXISTS dose_taken numeric(8,3),
  ADD COLUMN IF NOT EXISTS skipped_reason text,
  ADD COLUMN IF NOT EXISTS notes text;

-- ── vaccinations ────────────────────────────────────────────────────
ALTER TABLE vaccinations
  ADD COLUMN IF NOT EXISTS vaccine_name text,
  ADD COLUMN IF NOT EXISTS trade_name text,
  ADD COLUMN IF NOT EXISTS manufacturer text,
  ADD COLUMN IF NOT EXISTS lot_number text,
  ADD COLUMN IF NOT EXISTS dose_number integer,
  ADD COLUMN IF NOT EXISTS administered_by text,
  ADD COLUMN IF NOT EXISTS site text,
  ADD COLUMN IF NOT EXISTS notes text;

-- ── symptom_records ─────────────────────────────────────────────────
ALTER TABLE symptom_records
  ADD COLUMN IF NOT EXISTS recorded_at timestamp with time zone,
  ADD COLUMN IF NOT EXISTS trigger_factors text[],
  ADD COLUMN IF NOT EXISTS notes text;

-- ── symptom_entries ─────────────────────────────────────────────────
ALTER TABLE symptom_entries
  ADD COLUMN IF NOT EXISTS symptom_type text,
  ADD COLUMN IF NOT EXISTS custom_label text,
  ADD COLUMN IF NOT EXISTS intensity integer,
  ADD COLUMN IF NOT EXISTS body_region text,
  ADD COLUMN IF NOT EXISTS duration_minutes integer;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'symptom_entries_body_region_check') THEN
    ALTER TABLE symptom_entries ADD CONSTRAINT symptom_entries_body_region_check
      CHECK (body_region IS NULL OR body_region = ANY (ARRAY['head','neck','chest','abdomen','back','left_arm','right_arm','left_leg','right_leg','general']));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'symptom_entries_intensity_check') THEN
    ALTER TABLE symptom_entries ADD CONSTRAINT symptom_entries_intensity_check
      CHECK (intensity >= 0 AND intensity <= 10);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'symptom_entries_symptom_type_check') THEN
    ALTER TABLE symptom_entries ADD CONSTRAINT symptom_entries_symptom_type_check
      CHECK (symptom_type = ANY (ARRAY['pain','headache','nausea','fatigue','dizziness','shortness_of_breath','anxiety','mood','sleep_quality','appetite','custom']));
  END IF;
END $$;

-- ── tasks ───────────────────────────────────────────────────────────
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS priority text DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS notes text;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tasks_priority_check') THEN
    ALTER TABLE tasks ADD CONSTRAINT tasks_priority_check
      CHECK (priority = ANY (ARRAY['low','normal','high','urgent']));
  END IF;
END $$;

-- ── lab_results ─────────────────────────────────────────────────────
ALTER TABLE lab_results
  ADD COLUMN IF NOT EXISTS lab_name text,
  ADD COLUMN IF NOT EXISTS ordered_by text,
  ADD COLUMN IF NOT EXISTS sample_date timestamp with time zone,
  ADD COLUMN IF NOT EXISTS result_date timestamp with time zone,
  ADD COLUMN IF NOT EXISTS notes text;

-- ── lab_values ──────────────────────────────────────────────────────
ALTER TABLE lab_values
  ADD COLUMN IF NOT EXISTS marker text,
  ADD COLUMN IF NOT EXISTS value numeric(12,4),
  ADD COLUMN IF NOT EXISTS value_text text,
  ADD COLUMN IF NOT EXISTS unit text,
  ADD COLUMN IF NOT EXISTS reference_low numeric(12,4),
  ADD COLUMN IF NOT EXISTS reference_high numeric(12,4),
  ADD COLUMN IF NOT EXISTS flag text;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'lab_values_flag_check') THEN
    ALTER TABLE lab_values ADD CONSTRAINT lab_values_flag_check
      CHECK (flag IS NULL OR flag = ANY (ARRAY['normal','low','high','critical']));
  END IF;
END $$;

-- ── documents: rename filename_enc -> filename, ocr_text_enc -> ocr_text ──
-- We add new columns rather than rename to avoid breaking things
ALTER TABLE documents
  ADD COLUMN IF NOT EXISTS filename text,
  ADD COLUMN IF NOT EXISTS ocr_text text;

-- ── Make content_enc nullable on all tables (was NOT NULL) ──────────
ALTER TABLE vitals ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE allergies ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE appointments ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE diagnoses ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE diary_events ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE medical_contacts ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE medications ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE medication_intake ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE vaccinations ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE symptom_records ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE symptom_entries ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE tasks ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE lab_results ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE lab_values ALTER COLUMN content_enc DROP NOT NULL;
ALTER TABLE documents ALTER COLUMN filename_enc DROP NOT NULL;

-- ── profiles: make content_enc nullable (already is) and remove rotation fields later ──

COMMIT;
