import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ReactNode } from 'react';
import { BrowserRouter } from 'react-router-dom';

const queryClient = new QueryClient();

export function AppProviders({ children }: { children: ReactNode; }) {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter future={{ v7_startTransition: true }}>
        {children}
      </BrowserRouter>
    </QueryClientProvider>
  );
}
