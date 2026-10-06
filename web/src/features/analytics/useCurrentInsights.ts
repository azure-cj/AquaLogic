import { useQuery } from '@tanstack/react-query';
import { api } from '@/shared/api/client';
import type { CurrentInsightsResponse } from './types';

// Undefined selects all active tanks; null waits for the section's selection.
export function useCurrentInsights(tankId?: number | null) {
  return useQuery({
    queryKey: ['current-insights', tankId ?? 'all'],
    queryFn: () => api<CurrentInsightsResponse>(`/analytics/current-insights${tankId == null ? '' : `?tank_id=${tankId}`}`),
    enabled: tankId !== null,
    refetchOnWindowFocus: true,
    refetchInterval: false,
    refetchOnReconnect: false,
  });
}
