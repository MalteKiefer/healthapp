import { api } from './client';
import { decryptOrPassthrough, encryptForWrite, type EntityBase } from './encryptedEntity';

export interface DiaryEvent extends EntityBase {
  title: string;
  event_type: string;
  started_at: string;
  ended_at?: string | null;
  description?: string | null;
  severity?: number | null;
  location?: string | null;
  outcome?: string | null;
  created_at: string;
  updated_at?: string;
}

export interface DiaryListResponse {
  items: DiaryEvent[];
  total: number;
}

const EVENT_TYPES = [
  'accident', 'illness', 'surgery', 'hospital_stay', 'emergency',
  'doctor_visit', 'vaccination', 'medication_change', 'symptom', 'other',
] as const;

export { EVENT_TYPES };

const ENTITY = 'diary_event';
const CONTENT_FIELDS = [
  'title', 'event_type', 'started_at', 'ended_at',
  'description', 'severity', 'location', 'outcome',
] as const;

const migratePath = (r: DiaryEvent) =>
  `/api/v1/profiles/${r.profile_id}/diary/${r.id}/migrate-content`;

export const diaryApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number },
  ): Promise<DiaryListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    const qs = query.toString();
    const res = await api.get<DiaryListResponse>(
      `/api/v1/profiles/${profileId}/diary${qs ? `?${qs}` : ''}`,
    );
    const items = await Promise.all(
      res.items.map((r) =>
        decryptOrPassthrough(
          r,
          ENTITY,
          CONTENT_FIELDS as unknown as readonly (keyof DiaryEvent)[],
          migratePath,
        ),
      ),
    );
    return { items, total: res.total };
  },

  get: async (profileId: string, id: string): Promise<DiaryEvent> => {
    const raw = await api.get<DiaryEvent>(`/api/v1/profiles/${profileId}/diary/${id}`);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof DiaryEvent)[],
      migratePath,
    );
  },

  create: async (profileId: string, data: Partial<DiaryEvent>): Promise<DiaryEvent> => {
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite<DiaryEvent>(
      profileId,
      newId,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof DiaryEvent)[],
    );
    const body: Record<string, unknown> = { ...structural, id: newId };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<DiaryEvent>(`/api/v1/profiles/${profileId}/diary`, body);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof DiaryEvent)[],
      migratePath,
    );
  },

  update: async (
    profileId: string,
    id: string,
    data: Partial<DiaryEvent>,
  ): Promise<DiaryEvent> => {
    const { content_enc, structural } = await encryptForWrite<DiaryEvent>(
      profileId,
      id,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof DiaryEvent)[],
    );
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.patch<DiaryEvent>(
      `/api/v1/profiles/${profileId}/diary/${id}`,
      body,
    );
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof DiaryEvent)[],
      migratePath,
    );
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/diary/${id}`),
};
