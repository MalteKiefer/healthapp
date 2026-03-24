import { api } from './client';

export interface DiaryEvent {
  id: string;
  profile_id: string;
  title: string;
  event_type: string;
  started_at: string;
  ended_at?: string;
  description?: string;
  severity?: number;
  location?: string;
  outcome?: string;
  created_at: string;
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
  list: (profileId: string, params?: { limit?: number; offset?: number }) => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    const qs = query.toString();
    return api.get<DiaryListResponse>(`/api/v1/profiles/${profileId}/diary${qs ? `?${qs}` : ''}`);
  },
  get: (profileId: string, id: string) =>
    api.get<DiaryEvent>(`/api/v1/profiles/${profileId}/diary/${id}`),
  create: (profileId: string, data: Partial<DiaryEvent>) =>
    api.post<DiaryEvent>(`/api/v1/profiles/${profileId}/diary`, data),
  update: (profileId: string, id: string, data: Partial<DiaryEvent>) =>
    api.patch<DiaryEvent>(`/api/v1/profiles/${profileId}/diary/${id}`, data),
  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/diary/${id}`),
};
