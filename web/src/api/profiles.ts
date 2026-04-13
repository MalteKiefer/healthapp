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
  created_at: string;
  updated_at?: string;
}

export const profilesApi = {
  list: async () => {
    return api.get<{ items: Profile[]; total: number }>('/api/v1/profiles');
  },

  get: async (id: string): Promise<Profile> => {
    return api.get<Profile>(`/api/v1/profiles/${id}`);
  },

  create: async (data: Partial<Profile>): Promise<Profile> => {
    return api.post<Profile>('/api/v1/profiles', data);
  },

  update: async (id: string, data: Partial<Profile>): Promise<Profile> => {
    return api.patch<Profile>(`/api/v1/profiles/${id}`, data);
  },

  delete: (id: string) => api.delete(`/api/v1/profiles/${id}`),
};
