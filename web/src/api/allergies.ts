import { api } from './client';
import { decryptOrPassthrough, encryptForWrite, type EntityBase } from './encryptedEntity';

export interface Allergy extends EntityBase {
  name: string;
  category?: string;
  reaction_type?: string;
  severity?: string;
  onset_date?: string;
  diagnosed_by?: string;
  notes?: string;
  status?: string;
  version?: number;
  previous_id?: string;
  is_current?: boolean;
  created_at: string;
  updated_at?: string;
}

export interface AllergyListResponse {
  items: Allergy[];
  total: number;
}

const ENTITY = 'allergy';
const CONTENT_FIELDS = [
  'name', 'category', 'reaction_type', 'severity',
  'onset_date', 'diagnosed_by', 'notes', 'status',
] as const;

const migratePath = (r: Allergy) =>
  `/api/v1/profiles/${r.profile_id}/allergies/${r.id}/migrate-content`;

export const allergiesApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number },
  ): Promise<AllergyListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    const qs = query.toString();
    const res = await api.get<AllergyListResponse>(
      `/api/v1/profiles/${profileId}/allergies${qs ? `?${qs}` : ''}`,
    );
    const items = await Promise.all(
      (res.items || []).map((r) =>
        decryptOrPassthrough(
          r,
          ENTITY,
          CONTENT_FIELDS as unknown as readonly (keyof Allergy)[],
          migratePath,
        ),
      ),
    );
    return { items, total: res.total };
  },

  get: async (profileId: string, id: string): Promise<Allergy> => {
    const raw = await api.get<Allergy>(`/api/v1/profiles/${profileId}/allergies/${id}`);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Allergy)[],
      migratePath,
    );
  },

  create: async (profileId: string, data: Partial<Allergy>): Promise<Allergy> => {
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite<Allergy>(
      profileId,
      newId,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Allergy)[],
    );
    const body: Record<string, unknown> = { ...structural, id: newId };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<Allergy>(`/api/v1/profiles/${profileId}/allergies`, body);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Allergy)[],
      migratePath,
    );
  },

  update: async (profileId: string, id: string, data: Partial<Allergy>): Promise<Allergy> => {
    const { content_enc, structural } = await encryptForWrite<Allergy>(
      profileId,
      id,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Allergy)[],
    );
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.patch<Allergy>(`/api/v1/profiles/${profileId}/allergies/${id}`, body);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Allergy)[],
      migratePath,
    );
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/allergies/${id}`),
};
