import { api } from './client';

export interface Appointment {
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

// scheduled_at, duration_minutes, status stay plaintext (server filters).
export const appointmentsApi = {
  list: async (profileId: string): Promise<AppointmentListResponse> => {
    const res = await api.get<AppointmentListResponse>(
      `/api/v1/profiles/${profileId}/appointments`,
    );
    return res;
  },

  // upcoming endpoint removed (410 Gone) — use list() + client-side filter instead.

  create: async (profileId: string, data: Partial<Appointment>): Promise<Appointment> => {
    return api.post<Appointment>(`/api/v1/profiles/${profileId}/appointments`, data);
  },

  update: async (profileId: string, id: string, data: Partial<Appointment>): Promise<Appointment> => {
    return api.patch<Appointment>(`/api/v1/profiles/${profileId}/appointments/${id}`, data);
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/appointments/${id}`),

  complete: (profileId: string, id: string) =>
    api.post(`/api/v1/profiles/${profileId}/appointments/${id}/complete`),
};
