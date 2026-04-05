import { api } from './client';
import { decryptOrPassthrough, encryptForWrite, type EntityBase } from './encryptedEntity';
import {
  encryptProfileContent,
  decryptProfileContent,
  makeAAD,
  getProfileKey,
} from '../crypto';
import { enqueueMigration } from '../utils/migrationQueue';

export interface SymptomEntry {
  id?: string;
  symptom_record_id?: string;
  symptom_type: string;
  custom_label?: string;
  intensity: number;
  body_region?: string;
  duration_minutes?: number;
  content_enc?: string;
}

export interface SymptomRecord extends EntityBase {
  recorded_at: string;
  entries: SymptomEntry[];
  trigger_factors?: string[];
  notes?: string;
  linked_vital_id?: string;
  created_at: string;
  updated_at?: string;
}

export interface SymptomListResponse {
  items: SymptomRecord[];
  total: number;
}

const ENTITY = 'symptom_record';
const CONTENT_FIELDS = ['recorded_at', 'trigger_factors', 'notes'] as const;

const ENTRY_ENTITY = 'symptom_entry';
const ENTRY_CONTENT_FIELDS = [
  'symptom_type', 'custom_label', 'intensity', 'body_region', 'duration_minutes',
] as const;

const migratePath = (r: SymptomRecord) =>
  `/api/v1/profiles/${r.profile_id}/symptoms/${r.id}/migrate-content`;

const entryMigratePath = (profileId: string, recordId: string, entryId: string) =>
  `/api/v1/profiles/${profileId}/symptoms/${recordId}/entries/${entryId}/migrate-content`;

async function decryptSymptomEntry(
  profileId: string,
  recordId: string,
  e: SymptomEntry,
): Promise<SymptomEntry> {
  const key = getProfileKey(profileId);
  if (!key) return e;

  if (e.content_enc) {
    try {
      const content = await decryptProfileContent<Record<string, unknown>>(
        e.content_enc,
        key,
        makeAAD(profileId, ENTRY_ENTITY, e.id!),
      );
      const cleared = { ...e } as Record<string, unknown>;
      for (const k of ENTRY_CONTENT_FIELDS) cleared[k] = undefined;
      return { ...(cleared as unknown as SymptomEntry), ...content };
    } catch (err) {
      console.warn('symptom_entry decrypt failed, falling back', e.id, err);
      return e;
    }
  }

  const content: Record<string, unknown> = {};
  for (const k of ENTRY_CONTENT_FIELDS) {
    const val = (e as unknown as Record<string, unknown>)[k];
    if (val !== undefined) content[k] = val;
  }
  enqueueMigration(`symptom_entry:${profileId}`, async () => {
    const freshKey = getProfileKey(profileId);
    if (!freshKey) return;
    const blob = await encryptProfileContent(
      content,
      freshKey,
      makeAAD(profileId, ENTRY_ENTITY, e.id!),
    );
    await api.patch(entryMigratePath(profileId, recordId, e.id!), { content_enc: blob });
  });
  return e;
}

async function encryptSymptomEntryForWrite(
  profileId: string,
  entryId: string,
  e: Partial<SymptomEntry>,
): Promise<{ content_enc: string | undefined; structural: Partial<SymptomEntry> }> {
  const key = getProfileKey(profileId);
  const content: Record<string, unknown> = {};
  for (const k of ENTRY_CONTENT_FIELDS) {
    const val = (e as unknown as Record<string, unknown>)[k];
    if (val !== undefined) content[k] = val;
  }
  let content_enc: string | undefined;
  if (key && Object.keys(content).length > 0) {
    content_enc = await encryptProfileContent(
      content,
      key,
      makeAAD(profileId, ENTRY_ENTITY, entryId),
    );
  }
  const structural = { ...e } as Record<string, unknown>;
  for (const k of ENTRY_CONTENT_FIELDS) delete structural[k];
  delete structural.content_enc;
  return { content_enc, structural: structural as Partial<SymptomEntry> };
}

async function decryptRecord(
  profileId: string,
  raw: SymptomRecord,
): Promise<SymptomRecord> {
  const top = await decryptOrPassthrough(
    raw,
    ENTITY,
    CONTENT_FIELDS as unknown as readonly (keyof SymptomRecord)[],
    migratePath,
  );
  const entries = await Promise.all(
    (top.entries ?? []).map((e) => decryptSymptomEntry(profileId, top.id, e)),
  );
  return { ...top, entries };
}

export const symptomsApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number },
  ): Promise<SymptomListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    const qs = query.toString();
    const res = await api.get<SymptomListResponse>(
      `/api/v1/profiles/${profileId}/symptoms${qs ? `?${qs}` : ''}`,
    );
    const items = await Promise.all(res.items.map((r) => decryptRecord(profileId, r)));
    return { items, total: res.total };
  },

  get: async (profileId: string, id: string): Promise<SymptomRecord> => {
    const raw = await api.get<SymptomRecord>(`/api/v1/profiles/${profileId}/symptoms/${id}`);
    return decryptRecord(profileId, raw);
  },

  create: async (
    profileId: string,
    data: Partial<SymptomRecord> & { entries?: Partial<SymptomEntry>[] },
  ): Promise<SymptomRecord> => {
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite<SymptomRecord>(
      profileId,
      newId,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof SymptomRecord)[],
    );
    const rawEntries = data.entries ?? [];
    const encEntries = await Promise.all(
      rawEntries.map(async (e) => {
        const eId = e.id ?? crypto.randomUUID();
        const enc = await encryptSymptomEntryForWrite(profileId, eId, e);
        const eBody: Record<string, unknown> = { ...enc.structural, id: eId };
        if (enc.content_enc) eBody.content_enc = enc.content_enc;
        return eBody;
      }),
    );
    const body: Record<string, unknown> = { ...structural, id: newId, entries: encEntries };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<SymptomRecord>(
      `/api/v1/profiles/${profileId}/symptoms`,
      body,
    );
    return decryptRecord(profileId, raw);
  },

  update: async (
    profileId: string,
    id: string,
    data: Partial<SymptomRecord> & { entries?: Partial<SymptomEntry>[] },
  ): Promise<SymptomRecord> => {
    const { content_enc, structural } = await encryptForWrite<SymptomRecord>(
      profileId,
      id,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof SymptomRecord)[],
    );
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    if (data.entries !== undefined) {
      const encEntries = await Promise.all(
        data.entries.map(async (e) => {
          const eId = e.id ?? crypto.randomUUID();
          const enc = await encryptSymptomEntryForWrite(profileId, eId, e);
          const eBody: Record<string, unknown> = { ...enc.structural, id: eId };
          if (enc.content_enc) eBody.content_enc = enc.content_enc;
          return eBody;
        }),
      );
      body.entries = encEntries;
    }
    const raw = await api.patch<SymptomRecord>(
      `/api/v1/profiles/${profileId}/symptoms/${id}`,
      body,
    );
    return decryptRecord(profileId, raw);
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/symptoms/${id}`),
};
