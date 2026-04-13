import { api } from './client';

export interface SymptomEntry {
  id?: string;
  symptom_record_id?: string;
  symptom_type: string;
  custom_label?: string;
  intensity: number;
  body_region?: string;
  duration_minutes?: number;
}

export interface SymptomRecord {
  id?: string;
  profile_id?: string;
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

export const symptomsApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number },
  ): Promise<SymptomListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    const qs = query.toString();
    return api.get<SymptomListResponse>(
      `/api/v1/profiles/${profileId}/symptoms${qs ? `?${qs}` : ''}`,
    );
  },

  get: async (profileId: string, id: string): Promise<SymptomRecord> => {
    return api.get<SymptomRecord>(`/api/v1/profiles/${profileId}/symptoms/${id}`);
  },

  create: async (
    profileId: string,
    data: Partial<SymptomRecord> & { entries?: Partial<SymptomEntry>[] },
  ): Promise<SymptomRecord> => {
    return api.post<SymptomRecord>(`/api/v1/profiles/${profileId}/symptoms`, data);
  },

  update: async (
    profileId: string,
    id: string,
    data: Partial<SymptomRecord> & { entries?: Partial<SymptomEntry>[] },
  ): Promise<SymptomRecord> => {
    return api.patch<SymptomRecord>(`/api/v1/profiles/${profileId}/symptoms/${id}`, data);
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/symptoms/${id}`),
};
