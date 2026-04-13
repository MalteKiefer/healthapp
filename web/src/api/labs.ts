import { api } from './client';

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
}

export interface LabResult {
  id?: string;
  profile_id?: string;
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

export const labsApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number },
  ): Promise<LabListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    const qs = query.toString();
    return api.get<LabListResponse>(
      `/api/v1/profiles/${profileId}/labs${qs ? `?${qs}` : ''}`,
    );
  },

  get: async (profileId: string, id: string): Promise<LabResult> => {
    return api.get<LabResult>(`/api/v1/profiles/${profileId}/labs/${id}`);
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
    const qs = params?.force ? '?force=true' : '';
    return api.post<LabResult>(`/api/v1/profiles/${profileId}/labs${qs}`, data);
  },

  update: async (
    profileId: string,
    id: string,
    data: Partial<LabResult> & { values?: Partial<LabValue>[] },
  ): Promise<LabResult> => {
    return api.patch<LabResult>(`/api/v1/profiles/${profileId}/labs/${id}`, data);
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/labs/${id}`),
};
