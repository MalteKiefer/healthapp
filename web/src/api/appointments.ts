import { api } from './client';
import { decryptOrPassthrough, encryptForWrite, type EntityBase } from './encryptedEntity';

export interface Appointment extends EntityBase {
  title: string;
  appointment_type: string;
  scheduled_at: string;
  duration_minutes?: number;
  doctor_id?: string;
  location?: string;
  preparation_notes?: string;
  reminder_days_before?: number[];
  status: string;
  linked_diary_event_id?: string;
  recurrence: string;
  created_at: string;
  updated_at?: string;
}

export interface AppointmentListResponse {
  items: Appointment[];
  total: number;
}

const ENTITY = 'appointment';
// scheduled_at, duration_minutes, status stay plaintext (server filters).
const CONTENT_FIELDS = [
  'title', 'appointment_type', 'location', 'preparation_notes',
  'reminder_days_before', 'recurrence',
] as const;

const migratePath = (r: Appointment) =>
  `/api/v1/profiles/${r.profile_id}/appointments/${r.id}/migrate-content`;

export const appointmentsApi = {
  list: async (profileId: string): Promise<AppointmentListResponse> => {
    const res = await api.get<AppointmentListResponse>(
      `/api/v1/profiles/${profileId}/appointments`,
    );
    const items = await Promise.all(
      (res.items || []).map((r) =>
        decryptOrPassthrough(
          r,
          ENTITY,
          CONTENT_FIELDS as unknown as readonly (keyof Appointment)[],
          migratePath,
        ),
      ),
    );
    return { items, total: res.total };
  },

  upcoming: async (profileId: string): Promise<AppointmentListResponse> => {
    const res = await api.get<AppointmentListResponse>(
      `/api/v1/profiles/${profileId}/appointments/upcoming`,
    );
    const items = await Promise.all(
      (res.items || []).map((r) =>
        decryptOrPassthrough(
          r,
          ENTITY,
          CONTENT_FIELDS as unknown as readonly (keyof Appointment)[],
          migratePath,
        ),
      ),
    );
    return { items, total: res.total };
  },

  create: async (profileId: string, data: Partial<Appointment>): Promise<Appointment> => {
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite<Appointment>(
      profileId,
      newId,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Appointment)[],
    );
    const body: Record<string, unknown> = { ...structural, id: newId };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<Appointment>(
      `/api/v1/profiles/${profileId}/appointments`,
      body,
    );
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Appointment)[],
      migratePath,
    );
  },

  update: async (
    profileId: string,
    id: string,
    data: Partial<Appointment>,
  ): Promise<Appointment> => {
    const { content_enc, structural } = await encryptForWrite<Appointment>(
      profileId,
      id,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Appointment)[],
    );
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.patch<Appointment>(
      `/api/v1/profiles/${profileId}/appointments/${id}`,
      body,
    );
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Appointment)[],
      migratePath,
    );
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/appointments/${id}`),

  complete: (profileId: string, id: string) =>
    api.post(`/api/v1/profiles/${profileId}/appointments/${id}/complete`),
};
