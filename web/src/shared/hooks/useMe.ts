import { api, User } from '@/shared/api/client';
import { useQuery } from '@tanstack/react-query';

export function useMe() {
  return useQuery({
    queryKey: ['me'],
    queryFn: () => api<User>('/auth/me'),
    retry: false,
    staleTime: 20_000,
  });
}
