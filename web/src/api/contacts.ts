import { api } from './client';
import { decryptOrPassthrough, encryptForWrite, type EntityBase } from './encryptedEntity';

export interface Contact extends EntityBase {
  contact_type: string;
  name: string;
  specialty?: string | null;
  facility?: string | null;
  phone?: string | null;
  email?: string | null;
  street?: string | null;
  postal_code?: string | null;
  city?: string | null;
  country?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  address?: string | null;
  notes?: string | null;
  is_emergency_contact: boolean;
  created_at: string;
  updated_at?: string;
}

export interface ContactListResponse {
  items: Contact[];
  total: number;
}

const ENTITY = 'medical_contact';
const CONTENT_FIELDS = [
  'name', 'specialty', 'facility', 'phone', 'email',
  'street', 'postal_code', 'city', 'country', 'address',
  'latitude', 'longitude', 'notes', 'is_emergency_contact', 'contact_type',
] as const;

const migratePath = (r: Contact) =>
  `/api/v1/profiles/${r.profile_id}/contacts/${r.id}/migrate-content`;

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
    const items = await Promise.all(
      res.items.map((r) =>
        decryptOrPassthrough(
          r,
          ENTITY,
          CONTENT_FIELDS as unknown as readonly (keyof Contact)[],
          migratePath,
        ),
      ),
    );
    return { items, total: res.total };
  },

  get: async (profileId: string, id: string): Promise<Contact> => {
    const raw = await api.get<Contact>(`/api/v1/profiles/${profileId}/contacts/${id}`);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Contact)[],
      migratePath,
    );
  },

  create: async (profileId: string, data: Partial<Contact>): Promise<Contact> => {
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite<Contact>(
      profileId,
      newId,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Contact)[],
    );
    const body: Record<string, unknown> = { ...structural, id: newId };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<Contact>(`/api/v1/profiles/${profileId}/contacts`, body);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Contact)[],
      migratePath,
    );
  },

  update: async (profileId: string, id: string, data: Partial<Contact>): Promise<Contact> => {
    const { content_enc, structural } = await encryptForWrite<Contact>(
      profileId,
      id,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Contact)[],
    );
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.patch<Contact>(`/api/v1/profiles/${profileId}/contacts/${id}`, body);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Contact)[],
      migratePath,
    );
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/contacts/${id}`),
};
