import { api } from './client';
import { decryptOrPassthrough, encryptForWrite, type EntityBase } from './encryptedEntity';
import {
  encryptProfileContent,
  decryptProfileContent,
  makeAAD,
  getProfileKey,
} from '../crypto';
import { enqueueMigration } from '../utils/migrationQueue';

export interface LabValue {
  id?: string;
  lab_result_id?: string;
  marker: string;
  value?: number;
  value_text?: string;
  unit?: string;
  reference_low?: number;
  reference_high?: number;
  flag?: string;
  content_enc?: string;
}

export interface LabResult extends EntityBase {
  lab_name?: string;
  ordered_by?: string;
  sample_date: string;
  result_date?: string;
  notes?: string;
  values: LabValue[];
  version?: number;
  created_at: string;
  updated_at?: string;
}

export interface LabListResponse {
  items: LabResult[];
  total: number;
}

export interface TrendDataPoint {
  date: string;
  value: number;
  flag?: string;
}

export interface MarkerTrend {
  marker: string;
  unit?: string;
  reference_low?: number;
  reference_high?: number;
  data_points: TrendDataPoint[];
}

const ENTITY = 'lab_result';
const CONTENT_FIELDS = [
  'lab_name', 'ordered_by', 'sample_date', 'result_date', 'notes',
] as const;

const VALUE_ENTITY = 'lab_value';
const VALUE_CONTENT_FIELDS = [
  'marker', 'value', 'value_text', 'unit',
  'reference_low', 'reference_high', 'flag',
] as const;

const migratePath = (r: LabResult) =>
  `/api/v1/profiles/${r.profile_id}/labs/${r.id}/migrate-content`;

const valueMigratePath = (profileId: string, labId: string, valueId: string) =>
  `/api/v1/profiles/${profileId}/labs/${labId}/values/${valueId}/migrate-content`;

async function decryptLabValue(
  profileId: string,
  labId: string,
  v: LabValue,
): Promise<LabValue> {
  const key = getProfileKey(profileId);
  if (!key) return v;

  if (v.content_enc) {
    try {
      const content = await decryptProfileContent<Record<string, unknown>>(
        v.content_enc,
        key,
        makeAAD(profileId, VALUE_ENTITY, v.id),
      );
      const cleared = { ...v } as Record<string, unknown>;
      for (const k of VALUE_CONTENT_FIELDS) cleared[k] = undefined;
      return { ...(cleared as unknown as LabValue), ...content };
    } catch (err) {
      console.warn('lab_value decrypt failed, falling back', v.id, err);
      return v;
    }
  }

  // Legacy: schedule background migration
  const content: Record<string, unknown> = {};
  for (const k of VALUE_CONTENT_FIELDS) {
    const val = (v as unknown as Record<string, unknown>)[k];
    if (val !== undefined) content[k] = val;
  }
  enqueueMigration(`lab_value:${profileId}`, async () => {
    const freshKey = getProfileKey(profileId);
    if (!freshKey) return;
    const blob = await encryptProfileContent(
      content,
      freshKey,
      makeAAD(profileId, VALUE_ENTITY, v.id),
    );
    await api.patch(valueMigratePath(profileId, labId, v.id), { content_enc: blob });
  });
  return v;
}

async function encryptLabValueForWrite(
  profileId: string,
  valueId: string,
  v: Partial<LabValue>,
): Promise<{ content_enc: string | undefined; structural: Partial<LabValue> }> {
  const key = getProfileKey(profileId);
  const content: Record<string, unknown> = {};
  for (const k of VALUE_CONTENT_FIELDS) {
    const val = (v as unknown as Record<string, unknown>)[k];
    if (val !== undefined) content[k] = val;
  }
  let content_enc: string | undefined;
  if (key && Object.keys(content).length > 0) {
    content_enc = await encryptProfileContent(
      content,
      key,
      makeAAD(profileId, VALUE_ENTITY, valueId),
    );
  }
  const structural = { ...v } as Record<string, unknown>;
  for (const k of VALUE_CONTENT_FIELDS) delete structural[k];
  delete structural.content_enc;
  return { content_enc, structural: structural as Partial<LabValue> };
}

async function decryptLab(profileId: string, raw: LabResult): Promise<LabResult> {
  const top = await decryptOrPassthrough(
    raw,
    ENTITY,
    CONTENT_FIELDS as unknown as readonly (keyof LabResult)[],
    migratePath,
  );
  const values = await Promise.all(
    (top.values ?? []).map((v) => decryptLabValue(profileId, top.id, v)),
  );
  return { ...top, values };
}

export const labsApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number },
  ): Promise<LabListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    const qs = query.toString();
    const res = await api.get<LabListResponse>(
      `/api/v1/profiles/${profileId}/labs${qs ? `?${qs}` : ''}`,
    );
    const items = await Promise.all(res.items.map((r) => decryptLab(profileId, r)));
    return { items, total: res.total };
  },

  get: async (profileId: string, id: string): Promise<LabResult> => {
    const raw = await api.get<LabResult>(`/api/v1/profiles/${profileId}/labs/${id}`);
    return decryptLab(profileId, raw);
  },

  markers: (profileId: string) =>
    api.get<{ markers: string[] }>(`/api/v1/profiles/${profileId}/labs/markers`),

  trend: (profileId: string, marker: string) =>
    api.get<MarkerTrend>(
      `/api/v1/profiles/${profileId}/labs/trend?marker=${encodeURIComponent(marker)}`,
    ),

  create: async (
    profileId: string,
    data: Partial<LabResult> & { values?: Partial<LabValue>[] },
    params?: { force?: boolean },
  ): Promise<LabResult> => {
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite<LabResult>(
      profileId,
      newId,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof LabResult)[],
    );
    // Encrypt each value independently
    const rawValues = data.values ?? [];
    const encValues = await Promise.all(
      rawValues.map(async (v) => {
        const vId = v.id ?? crypto.randomUUID();
        const enc = await encryptLabValueForWrite(profileId, vId, v);
        const vBody: Record<string, unknown> = { ...enc.structural, id: vId };
        if (enc.content_enc) vBody.content_enc = enc.content_enc;
        return vBody;
      }),
    );
    const body: Record<string, unknown> = { ...structural, id: newId, values: encValues };
    if (content_enc) body.content_enc = content_enc;
    const qs = params?.force ? '?force=true' : '';
    const raw = await api.post<LabResult>(
      `/api/v1/profiles/${profileId}/labs${qs}`,
      body,
    );
    return decryptLab(profileId, raw);
  },

  update: async (
    profileId: string,
    id: string,
    data: Partial<LabResult> & { values?: Partial<LabValue>[] },
  ): Promise<LabResult> => {
    const { content_enc, structural } = await encryptForWrite<LabResult>(
      profileId,
      id,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof LabResult)[],
    );
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    if (data.values !== undefined) {
      const encValues = await Promise.all(
        data.values.map(async (v) => {
          const vId = v.id ?? crypto.randomUUID();
          const enc = await encryptLabValueForWrite(profileId, vId, v);
          const vBody: Record<string, unknown> = { ...enc.structural, id: vId };
          if (enc.content_enc) vBody.content_enc = enc.content_enc;
          return vBody;
        }),
      );
      body.values = encValues;
    }
    const raw = await api.patch<LabResult>(
      `/api/v1/profiles/${profileId}/labs/${id}`,
      body,
    );
    return decryptLab(profileId, raw);
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/labs/${id}`),
};
