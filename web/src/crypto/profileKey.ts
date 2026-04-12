/**
 * Profile key lifecycle — fetch-or-mint.
 *
 * Given a profile the caller has (or should have) access to, make sure the
 * AES-256 profile key is cached in memory:
 *
 *  1. If already cached → done.
 *  2. GET /profiles/{id}/my-grant → if 200, unwrap the encrypted_key via ECDH
 *     and cache.
 *  3. If 404 AND caller is the profile owner (legacy profiles created before
 *     Stage 1) → generate a new profile key, wrap a self-grant, POST it, and
 *     cache.
 *  4. Anything else → give up silently; absence of a key is not a fatal error
 *     because Stage 1 does not yet encrypt stored health data.
 */

import { api, ApiError } from '../api/client';
import {
  getProfileKey,
  setProfileKey,
  getIdentityPrivateKey,
  generateProfileKey,
} from './keys';
import { createKeyGrant, receiveKeyGrant } from './sharing';

interface MyGrantResp {
  profile_id: string;
  encrypted_key: string;
  granted_by_user_id: string;
  granter_identity_pubkey: string;
  via_family_id?: string;
}

interface MeResp {
  id: string;
  identity_pubkey: string;
}

/**
 * Compute the HKDF context string used when wrapping/unwrapping a grant.
 * Must be identical on create and consume sides.
 */
function grantContext(profileId: string, granterId: string, granteeId: string): string {
  if (granterId === granteeId) return `selfgrant:${granterId}`;
  return `${profileId}:${granterId}:${granteeId}`;
}

/**
 * Ensure the profile key for `profileId` is cached in memory. Best-effort —
 * failures are logged and swallowed so the UI keeps working while Stage 2
 * (data-at-rest encryption) lands.
 */
export async function ensureProfileKey(
  profileId: string,
  currentUserId: string,
  ownerUserId: string,
): Promise<CryptoKey | null> {
  if (getProfileKey(profileId)) return getProfileKey(profileId);

  const idPriv = getIdentityPrivateKey();
  if (!idPriv) {
    // Identity privkey not unwrapped (old session from before Stage 1).
    return null;
  }

  try {
    const grant = await api.get<MyGrantResp>(`/api/v1/profiles/${profileId}/my-grant`);
    const ctx = grantContext(profileId, grant.granted_by_user_id, currentUserId);
    try {
      const key = await receiveKeyGrant(
        grant.encrypted_key,
        idPriv,
        grant.granter_identity_pubkey,
        ctx,
      );
      setProfileKey(profileId, key);
      return key;
    } catch (unwrapErr) {
      // Unwrap failed — stale grant (encrypted with old identity keys).
      // If we're the owner, revoke it and re-mint with current keys.
      console.warn(`ensureProfileKey(${profileId}): unwrap failed, attempting repair`, unwrapErr);
      if (currentUserId !== ownerUserId) return null;
      return await _repairOrMintGrant(profileId, currentUserId, idPriv);
    }
  } catch (err) {
    if (!(err instanceof ApiError) || err.status !== 404) {
      console.warn(`ensureProfileKey(${profileId}): fetch grant failed`, err);
      return null;
    }
    // 404 — no active grant. If we're the owner, create a self-grant now.
    if (currentUserId !== ownerUserId) return null;
    return await _repairOrMintGrant(profileId, currentUserId, idPriv);
  }
}

/**
 * Revoke any existing stale grant, then mint a fresh self-grant.
 *
 * If a profile key is already cached (from a previous successful unwrap
 * or from sessionStorage), re-wrap THAT key so existing content_enc data
 * remains readable. Only generate a brand-new key as a last resort.
 */
async function _repairOrMintGrant(
  profileId: string,
  userId: string,
  idPriv: CryptoKey,
): Promise<CryptoKey | null> {
  try {
    // Best-effort revoke of the stale grant.
    try {
      await api.delete(`/api/v1/profiles/${profileId}/grants/${userId}`);
    } catch {
      // May 404 if already revoked — that's fine.
    }

    const me = await api.get<MeResp>('/api/v1/users/me');

    // Prefer the cached key so existing encrypted data stays readable.
    let profileKey = getProfileKey(profileId);
    if (!profileKey) {
      profileKey = await generateProfileKey();
    }

    const wrapped = await createKeyGrant(
      profileKey,
      idPriv,
      me.identity_pubkey,
      grantContext(profileId, userId, userId),
    );
    await api.post(`/api/v1/profiles/${profileId}/grants`, {
      grantee_user_id: userId,
      encrypted_key: wrapped,
      grant_signature: '',
    });
    setProfileKey(profileId, profileKey);
    return profileKey;
  } catch (mintErr) {
    console.warn(`_repairOrMintGrant(${profileId}): failed`, mintErr);
    return null;
  }
}
