import { useQuery } from '@tanstack/react-query';
import { profilesApi } from '../api/profiles';

export function useProfiles() {
  return useQuery({
    queryKey: ['profiles'],
    queryFn: () => profilesApi.list(),
  });
}
