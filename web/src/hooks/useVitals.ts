import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { vitalsApi, type Vital } from '../api/vitals';

export function useVitals(profileId: string | undefined, params?: { limit?: number }) {
  return useQuery({
    queryKey: ['vitals', profileId, params],
    queryFn: () => vitalsApi.list(profileId!, params),
    enabled: !!profileId,
  });
}

export function useVitalChart(profileId: string | undefined, metric: string) {
  return useQuery({
    queryKey: ['vitals-chart', profileId, metric],
    queryFn: () => vitalsApi.chart(profileId!, metric),
    enabled: !!profileId && !!metric,
  });
}

export function useCreateVital(profileId: string) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: Partial<Vital>) => vitalsApi.create(profileId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vitals', profileId] });
      queryClient.invalidateQueries({ queryKey: ['vitals-chart', profileId] });
    },
  });
}

export function useDeleteVital(profileId: string) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (vitalId: string) => vitalsApi.delete(profileId, vitalId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vitals', profileId] });
      queryClient.invalidateQueries({ queryKey: ['vitals-chart', profileId] });
    },
  });
}
