import { api } from '@/shared/api/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';

import Alerts, { resolutionLabel } from './AlertsPage';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

function renderPage() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <MemoryRouter>
      <QueryClientProvider client={client}>
        <Alerts />
      </QueryClientProvider>
    </MemoryRouter>,
  );
}

afterEach(() => vi.clearAllMocks());

describe('alert history', () => {
  it('labels automatic, operator, and legacy resolutions', () => {
    expect(resolutionLabel('system')).toBe('Automatically resolved');
    expect(resolutionLabel('operator')).toBe('Handled by operator');
    expect(resolutionLabel(null)).toBe('Resolved');
  });

  it('uses Mark handled wording and explains that it does not confirm recovery', async () => {
    vi.mocked(api).mockImplementation(async (path) => {
      if (path === '/fleet') return [];
      return [{
        id: 2,
        tank_id: 4,
        parameter: 'temperature',
        severity: 'warning',
        message: 'Temperature is outside its warning threshold',
        is_resolved: false,
        created_at: '2026-08-21T10:00:00Z',
        resolved_at: null,
        resolution_source: null,
      }];
    });

    renderPage();

    expect(await screen.findByRole('button', { name: /Mark temperature alert handled/i })).toBeInTheDocument();
    expect(screen.getByText(/does not confirm that water conditions have recovered/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Resolve$/ })).not.toBeInTheDocument();
  });

  it('renders an automatic resolution from the API', async () => {
    vi.mocked(api).mockImplementation(async (path) => {
      if (path === '/fleet') return [];
      return [{
        id: 1,
        tank_id: 4,
        parameter: 'temperature',
        severity: 'critical',
        message: 'Temperature is outside its critical threshold',
        is_resolved: true,
        created_at: '2026-08-21T10:00:00Z',
        resolved_at: '2026-08-21T10:05:00Z',
        resolution_source: 'system',
      }];
    });

    renderPage();

    expect(await screen.findByText('Automatically resolved')).toBeInTheDocument();
  });
});
