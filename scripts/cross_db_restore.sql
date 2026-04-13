-- Cross-database restore: Update main DB from backup DB using dblink
-- Run this against the healthvault database

-- vitals
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
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, blood_pressure_systolic, blood_pressure_diastolic, pulse, oxygen_saturation, weight, height, body_temperature, blood_glucose, respiratory_rate, waist_circumference, hip_circumference, body_fat_percentage, bmi, sleep_duration_minutes, sleep_quality, device, notes FROM vitals')
AS b(id uuid, blood_pressure_systolic int, blood_pressure_diastolic int, pulse int, oxygen_saturation numeric, weight numeric, height numeric, body_temperature numeric, blood_glucose numeric, respiratory_rate int, waist_circumference numeric, hip_circumference numeric, body_fat_percentage numeric, bmi numeric, sleep_duration_minutes int, sleep_quality int, device text, notes text)
WHERE v.id = b.id;

-- allergies
UPDATE allergies a SET
  name = b.name, category = b.category, reaction_type = b.reaction_type,
  severity = b.severity, onset_date = b.onset_date, diagnosed_by = b.diagnosed_by,
  notes = b.notes, status = b.status
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, name, category, reaction_type, severity, onset_date, diagnosed_by, notes, status FROM allergies')
AS b(id uuid, name text, category text, reaction_type text, severity text, onset_date date, diagnosed_by text, notes text, status text)
WHERE a.id = b.id;

-- appointments
UPDATE appointments a SET
  title = b.title, appointment_type = b.appointment_type, location = b.location,
  preparation_notes = b.preparation_notes, reminder_days_before = b.reminder_days_before,
  recurrence = b.recurrence
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, title, appointment_type, location, preparation_notes, reminder_days_before, recurrence FROM appointments')
AS b(id uuid, title text, appointment_type text, location text, preparation_notes text, reminder_days_before int[], recurrence text)
WHERE a.id = b.id;

-- diagnoses
UPDATE diagnoses d SET
  name = b.name, icd10_code = b.icd10_code, status = b.status,
  diagnosed_at = b.diagnosed_at, diagnosed_by = b.diagnosed_by,
  resolved_at = b.resolved_at, notes = b.notes
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, name, icd10_code, status, diagnosed_at, diagnosed_by, resolved_at, notes FROM diagnoses')
AS b(id uuid, name text, icd10_code text, status text, diagnosed_at date, diagnosed_by text, resolved_at date, notes text)
WHERE d.id = b.id;

-- diary_events
UPDATE diary_events d SET
  title = b.title, event_type = b.event_type, started_at = b.started_at,
  ended_at = b.ended_at, description = b.description, severity = b.severity,
  location = b.location, outcome = b.outcome
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, title, event_type, started_at, ended_at, description, severity, location, outcome FROM diary_events')
AS b(id uuid, title text, event_type text, started_at timestamptz, ended_at timestamptz, description text, severity int, location text, outcome text)
WHERE d.id = b.id;

-- medical_contacts
UPDATE medical_contacts c SET
  name = b.name, specialty = b.specialty, facility = b.facility,
  phone = b.phone, email = b.email, address = b.address, notes = b.notes,
  is_emergency_contact = b.is_emergency_contact, contact_type = b.contact_type,
  street = b.street, postal_code = b.postal_code, city = b.city,
  country = b.country, latitude = b.latitude, longitude = b.longitude
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, name, specialty, facility, phone, email, address, notes, is_emergency_contact, contact_type, street, postal_code, city, country, latitude, longitude FROM medical_contacts')
AS b(id uuid, name text, specialty text, facility text, phone text, email text, address text, notes text, is_emergency_contact bool, contact_type text, street text, postal_code text, city text, country text, latitude float8, longitude float8)
WHERE c.id = b.id;

-- medications
UPDATE medications m SET
  name = b.name, dosage = b.dosage, unit = b.unit, frequency = b.frequency,
  route = b.route, prescribed_by = b.prescribed_by, reason = b.reason, notes = b.notes
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, name, dosage, unit, frequency, route, prescribed_by, reason, notes FROM medications')
AS b(id uuid, name text, dosage text, unit text, frequency text, route text, prescribed_by text, reason text, notes text)
WHERE m.id = b.id;

-- medication_intake
UPDATE medication_intake m SET
  dose_taken = b.dose_taken, skipped_reason = b.skipped_reason, notes = b.notes
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, dose_taken, skipped_reason, notes FROM medication_intake')
AS b(id uuid, dose_taken numeric, skipped_reason text, notes text)
WHERE m.id = b.id;

-- vaccinations
UPDATE vaccinations v SET
  vaccine_name = b.vaccine_name, trade_name = b.trade_name, manufacturer = b.manufacturer,
  lot_number = b.lot_number, dose_number = b.dose_number, administered_by = b.administered_by,
  site = b.site, notes = b.notes
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, vaccine_name, trade_name, manufacturer, lot_number, dose_number, administered_by, site, notes FROM vaccinations')
AS b(id uuid, vaccine_name text, trade_name text, manufacturer text, lot_number text, dose_number int, administered_by text, site text, notes text)
WHERE v.id = b.id;

-- symptom_records
UPDATE symptom_records s SET
  recorded_at = b.recorded_at, trigger_factors = b.trigger_factors, notes = b.notes
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, recorded_at, trigger_factors, notes FROM symptom_records')
AS b(id uuid, recorded_at timestamptz, trigger_factors text[], notes text)
WHERE s.id = b.id;

-- symptom_entries
UPDATE symptom_entries s SET
  symptom_type = b.symptom_type, custom_label = b.custom_label, intensity = b.intensity,
  body_region = b.body_region, duration_minutes = b.duration_minutes
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, symptom_type, custom_label, intensity, body_region, duration_minutes FROM symptom_entries')
AS b(id uuid, symptom_type text, custom_label text, intensity int, body_region text, duration_minutes int)
WHERE s.id = b.id;

-- tasks
UPDATE tasks t SET
  title = b.title, priority = b.priority, notes = b.notes
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, title, priority, notes FROM tasks')
AS b(id uuid, title text, priority text, notes text)
WHERE t.id = b.id;

-- lab_results
UPDATE lab_results l SET
  lab_name = b.lab_name, ordered_by = b.ordered_by, sample_date = b.sample_date,
  result_date = b.result_date, notes = b.notes
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, lab_name, ordered_by, sample_date, result_date, notes FROM lab_results')
AS b(id uuid, lab_name text, ordered_by text, sample_date timestamptz, result_date timestamptz, notes text)
WHERE l.id = b.id;

-- lab_values
UPDATE lab_values l SET
  marker = b.marker, value = b.value, value_text = b.value_text, unit = b.unit,
  reference_low = b.reference_low, reference_high = b.reference_high, flag = b.flag
FROM dblink('dbname=healthvault_bak user=postgres password=03886cc7dda00600fb5aca303a77436ba79d60b8', 'SELECT id, marker, value, value_text, unit, reference_low, reference_high, flag FROM lab_values')
AS b(id uuid, marker text, value numeric, value_text text, unit text, reference_low numeric, reference_high numeric, flag text)
WHERE l.id = b.id;

-- documents: copy filename_enc to filename
UPDATE documents SET filename = filename_enc WHERE filename IS NULL;
UPDATE documents SET ocr_text = ocr_text_enc WHERE ocr_text IS NULL;

-- Clear content_enc on all rows (we are removing E2E encryption entirely)
UPDATE vitals SET content_enc = NULL;
UPDATE allergies SET content_enc = NULL;
UPDATE appointments SET content_enc = NULL;
UPDATE diagnoses SET content_enc = NULL;
UPDATE diary_events SET content_enc = NULL;
UPDATE medical_contacts SET content_enc = NULL;
UPDATE medications SET content_enc = NULL;
UPDATE medication_intake SET content_enc = NULL;
UPDATE vaccinations SET content_enc = NULL;
UPDATE symptom_records SET content_enc = NULL;
UPDATE symptom_entries SET content_enc = NULL;
UPDATE tasks SET content_enc = NULL;
UPDATE lab_results SET content_enc = NULL;
UPDATE lab_values SET content_enc = NULL;
UPDATE profiles SET content_enc = NULL;
