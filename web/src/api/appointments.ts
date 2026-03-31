import { api } from './client';

export interface Appointment {
  id: string;
  profile_id: string;
  title: string;
  appointment_type: string;
  scheduled_at: string;
  duration_minutes?: number;
  doctor_id?: string;
  location?: string;
  preparation_notes?: string;
  status: string;
  recurrence: string;
  created_at: string;
}

export interface AppointmentListResponse {
  items: Appointment[];
}

export const appointmentsApi = {
  list: (profileId: string) =>
    api.get<AppointmentListResponse>(`/api/v1/profiles/${profileId}/appointments`),
  upcoming: (profileId: string) =>
    api.get<AppointmentListResponse>(`/api/v1/profiles/${profileId}/appointments/upcoming`),
  create: (profileId: string, data: Partial<Appointment>) =>
    api.post<Appointment>(`/api/v1/profiles/${profileId}/appointments`, data),
  update: (profileId: string, id: string, data: Partial<Appointment>) =>
    api.patch<Appointment>(`/api/v1/profiles/${profileId}/appointments/${id}`, data),
  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/appointments/${id}`),
  complete: (profileId: string, id: string) =>
    api.post(`/api/v1/profiles/${profileId}/appointments/${id}/complete`),
};
