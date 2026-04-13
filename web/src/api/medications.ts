import { api } from './client';

export interface Medication {
  id?: string;
  profile_id?: string;
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
  related_diagnosis_id?: string;
  version?: number;
  previous_id?: string;
  is_current?: boolean;
  created_at: string;
  updated_at?: string;
}

export interface MedicationListResponse {
  items: Medication[];
  total: number;
}

export interface MedicationIntake {
  id?: string;
  medication_id: string;
  profile_id?: string;
  scheduled_at: string;
  taken_at?: string;
  dose_taken?: string;
  skipped_reason?: string;
  notes?: string;
  created_at: string;
}

export interface MedicationIntakeListResponse {
  items: MedicationIntake[];
  total: number;
}

export const medicationsApi = {
  list: async (profileId: string): Promise<MedicationListResponse> => {
    return api.get<MedicationListResponse>(`/api/v1/profiles/${profileId}/medications`);
  },

  get: async (profileId: string, id: string): Promise<Medication> => {
    return api.get<Medication>(`/api/v1/profiles/${profileId}/medications/${id}`);
  },

  create: async (profileId: string, data: Partial<Medication>): Promise<Medication> => {
    return api.post<Medication>(`/api/v1/profiles/${profileId}/medications`, data);
  },

  update: async (profileId: string, id: string, data: Partial<Medication>): Promise<Medication> => {
    return api.patch<Medication>(`/api/v1/profiles/${profileId}/medications/${id}`, data);
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/medications/${id}`),

  // ----- Intake sub-resource -----
  listIntake: async (
    profileId: string,
    medicationId: string,
  ): Promise<MedicationIntakeListResponse> => {
    return api.get<MedicationIntakeListResponse>(
      `/api/v1/profiles/${profileId}/medications/${medicationId}/intake`,
    );
  },

  createIntake: async (
    profileId: string,
    medicationId: string,
    data: Partial<MedicationIntake>,
  ): Promise<MedicationIntake> => {
    return api.post<MedicationIntake>(
      `/api/v1/profiles/${profileId}/medications/${medicationId}/intake`,
      data,
    );
  },

  updateIntake: async (
    profileId: string,
    medicationId: string,
    intakeId: string,
    data: Partial<MedicationIntake>,
  ): Promise<MedicationIntake> => {
    return api.patch<MedicationIntake>(
      `/api/v1/profiles/${profileId}/medications/${medicationId}/intake/${intakeId}`,
      data,
    );
  },

  deleteIntake: (profileId: string, medicationId: string, intakeId: string) =>
    api.delete(
      `/api/v1/profiles/${profileId}/medications/${medicationId}/intake/${intakeId}`,
    ),
};
