import { api } from './client';

export interface Task {
  title: string;
  due_date?: string;
  priority: string;
  status: string;
  done_at?: string;
  related_diary_event_id?: string;
  related_appointment_id?: string;
  notes?: string;
  created_by_user_id: string;
  created_at: string;
  updated_at?: string;
}

export interface TaskListResponse {
  items: Task[];
  total: number;
}

// due_date/status/done_at stay plaintext (server filters on them).
export const tasksApi = {
  list: async (
    profileId: string,
    params?: { limit?: number; offset?: number; status?: string },
  ): Promise<TaskListResponse> => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    if (params?.status) query.set('status', params.status);
    const qs = query.toString();
    const res = await api.get<TaskListResponse>(
      `/api/v1/profiles/${profileId}/tasks${qs ? `?${qs}` : ''}`,
    );
    return res;
  },

  get: async (profileId: string, id: string): Promise<Task> => {
    const raw = await api.get<Task>(`/api/v1/profiles/${profileId}/tasks/${id}`);
    return raw;
  },

  create: async (profileId: string, data: Partial<Task>): Promise<Task> => {
    return await api.post<Task>(`/api/v1/profiles/${profileId}/tasks`, data);
  },

  update: async (profileId: string, id: string, data: Partial<Task>): Promise<Task> => {
    return await api.patch<Task>(`/api/v1/profiles/${profileId}/tasks/${id}`, data);
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/tasks/${id}`),
};
