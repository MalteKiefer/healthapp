-- HealthVault — Initial Schema Migration
-- Creates all core tables, indexes, and extensions.

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ── Users ───────────────────────────────────────────────────────────

CREATE TABLE users (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email                   TEXT NOT NULL UNIQUE,
    display_name            TEXT NOT NULL,
    auth_hash               TEXT NOT NULL,
    pek_salt                TEXT NOT NULL,
    auth_salt               TEXT NOT NULL,
    identity_pubkey         TEXT NOT NULL,
    identity_privkey_enc    TEXT NOT NULL,
    signing_pubkey          TEXT NOT NULL,
    signing_privkey_enc     TEXT NOT NULL,
    role                    TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    is_disabled             BOOLEAN NOT NULL DEFAULT FALSE,
    totp_secret_enc         TEXT,
    totp_enabled            BOOLEAN NOT NULL DEFAULT FALSE,
    onboarding_completed_at TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE user_recovery_codes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash   TEXT NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recovery_codes_user ON user_recovery_codes (user_id) WHERE used_at IS NULL;

CREATE TABLE user_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    jti             TEXT NOT NULL UNIQUE,
    device_hint     TEXT,
    ip_address      INET,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_active_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ
);

CREATE INDEX idx_sessions_user ON user_sessions (user_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_sessions_jti ON user_sessions (jti);

CREATE TABLE user_preferences (
    user_id             UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    language            TEXT NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'de')),
    date_format         TEXT NOT NULL DEFAULT 'DMY' CHECK (date_format IN ('DMY', 'MDY', 'YMD')),
    weight_unit         TEXT NOT NULL DEFAULT 'kg' CHECK (weight_unit IN ('kg', 'lbs')),
    height_unit         TEXT NOT NULL DEFAULT 'cm' CHECK (height_unit IN ('cm', 'inch')),
    temperature_unit    TEXT NOT NULL DEFAULT 'celsius' CHECK (temperature_unit IN ('celsius', 'fahrenheit')),
    blood_glucose_unit  TEXT NOT NULL DEFAULT 'mmol_l' CHECK (blood_glucose_unit IN ('mmol_l', 'mg_dl')),
    week_start          TEXT NOT NULL DEFAULT 'monday' CHECK (week_start IN ('monday', 'sunday')),
    timezone            TEXT NOT NULL DEFAULT 'UTC'
);

CREATE TABLE user_storage (
    user_id             UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    used_bytes          BIGINT NOT NULL DEFAULT 0,
    quota_bytes         BIGINT NOT NULL DEFAULT 5368709120,
    last_calculated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Profiles ────────────────────────────────────────────────────────

CREATE TABLE profiles (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    display_name            TEXT NOT NULL,
    date_of_birth           DATE,
    biological_sex          TEXT NOT NULL DEFAULT 'unspecified' CHECK (biological_sex IN ('male', 'female', 'other', 'unspecified')),
    blood_type              TEXT DEFAULT 'unknown' CHECK (blood_type IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', '0+', '0-', 'unknown')),
    rhesus_factor           TEXT DEFAULT 'unknown' CHECK (rhesus_factor IN ('positive', 'negative', 'unknown')),
    avatar_color            TEXT NOT NULL DEFAULT '#4A90D9',
    avatar_image_enc        BYTEA,
    archived_at             TIMESTAMPTZ,
    onboarding_completed_at TIMESTAMPTZ,
    rotation_state          TEXT NOT NULL DEFAULT 'idle' CHECK (rotation_state IN ('idle', 'rotating', 'rotation_failed')),
    rotation_started_at     TIMESTAMPTZ,
    rotation_progress       JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE profile_key_grants (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id          UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    grantee_user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_key       TEXT NOT NULL,
    grant_signature     TEXT NOT NULL,
    granted_by_user_id  UUID NOT NULL REFERENCES users(id),
    granted_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at          TIMESTAMPTZ
);

CREATE INDEX idx_pkg_profile_grantee ON profile_key_grants (profile_id, grantee_user_id) WHERE revoked_at IS NULL;

-- ── Families ────────────────────────────────────────────────────────

CREATE TABLE families (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    created_by      UUID NOT NULL REFERENCES users(id),
    dissolved_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE family_memberships (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id   UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    role        TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'member')),
    joined_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    left_at     TIMESTAMPTZ,
    UNIQUE(user_id, family_id)
);

CREATE TABLE family_key_grants (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id           UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    grantee_user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_key       TEXT NOT NULL,
    granted_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at          TIMESTAMPTZ
);

-- ── Vitals ──────────────────────────────────────────────────────────

CREATE TABLE vitals (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id              UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    blood_pressure_systolic INTEGER,
    blood_pressure_diastolic INTEGER,
    pulse                   INTEGER,
    oxygen_saturation       DECIMAL(5,2),
    weight                  DECIMAL(7,3),
    height                  DECIMAL(6,1),
    body_temperature        DECIMAL(4,1),
    blood_glucose           DECIMAL(6,2),
    respiratory_rate        INTEGER,
    waist_circumference     DECIMAL(5,1),
    hip_circumference       DECIMAL(5,1),
    body_fat_percentage     DECIMAL(4,1),
    bmi                     DECIMAL(4,1),
    sleep_duration_minutes  INTEGER,
    sleep_quality           INTEGER CHECK (sleep_quality IS NULL OR (sleep_quality >= 1 AND sleep_quality <= 5)),
    measured_at             TIMESTAMPTZ NOT NULL,
    device                  TEXT,
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at              TIMESTAMPTZ
);

CREATE INDEX idx_vitals_profile_time ON vitals (profile_id, measured_at DESC);
CREATE INDEX idx_vitals_profile_active ON vitals (profile_id, measured_at DESC) WHERE deleted_at IS NULL;

-- ── Lab Results ─────────────────────────────────────────────────────

CREATE TABLE lab_results (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    lab_name        TEXT,
    ordered_by      TEXT,
    sample_date     TIMESTAMPTZ NOT NULL,
    result_date     TIMESTAMPTZ,
    notes           TEXT,
    version         INTEGER NOT NULL DEFAULT 1,
    previous_id     UUID REFERENCES lab_results(id),
    is_current      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_labs_profile_date ON lab_results (profile_id, sample_date DESC);

CREATE TABLE lab_values (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lab_result_id   UUID NOT NULL REFERENCES lab_results(id) ON DELETE CASCADE,
    marker          TEXT NOT NULL,
    value           DECIMAL(12,4),
    value_text      TEXT,
    unit            TEXT,
    reference_low   DECIMAL(12,4),
    reference_high  DECIMAL(12,4),
    flag            TEXT CHECK (flag IS NULL OR flag IN ('normal', 'low', 'high', 'critical'))
);

CREATE INDEX idx_lab_values_result ON lab_values (lab_result_id, marker);

-- ── Documents ───────────────────────────────────────────────────────

CREATE TABLE documents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    filename_enc    TEXT NOT NULL,
    mime_type       TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    storage_path    TEXT NOT NULL,
    category        TEXT NOT NULL CHECK (category IN (
        'lab_result', 'imaging', 'prescription', 'referral',
        'vaccination_record', 'discharge_summary', 'report', 'legal', 'other'
    )),
    tags            TEXT[],
    ocr_text_enc    TEXT,
    uploaded_by     UUID NOT NULL REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_docs_profile_cat ON documents (profile_id, category) WHERE deleted_at IS NULL;

-- ── Health Diary ────────────────────────────────────────────────────

CREATE TABLE diary_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title           TEXT NOT NULL,
    event_type      TEXT NOT NULL CHECK (event_type IN (
        'accident', 'illness', 'surgery', 'hospital_stay', 'emergency',
        'doctor_visit', 'vaccination', 'medication_change', 'symptom', 'other'
    )),
    started_at      TIMESTAMPTZ NOT NULL,
    ended_at        TIMESTAMPTZ,
    description     TEXT,
    severity        INTEGER CHECK (severity IS NULL OR (severity >= 1 AND severity <= 10)),
    location        TEXT,
    outcome         TEXT,
    version         INTEGER NOT NULL DEFAULT 1,
    previous_id     UUID REFERENCES diary_events(id),
    is_current      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_diary_profile_time ON diary_events (profile_id, started_at DESC) WHERE is_current AND deleted_at IS NULL;

-- ── Medications ─────────────────────────────────────────────────────

CREATE TABLE medications (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id              UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name                    TEXT NOT NULL,
    dosage                  TEXT,
    unit                    TEXT,
    frequency               TEXT,
    route                   TEXT,
    started_at              TIMESTAMPTZ,
    ended_at                TIMESTAMPTZ,
    prescribed_by           TEXT,
    reason                  TEXT,
    notes                   TEXT,
    related_diagnosis_id    UUID,
    version                 INTEGER NOT NULL DEFAULT 1,
    previous_id             UUID REFERENCES medications(id),
    is_current              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at              TIMESTAMPTZ
);

CREATE INDEX idx_meds_profile_active ON medications (profile_id) WHERE ended_at IS NULL AND deleted_at IS NULL;
CREATE INDEX idx_meds_name_fts ON medications USING GIN (to_tsvector('english', name));
CREATE INDEX idx_meds_name_trgm ON medications USING GIN (name gin_trgm_ops);

CREATE TABLE medication_intake (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    medication_id   UUID NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
    profile_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    scheduled_at    TIMESTAMPTZ NOT NULL,
    taken_at        TIMESTAMPTZ,
    dose_taken      DECIMAL(8,3),
    skipped_reason  TEXT,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_intake_med_scheduled ON medication_intake (medication_id, scheduled_at DESC);

-- ── Allergies ───────────────────────────────────────────────────────

CREATE TABLE allergies (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    category        TEXT NOT NULL CHECK (category IN ('medication', 'food', 'environmental', 'contact', 'other')),
    reaction_type   TEXT CHECK (reaction_type IN ('anaphylaxis', 'urticaria', 'angioedema', 'respiratory', 'gastrointestinal', 'skin', 'other')),
    severity        TEXT CHECK (severity IN ('mild', 'moderate', 'severe', 'life_threatening')),
    onset_date      DATE,
    diagnosed_by    TEXT,
    notes           TEXT,
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'resolved', 'unconfirmed')),
    version         INTEGER NOT NULL DEFAULT 1,
    previous_id     UUID REFERENCES allergies(id),
    is_current      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_allergy_name_fts ON allergies USING GIN (to_tsvector('english', name));
CREATE INDEX idx_allergy_name_trgm ON allergies USING GIN (name gin_trgm_ops);

-- ── Vaccinations ────────────────────────────────────────────────────

CREATE TABLE vaccinations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    vaccine_name    TEXT NOT NULL,
    trade_name      TEXT,
    manufacturer    TEXT,
    lot_number      TEXT,
    dose_number     INTEGER,
    administered_at DATE NOT NULL,
    administered_by TEXT,
    next_due_at     DATE,
    site            TEXT,
    notes           TEXT,
    document_id     UUID REFERENCES documents(id) ON DELETE SET NULL,
    version         INTEGER NOT NULL DEFAULT 1,
    previous_id     UUID REFERENCES vaccinations(id),
    is_current      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_vacc_name_fts ON vaccinations USING GIN (to_tsvector('english', vaccine_name));

-- ── Diagnoses ───────────────────────────────────────────────────────

CREATE TABLE diagnoses (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id          UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    icd10_code          TEXT,
    status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'resolved', 'chronic', 'in_remission', 'suspected')),
    diagnosed_at        DATE,
    diagnosed_by        TEXT,
    resolved_at         DATE,
    notes               TEXT,
    version             INTEGER NOT NULL DEFAULT 1,
    previous_id         UUID REFERENCES diagnoses(id),
    is_current          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX idx_diagnosis_name_fts ON diagnoses USING GIN (to_tsvector('english', name || ' ' || COALESCE(icd10_code, '')));

-- ── Medical Contacts ────────────────────────────────────────────────

CREATE TABLE medical_contacts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id          UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    specialty           TEXT,
    facility            TEXT,
    phone               TEXT,
    email               TEXT,
    address             TEXT,
    notes               TEXT,
    is_emergency_contact BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

-- ── Tasks ───────────────────────────────────────────────────────────

CREATE TABLE tasks (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id              UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title                   TEXT NOT NULL,
    due_date                DATE,
    priority                TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    status                  TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'done', 'cancelled')),
    done_at                 TIMESTAMPTZ,
    related_diary_event_id  UUID REFERENCES diary_events(id) ON DELETE SET NULL,
    related_appointment_id  UUID,
    notes                   TEXT,
    created_by_user_id      UUID NOT NULL REFERENCES users(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tasks_profile_open ON tasks (profile_id, due_date ASC) WHERE status = 'open';

-- ── Appointments ────────────────────────────────────────────────────

CREATE TABLE appointments (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id              UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title                   TEXT NOT NULL,
    appointment_type        TEXT NOT NULL CHECK (appointment_type IN (
        'examination', 'surgery', 'vaccination', 'follow_up', 'lab',
        'specialist', 'general_practice', 'therapy', 'other'
    )),
    scheduled_at            TIMESTAMPTZ NOT NULL,
    duration_minutes        INTEGER,
    doctor_id               UUID REFERENCES medical_contacts(id) ON DELETE SET NULL,
    location                TEXT,
    preparation_notes       TEXT,
    reminder_days_before    INTEGER[],
    status                  TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'completed', 'cancelled', 'missed')),
    linked_diary_event_id   UUID REFERENCES diary_events(id) ON DELETE SET NULL,
    recurrence              TEXT DEFAULT 'none' CHECK (recurrence IN ('none', 'weekly', 'monthly', 'quarterly', 'yearly', 'custom')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Fix tasks FK now that appointments table exists
ALTER TABLE tasks ADD CONSTRAINT fk_tasks_appointment FOREIGN KEY (related_appointment_id) REFERENCES appointments(id) ON DELETE SET NULL;

CREATE INDEX idx_appt_profile_future ON appointments (profile_id, scheduled_at ASC) WHERE status = 'scheduled';

-- ── Symptoms ────────────────────────────────────────────────────────

CREATE TABLE symptom_records (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    recorded_at     TIMESTAMPTZ NOT NULL,
    trigger_factors TEXT[],
    notes           TEXT,
    linked_vital_id UUID REFERENCES vitals(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE symptom_entries (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    symptom_record_id   UUID NOT NULL REFERENCES symptom_records(id) ON DELETE CASCADE,
    symptom_type        TEXT NOT NULL CHECK (symptom_type IN (
        'pain', 'headache', 'nausea', 'fatigue', 'dizziness',
        'shortness_of_breath', 'anxiety', 'mood', 'sleep_quality',
        'appetite', 'custom'
    )),
    custom_label        TEXT,
    intensity           INTEGER NOT NULL CHECK (intensity >= 0 AND intensity <= 10),
    body_region         TEXT CHECK (body_region IS NULL OR body_region IN (
        'head', 'neck', 'chest', 'abdomen', 'back',
        'left_arm', 'right_arm', 'left_leg', 'right_leg', 'general'
    )),
    duration_minutes    INTEGER
);

CREATE INDEX idx_symptoms_profile_time ON symptom_records (profile_id, recorded_at DESC);

-- ── Vital Thresholds ────────────────────────────────────────────────

CREATE TABLE vital_thresholds (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
    thresholds  JSONB NOT NULL DEFAULT '{}',
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Notifications ───────────────────────────────────────────────────

CREATE TABLE notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type            TEXT NOT NULL,
    title           TEXT NOT NULL,
    body            TEXT,
    metadata        JSONB,
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notif_user_unread ON notifications (user_id, created_at DESC) WHERE read_at IS NULL;

CREATE TABLE notification_preferences (
    user_id                 UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    vaccination_due         BOOLEAN NOT NULL DEFAULT TRUE,
    vaccination_due_days    INTEGER NOT NULL DEFAULT 30,
    medication_reminder     BOOLEAN NOT NULL DEFAULT FALSE,
    lab_result_abnormal     BOOLEAN NOT NULL DEFAULT TRUE,
    emergency_access        BOOLEAN NOT NULL DEFAULT TRUE,
    export_ready            BOOLEAN NOT NULL DEFAULT TRUE,
    family_invite           BOOLEAN NOT NULL DEFAULT TRUE,
    key_rotation_required   BOOLEAN NOT NULL DEFAULT TRUE,
    session_new             BOOLEAN NOT NULL DEFAULT TRUE,
    storage_quota_warning   BOOLEAN NOT NULL DEFAULT TRUE
);

-- ── Emergency Access ────────────────────────────────────────────────

CREATE TABLE emergency_access_configs (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id                  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
    emergency_contact_user_id   UUID NOT NULL REFERENCES users(id),
    wait_hours                  INTEGER NOT NULL DEFAULT 48 CHECK (wait_hours >= 0 AND wait_hours <= 168),
    data_fields                 TEXT[] NOT NULL DEFAULT '{"blood_type","allergies","medications","diagnoses","contacts"}',
    message                     TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE emergency_access_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    requester_id    UUID NOT NULL REFERENCES users(id),
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'denied', 'auto_approved', 'expired')),
    requested_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at     TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    auto_approve_at TIMESTAMPTZ
);

CREATE TABLE emergency_cards (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
    token       TEXT NOT NULL UNIQUE,
    data        JSONB NOT NULL,
    enabled     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Calendar Feeds ──────────────────────────────────────────────────

CREATE TABLE calendar_feeds (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    token_hash      TEXT NOT NULL UNIQUE,
    profile_ids     UUID[] NOT NULL,
    include_appointments    BOOLEAN NOT NULL DEFAULT TRUE,
    include_tasks           BOOLEAN NOT NULL DEFAULT TRUE,
    include_vaccinations    BOOLEAN NOT NULL DEFAULT TRUE,
    include_medications     BOOLEAN NOT NULL DEFAULT FALSE,
    include_labs            BOOLEAN NOT NULL DEFAULT TRUE,
    verbose_mode            BOOLEAN NOT NULL DEFAULT FALSE,
    last_polled_at  TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Profile Activity Log ────────────────────────────────────────────

CREATE TABLE profile_activity_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    action      TEXT NOT NULL,
    module      TEXT NOT NULL,
    record_id   UUID,
    metadata    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_activity_profile_time ON profile_activity_log (profile_id, created_at DESC);

-- ── Audit Log (System-Wide, Immutable) ──────────────────────────────

CREATE TABLE audit_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    action      TEXT NOT NULL,
    resource    TEXT NOT NULL,
    resource_id UUID,
    ip_address  INET,
    user_agent  TEXT,
    metadata    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_user_time ON audit_log (user_id, created_at DESC);

-- ── Legal / Consent ─────────────────────────────────────────────────

CREATE TABLE instance_legal_documents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_type   TEXT NOT NULL CHECK (document_type IN ('privacy_policy', 'terms_of_service')),
    version         TEXT NOT NULL,
    content_html    TEXT NOT NULL,
    effective_from  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE user_consent_records (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_id     UUID NOT NULL REFERENCES instance_legal_documents(id),
    accepted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address      INET,
    user_agent      TEXT
);

-- ── Instance Settings ───────────────────────────────────────────────

CREATE TABLE instance_settings (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Backup ──────────────────────────────────────────────────────────

CREATE TABLE backup_heartbeat (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    backed_up_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    file_size_bytes BIGINT NOT NULL,
    encrypted       BOOLEAN NOT NULL DEFAULT TRUE,
    checksum_sha256 TEXT NOT NULL
);

CREATE TABLE backup_verification_log (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    verified_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    backup_filename     TEXT NOT NULL,
    backup_size_bytes   BIGINT NOT NULL,
    backup_created_at   TIMESTAMPTZ NOT NULL,
    status              TEXT NOT NULL CHECK (status IN ('success', 'failed', 'warning')),
    tables_found        TEXT[],
    row_counts          JSONB,
    error_message       TEXT,
    duration_ms         INTEGER
);

-- ── Export Audit ────────────────────────────────────────────────────

CREATE TABLE export_audit_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    profile_ids     UUID[] NOT NULL,
    format          TEXT NOT NULL,
    record_counts   JSONB,
    file_size_bytes BIGINT,
    status          TEXT NOT NULL DEFAULT 'success' CHECK (status IN ('success', 'failed')),
    ip_address      INET,
    exported_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_export_audit_user ON export_audit_log (user_id, exported_at DESC);

-- ── Import Jobs ─────────────────────────────────────────────────────

CREATE TABLE import_jobs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status          TEXT NOT NULL CHECK (status IN ('pending', 'processing', 'partial', 'complete', 'failed')),
    total_records   INTEGER,
    imported_records INTEGER DEFAULT 0,
    failed_records  INTEGER DEFAULT 0,
    error_log       JSONB,
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ NOT NULL
);

-- ── Webhooks ────────────────────────────────────────────────────────

CREATE TABLE webhooks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    url         TEXT NOT NULL,
    events      TEXT[] NOT NULL,
    secret      TEXT NOT NULL,
    enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE webhook_delivery_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    webhook_id  UUID NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
    event       TEXT NOT NULL,
    status_code INTEGER,
    response    TEXT,
    error       TEXT,
    delivered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Schema Migrations Tracking ──────────────────────────────────────

CREATE TABLE IF NOT EXISTS schema_migrations (
    version     BIGINT PRIMARY KEY,
    dirty       BOOLEAN NOT NULL DEFAULT FALSE,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO schema_migrations (version, dirty) VALUES (1, FALSE);
