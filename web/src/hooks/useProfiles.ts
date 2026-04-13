import { useQuery } from '@tanstack/react-query';
import { profilesApi } from '../api/profiles';
import { useAuthStore } from '../store/auth';

export function useProfiles() {
  const { userId } = useAuthStore();
  const result = useQuery({
    queryKey: ['profiles', userId],
    queryFn: async () => {
      const res = await profilesApi.list();
      return res.items ?? [];
    },
  });

  return result;
}
