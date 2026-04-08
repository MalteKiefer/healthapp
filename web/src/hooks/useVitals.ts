import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { vitalsApi, type Vital } from '../api/vitals';
import { ensureProfileKey } from '../crypto';
import { useAuthStore } from '../store/auth';
import { useProfiles } from './useProfiles';

/**
 * Wait until the profile key is unwrapped in memory. Idempotent — if the
 * key is already cached the promise resolves immediately. Used on write
 * paths so clients can't accidentally post plaintext during the brief
 * window between profile selection and the background key fetch.
 */
async function ensureKey(profileId: string, userId: string, ownerUserId: string) {
  return ensureProfileKey(profileId, userId, ownerUserId);
}

export function useVitals(profileId: string | undefined, params?: { limit?: number; from?: string; to?: string }) {
  const { userId } = useAuthStore();
  const { data: profiles } = useProfiles();
  return useQuery({
    queryKey: ['vitals', profileId, params],
    queryFn: async () => {
      if (profileId && userId) {
        const p = profiles?.find((x) => x.id === profileId);
        if (p) await ensureKey(profileId, userId, p.owner_user_id);
      }
      return vitalsApi.list(profileId!, params);
    },
    enabled: !!profileId,
  });
}

export function useCreateVital(profileId: string) {
  const queryClient = useQueryClient();
  const { userId } = useAuthStore();
  const { data: profiles } = useProfiles();

  return useMutation({
    mutationFn: async (data: Partial<Vital>) => {
      const p = profiles?.find((x) => x.id === profileId);
      if (userId && p) await ensureKey(profileId, userId, p.owner_user_id);
      return vitalsApi.create(profileId, data);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vitals', profileId] });
    },
  });
}

export function useDeleteVital(profileId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (vitalId: string) => vitalsApi.delete(profileId, vitalId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vitals', profileId] });
    },
  });
}

export function useUpdateVital(profileId: string) {
  const queryClient = useQueryClient();
  const { userId } = useAuthStore();
  const { data: profiles } = useProfiles();
  return useMutation({
    mutationFn: async (data: Partial<Vital> & { id: string }) => {
      const p = profiles?.find((x) => x.id === profileId);
      if (userId && p) await ensureKey(profileId, userId, p.owner_user_id);
      return vitalsApi.update(profileId, data.id, data);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vitals', profileId] });
    },
  });
}
