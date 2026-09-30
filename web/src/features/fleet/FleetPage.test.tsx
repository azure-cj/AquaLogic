import { api } from '@/shared/api/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';

import Fleet from './FleetPage';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

const fleet = [{
  id: 1,
  public_id: 'tank-one',
  name: 'Display tank',
  location: 'Front room',
  customer: null,
  status: 'offline' as const,
  latest_reading: {
    id: 8,
    tank_id: 1,
    timestamp: '2026-08-22T00:00:00Z',
    received_at: new Date(Date.now() - 13 * 60 * 60 * 1000).toISOString(),
    temperature: 25,
    ph: 7,
    turbidity: 2,
    dissolved_oxygen: null,
    tds: 100,
    ammonia: null,
  },
  last_reading_at: '2026-08-22T00:00:00Z',
  reporting_age_seconds: 13 * 60 * 60,
  active_warning_count: 0,
  active_critical_count: 0,
  active_monitoring_incident_count: 1,
  species_care_status: 'suitable' as const,
  assigned_species_count: 1,
}];

function renderPage() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <MemoryRouter>
      <QueryClientProvider client={client}>
        <Fleet />
      </QueryClientProvider>
    </MemoryRouter>,
  );
}

afterEach(() => vi.clearAllMocks());

describe('fleet reporting clarity', () => {
  it('labels offline values as last known and uses server reporting age', async () => {
    vi.mocked(api).mockImplementation(async (path) => {
      if (path === '/fleet') return fleet;
      if (path === '/alerts/history?resolved=false') return [];
      return { uptime: [], uptime_comparison: { current: 0, change: 0 }, fleet_series: [] };
    });

    renderPage();

    expect(await screen.findByLabelText(/Last known temperature/)).toHaveTextContent('25.0 °C');
    expect(screen.getByLabelText(/Last known pH/)).toHaveTextContent('7.0');
    expect(screen.getAllByText('Last known').length).toBeGreaterThanOrEqual(2);
    expect(screen.getAllByText('No report for approximately 13 hours').length).toBeGreaterThan(0);
    expect(screen.getByText('Water suitable')).toBeInTheDocument();
    expect(screen.getByText('Species Care (water)')).toBeInTheDocument();
    expect(screen.getAllByText('Monitoring outage recorded').length).toBeGreaterThan(0);
  });

  it('filters Needs action to include warnings, critical tanks, and offline tanks', async () => {
    const withStatuses = [
      fleet[0],
      { ...fleet[0], id: 2, public_id: 'tank-warning', name: 'Warning tank', status: 'warning' as const },
      { ...fleet[0], id: 3, public_id: 'tank-critical', name: 'Critical tank', status: 'critical' as const },
      { ...fleet[0], id: 4, public_id: 'tank-normal', name: 'Normal tank', status: 'normal' as const },
    ];
    vi.mocked(api).mockImplementation(async (path) => {
      if (path === '/fleet') return withStatuses;
      if (path === '/alerts/history?resolved=false') return [];
      return { uptime: [], uptime_comparison: { current: 0, change: 0 }, fleet_series: [] };
    });

    renderPage();
    const needsAction = await screen.findByRole('button', { name: /Needs action · 3/ });
    fireEvent.click(needsAction);

    expect(needsAction).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getAllByRole('link', { name: /Display tank/ }).length).toBeGreaterThan(0);
    expect(screen.getAllByRole('link', { name: /Warning tank/ }).length).toBeGreaterThan(0);
    expect(screen.getAllByRole('link', { name: /Critical tank/ }).length).toBeGreaterThan(0);
    expect(screen.queryByRole('link', { name: /Normal tank/ })).not.toBeInTheDocument();
  });

  it('keeps cached fleet data visible after a refresh failure', async () => {
    vi.mocked(api).mockImplementation(async (path) => {
      if (path === '/fleet') throw new TypeError('Failed to fetch');
      if (path === '/alerts/history?resolved=false') return [];
      return { uptime: [], uptime_comparison: { current: 0, change: 0 }, fleet_series: [] };
    });

    const client = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });
    client.setQueryData(['fleet'], fleet);
    render(
      <MemoryRouter>
        <QueryClientProvider client={client}>
          <Fleet />
        </QueryClientProvider>
      </MemoryRouter>,
    );

    expect(await screen.findByText(/Fleet refresh failed/)).toBeInTheDocument();
    expect(screen.getAllByRole('link', { name: /Display tank/ }).length).toBeGreaterThan(0);
  });

  it('does not show zero fleet counts before the first response', () => {
    vi.mocked(api).mockImplementation(() => new Promise(() => {}));
    renderPage();
    expect(screen.getByRole('button', { name: /Total tanks/ })).toHaveTextContent('—');
  });
});
