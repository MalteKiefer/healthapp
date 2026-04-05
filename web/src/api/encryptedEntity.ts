/**
 * Shared encrypt/decrypt wrappers for profile-scoped entities under Stage 2.
 *
 * Each entity has a set of "content fields" — the health/personal data that
 * must be encrypted under the profile key. These helpers:
 *
 *  - extractContent(): pluck the content fields off a row
 *  - stripContent():   remove content fields from an object (used before POST)
 *  - mergeContent():   replace plaintext fields on a row with decrypted blob
 *  - encryptForWrite(): build the content_enc blob for a row before POST
 *  - decryptOrPassthrough(): decrypt incoming rows; if no content_enc, use
 *                            the plaintext fields and schedule a background
 *                            migrate-content PATCH so the next read is clean.
 */

import { api } from './client';
import {
  encryptProfileContent,
  decryptProfileContent,
  makeAAD,
  getProfileKey,
} from '../crypto';
import { enqueueMigration } from '../utils/migrationQueue';

export interface EntityBase {
  id: string;
  profile_id: string;
  content_enc?: string | null;
}

/** Pluck content fields from a row. Fields missing from the source are skipped. */
export function extractContent<T extends object>(
  v: Partial<T>,
  contentFields: readonly (keyof T)[],
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const k of contentFields) {
    const val = (v as Record<string, unknown>)[k as string];
    if (val !== undefined) out[k as string] = val;
  }
  return out;
}

/** Return a copy of `obj` without the listed content field keys (and content_enc). */
export function stripContent<T extends object>(
  obj: Partial<T>,
  contentFields: readonly (keyof T)[],
): Partial<T> {
  const copy = { ...obj } as Record<string, unknown>;
  for (const k of contentFields) delete copy[k as string];
  delete copy.content_enc;
  return copy as Partial<T>;
}

/** Clear plaintext content fields on a row, then splat the decrypted blob on top. */
export function mergeContent<T extends object>(
  base: T,
  content: Record<string, unknown>,
  contentFields: readonly (keyof T)[],
): T {
  const cleared = { ...base } as Record<string, unknown>;
  for (const k of contentFields) cleared[k as string] = undefined;
  return { ...(cleared as unknown as T), ...content } as T;
}

/** Try to decrypt a row. Falls back to plaintext fields + fires background migrate. */
export async function decryptOrPassthrough<T extends EntityBase>(
  row: T,
  entityName: string,
  contentFields: readonly (keyof T)[],
  migratePath: (r: T) => string,
): Promise<T> {
  const key = getProfileKey(row.profile_id);
  if (!key) return row;

  if (row.content_enc) {
    try {
      const content = await decryptProfileContent<Record<string, unknown>>(
        row.content_enc,
        key,
        makeAAD(row.profile_id, entityName, row.id),
      );
      return mergeContent(row, content, contentFields);
    } catch (err) {
      console.warn(`${entityName} decrypt failed, falling back`, row.id, err);
      return row;
    }
  }

  // Legacy row → schedule background migration.
  const content = extractContent(row, contentFields);
  enqueueMigration(`${entityName}:${row.profile_id}`, async () => {
    const freshKey = getProfileKey(row.profile_id);
    if (!freshKey) return;
    const blob = await encryptProfileContent(
      content,
      freshKey,
      makeAAD(row.profile_id, entityName, row.id),
    );
    await api.patch(migratePath(row), { content_enc: blob });
  });
  return row;
}

/** Build the content_enc blob for a write, plus stripped structural fields. */
export async function encryptForWrite<T extends EntityBase>(
  profileId: string,
  rowId: string,
  entityName: string,
  data: Partial<T>,
  contentFields: readonly (keyof T)[],
): Promise<{ content_enc: string | undefined; structural: Partial<T> }> {
  const key = getProfileKey(profileId);
  const content = extractContent(data, contentFields);
  let content_enc: string | undefined;
  if (key && Object.keys(content).length > 0) {
    content_enc = await encryptProfileContent(
      content,
      key,
      makeAAD(profileId, entityName, rowId),
    );
  }
  const structural = stripContent(data, contentFields);
  return { content_enc, structural };
}
