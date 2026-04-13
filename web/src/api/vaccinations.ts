import { api } from './client';

export interface Vaccination {
  id: string;
  profile_id: string;
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

// administered_at, next_due_at stay plaintext.
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
    return res;
  },

  get: async (profileId: string, id: string): Promise<Vaccination> => {
    const raw = await api.get<Vaccination>(
      `/api/v1/profiles/${profileId}/vaccinations/${id}`,
    );
    return raw;
  },

  create: async (profileId: string, data: Partial<Vaccination>): Promise<Vaccination> => {
    return api.post<Vaccination>(`/api/v1/profiles/${profileId}/vaccinations`, data);
  },

  update: async (profileId: string, id: string, data: Partial<Vaccination>): Promise<Vaccination> => {
    return api.patch<Vaccination>(`/api/v1/profiles/${profileId}/vaccinations/${id}`, data);
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/vaccinations/${id}`),
};
