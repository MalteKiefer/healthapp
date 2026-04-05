import { useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { profilesApi } from '../api/profiles';
import { ensureProfileKey } from '../crypto';
import { useAuthStore } from '../store/auth';

export function useProfiles() {
  const { userId } = useAuthStore();
  const result = useQuery({
    queryKey: ['profiles'],
    queryFn: () => profilesApi.list(),
  });

  // Best-effort: ensure a profile key is cached for every profile in the list.
  // For profiles we own without a grant yet (legacy), this lazily mints a
  // self-grant so owners can later share the profile with family members.
  useEffect(() => {
    if (!userId || !result.data) return;
    let cancelled = false;
    (async () => {
      for (const p of result.data) {
        if (cancelled) return;
        await ensureProfileKey(p.id, userId, p.owner_user_id);
      }
    })();
    return () => { cancelled = true; };
  }, [result.data, userId]);

  return result;
}
