import { api } from '@/shared/api/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { MonitoringIncidentHistory } from './MonitoringIncidentViews';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

const page = {
  items: [
    {
      id: 4,
      tank_id: 2,
      tank_name: 'Display tank',
      tank_lifecycle: 'active' as const,
      state: 'active' as const,
      started_at: '2026-08-22T10:00:00Z',
      detected_at: '2026-08-22T10:15:00Z',
      last_reading_received_at: '2026-08-22T09:59:00Z',
      last_report_age_seconds: 960,
      resolved_at: null,
      resolution_reason: null,
      recovery_reading_id: null,
      duration_seconds: 900,
    },
    {
      id: 3,
      tank_id: 2,
      tank_name: 'Display tank',
      tank_lifecycle: 'active' as const,
      state: 'resolved' as const,
      started_at: '2026-08-20T10:00:00Z',
      detected_at: '2026-08-20T10:15:00Z',
      last_reading_received_at: '2026-08-20T09:59:00Z',
      last_report_age_seconds: null,
      resolved_at: '2026-08-20T10:30:00Z',
      resolution_reason: 'reporting_recovered' as const,
      recovery_reading_id: 55,
      duration_seconds: 1800,
    },
  ],
  page: 1,
  page_size: 25,
  total: 2,
  total_pages: 1,
  has_previous: false,
  has_next: false,
};

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MemoryRouter>
      <QueryClientProvider client={client}>
        <MonitoringIncidentHistory />
      </QueryClientProvider>
    </MemoryRouter>,
  );
}

afterEach(() => vi.clearAllMocks());

describe('monitoring incident history', () => {
  it('distinguishes active and recovered reporting outages without manual resolution', async () => {
    vi.mocked(api).mockResolvedValue(page);
    renderPage();

    expect(await screen.findByText('Monitoring outage recorded')).toBeInTheDocument();
    expect(screen.getAllByText('Monitoring outage').length).toBeGreaterThan(0);
    expect(screen.getByText('Reporting recovered automatically')).toBeInTheDocument();
    expect(screen.getByText(/separate from water-quality alerts/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /resolve|handled/i })).not.toBeInTheDocument();
    expect(vi.mocked(api)).toHaveBeenCalledWith('/monitoring-incidents?state=all&page=1&page_size=25');
  });
});
