import { api } from './client';

export interface Medication {
  id: string;
  profile_id: string;
  name: string;
  dosage?: string;
  unit?: string;
  frequency?: string;
  route?: string;
  started_at?: string;
  ended_at?: string;
  prescribed_by?: string;
  reason?: string;
  notes?: string;
  created_at: string;
}

export interface MedicationListResponse {
  items: Medication[];
  total: number;
}

export const medicationsApi = {
  list: (profileId: string) =>
    api.get<MedicationListResponse>(`/api/v1/profiles/${profileId}/medications`),
  active: (profileId: string) =>
    api.get<MedicationListResponse>(`/api/v1/profiles/${profileId}/medications/active`),
  create: (profileId: string, data: Partial<Medication>) =>
    api.post<Medication>(`/api/v1/profiles/${profileId}/medications`, data),
  update: (profileId: string, id: string, data: Partial<Medication>) =>
    api.patch<Medication>(`/api/v1/profiles/${profileId}/medications/${id}`, data),
  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/medications/${id}`),
};
