import { api } from './client';
import { decryptOrPassthrough, encryptForWrite, type EntityBase } from './encryptedEntity';

export type DiagnosisStatus =
  | 'active'
  | 'resolved'
  | 'chronic'
  | 'in_remission'
  | 'suspected';

export interface Diagnosis extends EntityBase {
  name: string;
  icd10_code?: string;
  status: DiagnosisStatus;
  diagnosed_at?: string;
  diagnosed_by?: string;
  resolved_at?: string;
  notes?: string;
  version?: number;
  previous_id?: string;
  is_current?: boolean;
  created_at: string;
  updated_at?: string;
}

export interface DiagnosisListResponse {
  items: Diagnosis[];
  total: number;
}

const ENTITY = 'diagnosis';
const CONTENT_FIELDS = [
  'name', 'icd10_code', 'status', 'diagnosed_at',
  'diagnosed_by', 'resolved_at', 'notes',
] as const;

const migratePath = (r: Diagnosis) =>
  `/api/v1/profiles/${r.profile_id}/diagnoses/${r.id}/migrate-content`;

export const diagnosesApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number; status?: DiagnosisStatus },
  ): Promise<DiagnosisListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    if (params?.status) query.set('status', params.status);
    const qs = query.toString();
    const res = await api.get<DiagnosisListResponse>(
      `/api/v1/profiles/${profileId}/diagnoses${qs ? `?${qs}` : ''}`,
    );
    const items = await Promise.all(
      (res.items || []).map((r) =>
        decryptOrPassthrough(
          r,
          ENTITY,
          CONTENT_FIELDS as unknown as readonly (keyof Diagnosis)[],
          migratePath,
        ),
      ),
    );
    return { items, total: res.total };
  },

  get: async (profileId: string, id: string): Promise<Diagnosis> => {
    const raw = await api.get<Diagnosis>(`/api/v1/profiles/${profileId}/diagnoses/${id}`);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Diagnosis)[],
      migratePath,
    );
  },

  create: async (profileId: string, data: Partial<Diagnosis>): Promise<Diagnosis> => {
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite<Diagnosis>(
      profileId,
      newId,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Diagnosis)[],
    );
    const body: Record<string, unknown> = { ...structural, id: newId };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<Diagnosis>(`/api/v1/profiles/${profileId}/diagnoses`, body);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Diagnosis)[],
      migratePath,
    );
  },

  update: async (profileId: string, id: string, data: Partial<Diagnosis>): Promise<Diagnosis> => {
    const { content_enc, structural } = await encryptForWrite<Diagnosis>(
      profileId,
      id,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Diagnosis)[],
    );
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.patch<Diagnosis>(
      `/api/v1/profiles/${profileId}/diagnoses/${id}`,
      body,
    );
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Diagnosis)[],
      migratePath,
    );
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/diagnoses/${id}`),
};
