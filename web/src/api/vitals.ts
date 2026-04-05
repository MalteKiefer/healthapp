import { api } from './client';
import {
  encryptProfileContent,
  decryptProfileContent,
  makeAAD,
  getProfileKey,
} from '../crypto';
import { enqueueMigration } from '../utils/migrationQueue';

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

// Fields that live inside content_enc (everything except structural ids/ts).
const CONTENT_FIELDS = [
  'blood_pressure_systolic', 'blood_pressure_diastolic', 'pulse',
  'oxygen_saturation', 'weight', 'height', 'body_temperature',
  'blood_glucose', 'respiratory_rate', 'waist_circumference',
  'hip_circumference', 'body_fat_percentage', 'bmi',
  'sleep_duration_minutes', 'sleep_quality', 'device', 'notes',
] as const;

type ContentField = typeof CONTENT_FIELDS[number];
type VitalContent = Partial<Pick<Vital, ContentField>>;

function extractContent(v: Partial<Vital>): VitalContent {
  const out: VitalContent = {};
  for (const k of CONTENT_FIELDS) {
    if (v[k] !== undefined) (out as Record<string, unknown>)[k] = v[k];
  }
  return out;
}

function mergeContent(base: Vital, content: VitalContent): Vital {
  // Clear any plaintext that came off the wire — decrypted blob is
  // authoritative. Missing keys in content = field is null.
  const cleared: Vital = { ...base };
  for (const k of CONTENT_FIELDS) (cleared as Record<string, unknown>)[k] = undefined;
  return { ...cleared, ...content };
}

async function decryptOrPassthrough(profileId: string, raw: Vital): Promise<Vital> {
  const key = getProfileKey(profileId);
  if (!key) return raw; // key not unwrapped yet — caller handles

  if (raw.content_enc) {
    try {
      const content = await decryptProfileContent<VitalContent>(
        raw.content_enc,
        key,
        makeAAD(profileId, 'vital', raw.id),
      );
      return mergeContent(raw, content);
    } catch (err) {
      console.warn('vital decrypt failed, falling back to plaintext', raw.id, err);
      return raw;
    }
  }

  // Legacy row: plaintext fields still present. Schedule a background
  // migrate-content so the next read gets the encrypted blob.
  const content = extractContent(raw);
  enqueueMigration(`vitals:${profileId}`, async () => {
    const freshKey = getProfileKey(profileId);
    if (!freshKey) return;
    const blob = await encryptProfileContent(
      content,
      freshKey,
      makeAAD(profileId, 'vital', raw.id),
    );
    await api.patch(`/api/v1/profiles/${profileId}/vitals/${raw.id}/migrate-content`, {
      content_enc: blob,
    });
  });
  return raw;
}

async function encryptForWrite(
  profileId: string,
  vitalId: string,
  data: Partial<Vital>,
): Promise<{ content_enc: string | undefined; structural: Partial<Vital> }> {
  const key = getProfileKey(profileId);
  const content = extractContent(data);
  let content_enc: string | undefined;
  if (key && Object.keys(content).length > 0) {
    content_enc = await encryptProfileContent(
      content,
      key,
      makeAAD(profileId, 'vital', vitalId),
    );
  }
  // Strip content fields from the outgoing object so the server sees only
  // structural data plus content_enc.
  const structural: Partial<Vital> = { ...data };
  for (const k of CONTENT_FIELDS) delete structural[k];
  delete structural.content_enc;
  return { content_enc, structural };
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
    const items = await Promise.all(res.items.map((v) => decryptOrPassthrough(profileId, v)));
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
