import { api } from './client';

export type DiagnosisStatus =
  | 'active'
  | 'resolved'
  | 'chronic'
  | 'in_remission'
  | 'suspected';

export interface Diagnosis {
  id: string;
  profile_id: string;
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
    return res;
  },

  get: async (profileId: string, id: string): Promise<Diagnosis> => {
    const raw = await api.get<Diagnosis>(`/api/v1/profiles/${profileId}/diagnoses/${id}`);
    return raw;
  },

  create: async (profileId: string, data: Partial<Diagnosis>): Promise<Diagnosis> => {
    return await api.post<Diagnosis>(`/api/v1/profiles/${profileId}/diagnoses`, data);
  },

  update: async (profileId: string, id: string, data: Partial<Diagnosis>): Promise<Diagnosis> => {
    return api.patch<Diagnosis>(
      `/api/v1/profiles/${profileId}/diagnoses/${id}`,
      data,
    );
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/diagnoses/${id}`),
};
