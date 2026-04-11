/// Per-entity list of field names whose values must be encrypted into
/// `content_enc` before a row is written to the server.
///
/// Kept in sync with `web/src/api/*.ts` CONTENT_FIELDS constants. Any
/// change here must match the corresponding web constants or cross-client
/// reads will return blanks.
library;

/// Map from `entityType` (the AAD entity string — same one used for
/// row decryption) to the ordered list of content field keys.
///
/// Fields listed here are:
///   1. stripped from the structural (plaintext) payload before POST/PATCH,
///   2. serialized into a JSON object and encrypted into `content_enc`.
const Map<String, List<String>> kContentFields = <String, List<String>>{
  'vitals': [
    'blood_pressure_systolic',
    'blood_pressure_diastolic',
    'pulse',
    'oxygen_saturation',
    'weight',
    'height',
    'body_temperature',
    'blood_glucose',
    'respiratory_rate',
    'waist_circumference',
    'hip_circumference',
    'body_fat_percentage',
    'bmi',
    'sleep_duration_minutes',
    'sleep_quality',
    'device',
    'notes',
  ],
  'medications': [
    'name',
    'dosage',
    'unit',
    'frequency',
    'route',
    'prescribed_by',
    'reason',
    'notes',
  ],
  'medication_intake': [
    'dose_taken',
    'skipped_reason',
    'notes',
  ],
  'appointments': [
    'title',
    'appointment_type',
    'location',
    'preparation_notes',
    'reminder_days_before',
    'recurrence',
  ],
  'allergies': [
    'name',
    'category',
    'reaction_type',
    'severity',
    'onset_date',
    'diagnosed_by',
    'notes',
    'status',
  ],
  'diagnoses': [
    'name',
    'icd10_code',
    'status',
    'diagnosed_at',
    'diagnosed_by',
    'resolved_at',
    'notes',
  ],
  'vaccinations': [
    'vaccine_name',
    'trade_name',
    'manufacturer',
    'lot_number',
    'dose_number',
    'administered_by',
    'site',
    'notes',
  ],
  'contacts': [
    'name',
    'specialty',
    'facility',
    'phone',
    'email',
    'street',
    'postal_code',
    'city',
    'country',
    'address',
    'latitude',
    'longitude',
    'notes',
    'is_emergency_contact',
    'contact_type',
  ],
  'diary': [
    'title',
    'event_type',
    'started_at',
    'ended_at',
    'description',
    'severity',
    'location',
    'outcome',
  ],
  'symptoms': [
    'recorded_at',
    'trigger_factors',
    'notes',
  ],
  'symptom_entry': [
    'symptom_type',
    'custom_label',
    'intensity',
    'body_region',
    'duration_minutes',
  ],
  'tasks': [
    'title',
    'priority',
    'notes',
  ],
  'labs': [
    'lab_name',
    'ordered_by',
    'sample_date',
    'result_date',
    'notes',
  ],
  'lab_value': [
    'marker',
    'value',
    'value_text',
    'unit',
    'reference_low',
    'reference_high',
    'flag',
  ],
};
