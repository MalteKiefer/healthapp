import { api } from './client';
import { decryptOrPassthrough, encryptForWrite, type EntityBase } from './encryptedEntity';

export interface Medication extends EntityBase {
  name: string;
  dosage?: string;
  unit?: string;
  frequency?: string;
  route?: string;
  started_at?: string;
  ended_at?: string;
  prescribed_by?: string;
  reason?: string;
  notes?: string;
  related_diagnosis_id?: string;
  version?: number;
  previous_id?: string;
  is_current?: boolean;
  created_at: string;
  updated_at?: string;
}

export interface MedicationListResponse {
  items: Medication[];
  total: number;
}

export interface MedicationIntake extends EntityBase {
  medication_id: string;
  scheduled_at: string;
  taken_at?: string;
  dose_taken?: string;
  skipped_reason?: string;
  notes?: string;
  created_at: string;
}

export interface MedicationIntakeListResponse {
  items: MedicationIntake[];
  total: number;
}

const ENTITY = 'medication';
// started_at, ended_at stay plaintext.
const CONTENT_FIELDS = [
  'name', 'dosage', 'unit', 'frequency', 'route',
  'prescribed_by', 'reason', 'notes',
] as const;

const migratePath = (r: Medication) =>
  `/api/v1/profiles/${r.profile_id}/medications/${r.id}/migrate-content`;

const INTAKE_ENTITY = 'medication_intake';
const INTAKE_CONTENT_FIELDS = ['dose_taken', 'skipped_reason', 'notes'] as const;

const intakeMigratePath = (r: MedicationIntake) =>
  `/api/v1/profiles/${r.profile_id}/medications/${r.medication_id}/intake/${r.id}/migrate-content`;

export const medicationsApi = {
  list: async (profileId: string): Promise<MedicationListResponse> => {
    const res = await api.get<MedicationListResponse>(
      `/api/v1/profiles/${profileId}/medications`,
    );
    const items = await Promise.all(
      res.items.map((r) =>
        decryptOrPassthrough(
          r,
          ENTITY,
          CONTENT_FIELDS as unknown as readonly (keyof Medication)[],
          migratePath,
        ),
      ),
    );
    return { items, total: res.total };
  },

  active: async (profileId: string): Promise<MedicationListResponse> => {
    const res = await api.get<MedicationListResponse>(
      `/api/v1/profiles/${profileId}/medications/active`,
    );
    const items = await Promise.all(
      res.items.map((r) =>
        decryptOrPassthrough(
          r,
          ENTITY,
          CONTENT_FIELDS as unknown as readonly (keyof Medication)[],
          migratePath,
        ),
      ),
    );
    return { items, total: res.total };
  },

  create: async (profileId: string, data: Partial<Medication>): Promise<Medication> => {
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite<Medication>(
      profileId,
      newId,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Medication)[],
    );
    const body: Record<string, unknown> = { ...structural, id: newId };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<Medication>(
      `/api/v1/profiles/${profileId}/medications`,
      body,
    );
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Medication)[],
      migratePath,
    );
  },

  update: async (
    profileId: string,
    id: string,
    data: Partial<Medication>,
  ): Promise<Medication> => {
    const { content_enc, structural } = await encryptForWrite<Medication>(
      profileId,
      id,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Medication)[],
    );
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.patch<Medication>(
      `/api/v1/profiles/${profileId}/medications/${id}`,
      body,
    );
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Medication)[],
      migratePath,
    );
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/medications/${id}`),

  // ----- Intake sub-resource -----
  listIntake: async (
    profileId: string,
    medicationId: string,
  ): Promise<MedicationIntakeListResponse> => {
    const res = await api.get<MedicationIntakeListResponse>(
      `/api/v1/profiles/${profileId}/medications/${medicationId}/intake`,
    );
    const items = await Promise.all(
      res.items.map((r) =>
        decryptOrPassthrough(
          r,
          INTAKE_ENTITY,
          INTAKE_CONTENT_FIELDS as unknown as readonly (keyof MedicationIntake)[],
          intakeMigratePath,
        ),
      ),
    );
    return { items, total: res.total };
  },

  createIntake: async (
    profileId: string,
    medicationId: string,
    data: Partial<MedicationIntake>,
  ): Promise<MedicationIntake> => {
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite<MedicationIntake>(
      profileId,
      newId,
      INTAKE_ENTITY,
      data,
      INTAKE_CONTENT_FIELDS as unknown as readonly (keyof MedicationIntake)[],
    );
    const body: Record<string, unknown> = { ...structural, id: newId };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<MedicationIntake>(
      `/api/v1/profiles/${profileId}/medications/${medicationId}/intake`,
      body,
    );
    return decryptOrPassthrough(
      raw,
      INTAKE_ENTITY,
      INTAKE_CONTENT_FIELDS as unknown as readonly (keyof MedicationIntake)[],
      intakeMigratePath,
    );
  },

  updateIntake: async (
    profileId: string,
    medicationId: string,
    intakeId: string,
    data: Partial<MedicationIntake>,
  ): Promise<MedicationIntake> => {
    const { content_enc, structural } = await encryptForWrite<MedicationIntake>(
      profileId,
      intakeId,
      INTAKE_ENTITY,
      data,
      INTAKE_CONTENT_FIELDS as unknown as readonly (keyof MedicationIntake)[],
    );
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.patch<MedicationIntake>(
      `/api/v1/profiles/${profileId}/medications/${medicationId}/intake/${intakeId}`,
      body,
    );
    return decryptOrPassthrough(
      raw,
      INTAKE_ENTITY,
      INTAKE_CONTENT_FIELDS as unknown as readonly (keyof MedicationIntake)[],
      intakeMigratePath,
    );
  },

  deleteIntake: (profileId: string, medicationId: string, intakeId: string) =>
    api.delete(
      `/api/v1/profiles/${profileId}/medications/${medicationId}/intake/${intakeId}`,
    ),
};
