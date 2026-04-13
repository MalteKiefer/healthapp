import { api } from './client';

export interface Contact {
  contact_type: string;
  name: string;
  specialty?: string;
  facility?: string;
  phone?: string;
  email?: string;
  street?: string;
  postal_code?: string;
  city?: string;
  country?: string;
  latitude?: number;
  longitude?: number;
  address?: string;
  notes?: string;
  is_emergency_contact: boolean;
  created_at: string;
  updated_at?: string;
}

export interface ContactListResponse {
  items: Contact[];
  total: number;
}

export const contactsApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number },
  ): Promise<ContactListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    const qs = query.toString();
    const res = await api.get<ContactListResponse>(
      `/api/v1/profiles/${profileId}/contacts${qs ? `?${qs}` : ''}`,
    );
    return res;
  },

  get: async (profileId: string, id: string): Promise<Contact> => {
    const raw = await api.get<Contact>(`/api/v1/profiles/${profileId}/contacts/${id}`);
    return raw;
  },

  create: async (profileId: string, data: Partial<Contact>): Promise<Contact> => {
    return await api.post<Contact>(`/api/v1/profiles/${profileId}/contacts`, data);
  },

  update: async (profileId: string, id: string, data: Partial<Contact>): Promise<Contact> => {
    return await api.patch<Contact>(`/api/v1/profiles/${profileId}/contacts/${id}`, data);
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/contacts/${id}`),
};
