import { api } from './client';
import {
  decryptOrPassthrough as decryptEntity,
  encryptForWrite as encryptEntity,
} from './encryptedEntity';

export interface Vital {
  id: string;
  profile_id: string;
  blood_pressure_systolic?: number;
  blood_pressure_diastolic?: number;
  pulse?: number;
  oxygen_saturation?: number;
  weight?: number;
  height?: number;
  body_temperature?: number;
  blood_glucose?: number;
  respiratory_rate?: number;
  waist_circumference?: number;
  hip_circumference?: number;
  body_fat_percentage?: number;
  bmi?: number;
  sleep_duration_minutes?: number;
  sleep_quality?: number;
  measured_at: string;
  device?: string;
  notes?: string;
  created_at: string;
  /** Opaque ciphertext; present on reads, extracted on writes. */
  content_enc?: string | null;
}

const ENTITY = 'vital';

// Fields that live inside content_enc (everything except structural ids/ts).
const CONTENT_FIELDS: readonly (keyof Vital)[] = [
  'blood_pressure_systolic', 'blood_pressure_diastolic', 'pulse',
  'oxygen_saturation', 'weight', 'height', 'body_temperature',
  'blood_glucose', 'respiratory_rate', 'waist_circumference',
  'hip_circumference', 'body_fat_percentage', 'bmi',
  'sleep_duration_minutes', 'sleep_quality', 'device', 'notes',
];

const migratePath = (v: Vital) =>
  `/api/v1/profiles/${v.profile_id}/vitals/${v.id}/migrate-content`;

async function decryptOrPassthrough(_profileId: string, raw: Vital): Promise<Vital> {
  return decryptEntity(raw, ENTITY, CONTENT_FIELDS, migratePath);
}

async function encryptForWrite(
  profileId: string,
  vitalId: string,
  data: Partial<Vital>,
): Promise<{ content_enc: string | undefined; structural: Partial<Vital> }> {
  return encryptEntity(profileId, vitalId, ENTITY, data, CONTENT_FIELDS);
}

export interface VitalListResponse {
  items: Vital[];
  total: number;
}

export const vitalsApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number; from?: string; to?: string },
  ): Promise<VitalListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    if (params?.from) query.set('from', params.from);
    if (params?.to) query.set('to', params.to);
    const qs = query.toString();
    const res = await api.get<VitalListResponse>(
      `/api/v1/profiles/${profileId}/vitals${qs ? `?${qs}` : ''}`,
    );
    const items = await Promise.all((res.items || []).map((v) => decryptOrPassthrough(profileId, v)));
    return { items, total: res.total };
  },

  get: async (profileId: string, vitalId: string): Promise<Vital> => {
    const raw = await api.get<Vital>(`/api/v1/profiles/${profileId}/vitals/${vitalId}`);
    return decryptOrPassthrough(profileId, raw);
  },

  create: async (profileId: string, data: Partial<Vital>): Promise<Vital> => {
    // We need the server-assigned id for AAD. Strategy: generate the id
    // client-side (UUIDv4), send it with the payload so the AAD binds.
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite(profileId, newId, data);
    const body: Record<string, unknown> = { ...structural, id: newId };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<Vital>(`/api/v1/profiles/${profileId}/vitals`, body);
    return decryptOrPassthrough(profileId, raw);
  },

  update: async (profileId: string, vitalId: string, data: Partial<Vital>): Promise<Vital> => {
    const { content_enc, structural } = await encryptForWrite(profileId, vitalId, data);
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.patch<Vital>(
      `/api/v1/profiles/${profileId}/vitals/${vitalId}`,
      body,
    );
    return decryptOrPassthrough(profileId, raw);
  },

  delete: (profileId: string, vitalId: string) =>
    api.delete(`/api/v1/profiles/${profileId}/vitals/${vitalId}`),
};
