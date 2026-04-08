import { api } from './client';
import {
  extractContent,
  mergeContent,
  encryptForWrite as encryptEntity,
} from './encryptedEntity';
import {
  encryptProfileContent,
  decryptProfileContent,
  makeAAD,
  getProfileKey,
} from '../crypto';
import { enqueueMigration } from '../utils/migrationQueue';

export interface Profile {
  id: string;
  owner_user_id: string;
  display_name: string;
  date_of_birth?: string;
  biological_sex: string;
  blood_type?: string;
  rhesus_factor?: string;
  avatar_color: string;
  avatar_image_enc?: string;
  content_enc?: string | null;
  archived_at?: string;
  onboarding_completed_at?: string;
  rotation_state?: string;
  rotation_started_at?: string;
  rotation_progress?: Record<string, unknown>;
  created_at: string;
  updated_at?: string;
}

const ENTITY = 'profile';
const CONTENT_FIELDS: readonly (keyof Profile)[] = [
  'date_of_birth', 'biological_sex', 'blood_type', 'rhesus_factor',
];

const migratePath = (p: Profile) =>
  `/api/v1/profiles/${p.id}/migrate-content`;

/**
 * Profile is special: for a Profile row, the profile_id IS the row's own id.
 * This wrapper uses the shared helpers (extractContent, mergeContent) but
 * supplies row.id where other entities would use row.profile_id.
 */
async function decryptOrPassthrough(row: Profile): Promise<Profile> {
  const profileId = row.id;
  const key = getProfileKey(profileId);
  if (!key) return row;

  if (row.content_enc) {
    try {
      const content = await decryptProfileContent<Record<string, unknown>>(
        row.content_enc,
        key,
        makeAAD(profileId, ENTITY, row.id),
      );
      return mergeContent(row, content, CONTENT_FIELDS);
    } catch (err) {
      console.warn('profile decrypt failed, falling back', row.id, err);
      return row;
    }
  }

  // Legacy row -- schedule background migration.
  const content = extractContent(row, CONTENT_FIELDS);
  enqueueMigration(`${ENTITY}:${profileId}`, async () => {
    const freshKey = getProfileKey(profileId);
    if (!freshKey) return;
    const blob = await encryptProfileContent(
      content,
      freshKey,
      makeAAD(profileId, ENTITY, row.id),
    );
    await api.patch(migratePath(row), { content_enc: blob });
  });
  return row;
}

async function encryptForWrite(
  profileId: string,
  data: Partial<Profile>,
): Promise<{ content_enc: string | undefined; structural: Partial<Profile> }> {
  return encryptEntity(profileId, profileId, ENTITY, data, CONTENT_FIELDS);
}

export const profilesApi = {
  list: async () => {
    const res = await api.get<{ items: Profile[]; total: number }>('/api/v1/profiles');
    const items = await Promise.all(
      (res.items || []).map((p) => decryptOrPassthrough(p)),
    );
    return items;
  },
  get: async (id: string): Promise<Profile> => {
    const raw = await api.get<Profile>(`/api/v1/profiles/${id}`);
    return decryptOrPassthrough(raw);
  },
  create: async (data: Partial<Profile>): Promise<Profile> => {
    const newId = data.id || crypto.randomUUID();
    const { content_enc, structural } = await encryptForWrite(newId, data);
    const body: Record<string, unknown> = { ...structural, id: newId };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.post<Profile>('/api/v1/profiles', body);
    return decryptOrPassthrough(raw);
  },
  update: async (id: string, data: Partial<Profile>): Promise<Profile> => {
    const { content_enc, structural } = await encryptForWrite(id, data);
    const body: Record<string, unknown> = { ...structural };
    if (content_enc) body.content_enc = content_enc;
    const raw = await api.patch<Profile>(`/api/v1/profiles/${id}`, body);
    return decryptOrPassthrough(raw);
  },
  delete: (id: string) => api.delete(`/api/v1/profiles/${id}`),
};
