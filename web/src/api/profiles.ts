import { api } from './client';

export interface Profile {
  id: string;
  owner_user_id: string;
  display_name: string;
  date_of_birth?: string;
  biological_sex: string;
  blood_type: string;
  rhesus_factor: string;
  avatar_color: string;
  archived_at?: string;
  created_at: string;
}

export interface ProfileListResponse {
  items: Profile[];
}

export const profilesApi = {
  list: () => api.get<ProfileListResponse>('/api/v1/profiles'),
  get: (id: string) => api.get<Profile>(`/api/v1/profiles/${id}`),
  create: (data: Partial<Profile>) => api.post<Profile>('/api/v1/profiles', data),
  update: (id: string, data: Partial<Profile>) => api.patch<Profile>(`/api/v1/profiles/${id}`, data),
  delete: (id: string) => api.delete(`/api/v1/profiles/${id}`),
};
