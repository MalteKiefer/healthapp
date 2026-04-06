import { api } from './client';
import { decryptOrPassthrough, encryptForWrite, type EntityBase } from './encryptedEntity';

export interface Vaccination extends EntityBase {
  vaccine_name: string;
  trade_name?: string;
  manufacturer?: string;
  lot_number?: string;
  dose_number?: number;
  administered_at: string;
  administered_by?: string;
  next_due_at?: string;
  site?: string;
  notes?: string;
  document_id?: string;
  version?: number;
  previous_id?: string;
  is_current?: boolean;
  created_at: string;
  updated_at?: string;
}

export interface VaccinationListResponse {
  items: Vaccination[];
  total: number;
}

const ENTITY = 'vaccination';
// administered_at, next_due_at stay plaintext.
const CONTENT_FIELDS = [
  'vaccine_name', 'trade_name', 'manufacturer', 'lot_number',
  'dose_number', 'administered_by', 'site', 'notes',
] as const;

const migratePath = (r: Vaccination) =>
  `/api/v1/profiles/${r.profile_id}/vaccinations/${r.id}/migrate-content`;

export const vaccinationsApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number },
  ): Promise<VaccinationListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    const qs = query.toString();
    const res = await api.get<VaccinationListResponse>(
      `/api/v1/profiles/${profileId}/vaccinations${qs ? `?${qs}` : ''}`,
    );
    const items = await Promise.all(
      (res.items || []).map((r) =>
        decryptOrPassthrough(
          r,
          ENTITY,
          CONTENT_FIELDS as unknown as readonly (keyof Vaccination)[],
          migratePath,
        ),
      ),
    );
    return { items, total: res.total };
  },

  get: async (profileId: string, id: string): Promise<Vaccination> => {
    const raw = await api.get<Vaccination>(
      `/api/v1/profiles/${profileId}/vaccinations/${id}`,
    );
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Vaccination)[],
      migratePath,
    );
  },

  create: async (profileId: string, data: Partial<Vaccination>): Promise<Vaccination> => {
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite<Vaccination>(
      profileId,
      newId,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Vaccination)[],
    );
    const body: Record<string, unknown> = { ...structural, id: newId };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<Vaccination>(
      `/api/v1/profiles/${profileId}/vaccinations`,
      body,
    );
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Vaccination)[],
      migratePath,
    );
  },

  update: async (
    profileId: string,
    id: string,
    data: Partial<Vaccination>,
  ): Promise<Vaccination> => {
    const { content_enc, structural } = await encryptForWrite<Vaccination>(
      profileId,
      id,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Vaccination)[],
    );
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.patch<Vaccination>(
      `/api/v1/profiles/${profileId}/vaccinations/${id}`,
      body,
    );
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Vaccination)[],
      migratePath,
    );
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/vaccinations/${id}`),
};
