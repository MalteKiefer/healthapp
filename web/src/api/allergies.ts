import { api } from './client';

export interface Allergy {
  id: string;
  profile_id: string;
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

export const allergiesApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number },
  ): Promise<AllergyListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    const qs = query.toString();
    return api.get<AllergyListResponse>(
      `/api/v1/profiles/${profileId}/allergies${qs ? `?${qs}` : ''}`,
    );
  },

  get: async (profileId: string, id: string): Promise<Allergy> => {
    return api.get<Allergy>(`/api/v1/profiles/${profileId}/allergies/${id}`);
  },

  create: async (profileId: string, data: Partial<Allergy>): Promise<Allergy> => {
    return api.post<Allergy>(`/api/v1/profiles/${profileId}/allergies`, data);
  },

  update: async (profileId: string, id: string, data: Partial<Allergy>): Promise<Allergy> => {
    return api.patch<Allergy>(`/api/v1/profiles/${profileId}/allergies/${id}`, data);
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/allergies/${id}`),
};
