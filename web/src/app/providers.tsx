import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ReactNode, useEffect } from 'react';
import { BrowserRouter } from 'react-router-dom';

const queryClient = new QueryClient();

export function AppProviders({ children }: { children: ReactNode; }) {
  useEffect(() => {
    const clearCache = () => queryClient.clear();
    window.addEventListener('aqualogic:session-cleared', clearCache);
    return () => window.removeEventListener('aqualogic:session-cleared', clearCache);
  }, []);
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        {children}
      </BrowserRouter>
    </QueryClientProvider>
  );
}
