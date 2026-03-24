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

export interface ChartPoint {
  measured_at: string;
  values: Record<string, number>;
}

export interface ChartResponse {
  metric: string;
  points: ChartPoint[];
}

export const vitalsApi = {
  list: (profileId: string, params?: { limit?: number; offset?: number; from?: string; to?: string }) => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    if (params?.from) query.set('from', params.from);
    if (params?.to) query.set('to', params.to);
    const qs = query.toString();
    return api.get<VitalListResponse>(`/api/v1/profiles/${profileId}/vitals${qs ? `?${qs}` : ''}`);
  },

  get: (profileId: string, vitalId: string) =>
    api.get<Vital>(`/api/v1/profiles/${profileId}/vitals/${vitalId}`),

  create: (profileId: string, data: Partial<Vital>) =>
    api.post<Vital>(`/api/v1/profiles/${profileId}/vitals`, data),

  update: (profileId: string, vitalId: string, data: Partial<Vital>) =>
    api.patch<Vital>(`/api/v1/profiles/${profileId}/vitals/${vitalId}`, data),

  delete: (profileId: string, vitalId: string) =>
    api.delete(`/api/v1/profiles/${profileId}/vitals/${vitalId}`),

  chart: (profileId: string, metric: string, from?: string, to?: string) => {
    const query = new URLSearchParams({ metric });
    if (from) query.set('from', from);
    if (to) query.set('to', to);
    return api.get<ChartResponse>(`/api/v1/profiles/${profileId}/vitals/chart?${query}`);
  },
};
