import { api } from './client';

export interface Profile {
  id: string;
  owner_user_id: string;
  display_name: string;
  date_of_birth?: string;
  biological_sex: string;
  blood_type?: string;
  rhesus_factor?: string;
  avatar_color: string;
  avatar_image_enc?: string;
  archived_at?: string;
  onboarding_completed_at?: string;
  rotation_state?: string;
  rotation_started_at?: string;
  rotation_progress?: Record<string, unknown>;
  created_at: string;
  updated_at?: string;
}

export const profilesApi = {
  list: async () => {
    const res = await api.get<{ items: Profile[]; total: number }>('/api/v1/profiles');
    return res.items;
  },
  get: (id: string) => api.get<Profile>(`/api/v1/profiles/${id}`),
  create: (data: Partial<Profile>) => api.post<Profile>('/api/v1/profiles', data),
  update: (id: string, data: Partial<Profile>) => api.patch<Profile>(`/api/v1/profiles/${id}`, data),
  delete: (id: string) => api.delete(`/api/v1/profiles/${id}`),
};
