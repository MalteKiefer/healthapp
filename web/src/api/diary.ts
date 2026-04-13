import { api } from './client';

export interface DiaryEvent {
  title: string;
  event_type: string;
  started_at: string;
  ended_at?: string;
  description?: string;
  severity?: number;
  location?: string;
  outcome?: string;
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
    return res;
  },

  get: async (profileId: string, id: string): Promise<DiaryEvent> => {
    const raw = await api.get<DiaryEvent>(`/api/v1/profiles/${profileId}/diary/${id}`);
    return raw;
  },

  create: async (profileId: string, data: Partial<DiaryEvent>): Promise<DiaryEvent> => {
    return await api.post<DiaryEvent>(`/api/v1/profiles/${profileId}/diary`, data);
  },

  update: async (profileId: string, id: string, data: Partial<DiaryEvent>): Promise<DiaryEvent> => {
    return api.patch<DiaryEvent>(`/api/v1/profiles/${profileId}/diary/${id}`, data);
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/diary/${id}`),
};
