import { api } from './client';
import { decryptOrPassthrough, encryptForWrite, type EntityBase } from './encryptedEntity';

export interface Task extends EntityBase {
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

const ENTITY = 'task';
// due_date/status/done_at stay plaintext (server filters on them).
const CONTENT_FIELDS = ['title', 'priority', 'notes'] as const;

const migratePath = (r: Task) =>
  `/api/v1/profiles/${r.profile_id}/tasks/${r.id}/migrate-content`;

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
    const items = await Promise.all(
      res.items.map((r) =>
        decryptOrPassthrough(
          r,
          ENTITY,
          CONTENT_FIELDS as unknown as readonly (keyof Task)[],
          migratePath,
        ),
      ),
    );
    return { items, total: res.total };
  },

  get: async (profileId: string, id: string): Promise<Task> => {
    const raw = await api.get<Task>(`/api/v1/profiles/${profileId}/tasks/${id}`);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Task)[],
      migratePath,
    );
  },

  create: async (profileId: string, data: Partial<Task>): Promise<Task> => {
    const newId = crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite<Task>(
      profileId,
      newId,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Task)[],
    );
    const body: Record<string, unknown> = { ...structural, id: newId };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<Task>(`/api/v1/profiles/${profileId}/tasks`, body);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Task)[],
      migratePath,
    );
  },

  update: async (profileId: string, id: string, data: Partial<Task>): Promise<Task> => {
    const { content_enc, structural } = await encryptForWrite<Task>(
      profileId,
      id,
      ENTITY,
      data,
      CONTENT_FIELDS as unknown as readonly (keyof Task)[],
    );
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.patch<Task>(`/api/v1/profiles/${profileId}/tasks/${id}`, body);
    return decryptOrPassthrough(
      raw,
      ENTITY,
      CONTENT_FIELDS as unknown as readonly (keyof Task)[],
      migratePath,
    );
  },

  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/tasks/${id}`),
};
