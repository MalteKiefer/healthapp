import { api } from './client';

export interface Vital {
  id: string;
  profile_id: string;
  blood_pressure_systolic?: number;
  blood_pressure_diastolic?: number;
  pulse?: number;
  oxygen_saturation?: number;
  weight?: number;
  height?: number;
  body_temperature?: number;
  blood_glucose?: number;
  respiratory_rate?: number;
  waist_circumference?: number;
  hip_circumference?: number;
  body_fat_percentage?: number;
  bmi?: number;
  sleep_duration_minutes?: number;
  sleep_quality?: number;
  measured_at: string;
  device?: string;
  notes?: string;
  created_at: string;
}

export interface VitalListResponse {
  items: Vital[];
  total: number;
}

export const vitalsApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number; from?: string; to?: string },
  ): Promise<VitalListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    if (params?.from) query.set('from', params.from);
    if (params?.to) query.set('to', params.to);
    const qs = query.toString();
    const res = await api.get<VitalListResponse>(
      `/api/v1/profiles/${profileId}/vitals${qs ? `?${qs}` : ''}`,
    );
    
    return res;
  },

  get: async (profileId: string, vitalId: string): Promise<Vital> => {
    return await api.get<Vital>(`/api/v1/profiles/${profileId}/vitals/${vitalId}`);
  },

  create: async (profileId: string, data: Partial<Vital>): Promise<Vital> => {
    // We need the server-assigned id for AAD. Strategy: generate the id
    // client-side (UUIDv4), send it with the payload so the AAD binds.
    return await api.post<Vital>(`/api/v1/profiles/${profileId}/vitals`, data);
  },

  update: async (profileId: string, vitalId: string, data: Partial<Vital>): Promise<Vital> => {
    return await api.patch<Vital>(
      `/api/v1/profiles/${profileId}/vitals/${vitalId}`,
      data,
    );
  },

  delete: (profileId: string, vitalId: string) =>
    api.delete(`/api/v1/profiles/${profileId}/vitals/${vitalId}`),
};
