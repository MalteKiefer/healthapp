import { api } from './client';
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

function extractContent(v: Partial<Profile>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const k of CONTENT_FIELDS) {
    const val = (v as Record<string, unknown>)[k as string];
    if (val !== undefined) out[k as string] = val;
  }
  return out;
}

function stripContent(obj: Partial<Profile>): Partial<Profile> {
  const copy = { ...obj } as Record<string, unknown>;
  for (const k of CONTENT_FIELDS) delete copy[k as string];
  delete copy.content_enc;
  return copy as Partial<Profile>;
}

async function decryptOrPassthrough(row: Profile): Promise<Profile> {
  const key = getProfileKey(row.id);
  if (!key) return row;

  if (row.content_enc) {
    try {
      const content = await decryptProfileContent<Record<string, unknown>>(
        row.content_enc,
        key,
        makeAAD(row.id, ENTITY, row.id),
      );
      const cleared = { ...row } as Record<string, unknown>;
      for (const k of CONTENT_FIELDS) cleared[k as string] = undefined;
      return { ...(cleared as unknown as Profile), ...content } as Profile;
    } catch (err) {
      console.warn('profile decrypt failed, falling back', row.id, err);
      return row;
    }
  }

  // Legacy row -- schedule background migration.
  const content = extractContent(row);
  enqueueMigration(`${ENTITY}:${row.id}`, async () => {
    const freshKey = getProfileKey(row.id);
    if (!freshKey) return;
    const blob = await encryptProfileContent(
      content,
      freshKey,
      makeAAD(row.id, ENTITY, row.id),
    );
    await api.patch(migratePath(row), { content_enc: blob });
  });
  return row;
}

async function encryptForWrite(
  profileId: string,
  data: Partial<Profile>,
): Promise<{ content_enc: string | undefined; structural: Partial<Profile> }> {
  const key = getProfileKey(profileId);
  const content = extractContent(data);
  let content_enc: string | undefined;
  if (key && Object.keys(content).length > 0) {
    content_enc = await encryptProfileContent(
      content,
      key,
      makeAAD(profileId, ENTITY, profileId),
    );
  }
  const structural = stripContent(data);
  return { content_enc, structural };
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
