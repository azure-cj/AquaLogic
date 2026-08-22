import { api } from '@/shared/api/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import TankDetail from './TankDetailPage';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

const tank = {
  id: 1,
  public_id: 'tank-one',
  name: 'Display tank',
  location: 'Front room',
  description: 'A planted display tank.',
  is_public: true,
  customer_id: 4,
  customer: { id: 4, name: 'JRed Client' },
  fish_species: [],
  tank_code: 'DISPLAY-01',
  habitat_label: 'Community habitat',
  water_type: 'freshwater' as const,
  volume_liters: 180,
  public_care_notes: 'Keep the viewing area calm.',
  lifecycle: 'active' as 'active' | 'retired',
  retired_at: null as string | null,
};

const suitability = {
  tank_id: 1,
  status: 'attention' as const,
  summary_reason: null,
  evaluated_at: '2026-07-28T10:15:30Z',
  reading: {
    id: 8,
    timestamp: '2026-07-28T10:15:12Z',
    freshness: 'current' as const,
  },
  species_counts: { suitable: 0, attention: 1, unavailable: 0 },
  species: [
    {
      fish_species_id: 7,
      common_name: 'Discus',
      scientific_name: 'Symphysodon aequifasciatus',
      status: 'attention' as const,
      checks: [
        {
          parameter: 'temperature' as const,
          status: 'attention' as const,
          configured: true,
          reason: 'below_preferred_minimum' as const,
          current_value: 25,
          preferred_min: 28,
          preferred_max: 31,
          unit: '°C',
          message:
            'Discus prefers 28–31 °C, but the tank is currently 25 °C.',
        },
      ],
    },
  ],
};

const operations = {
  tank_id: 1,
  evaluated_at: '2026-07-28T10:15:30Z',
  status: 'normal' as const,
  latest_reading: {
    id: 8,
    device_id: 'display-device',
    tank_id: 1,
    timestamp: '2026-07-28T10:15:12Z',
    received_at: '2026-07-28T10:15:20Z',
    temperature: 25,
    ph: 7,
    turbidity: 2,
    dissolved_oxygen: null,
    tds: 100,
    ammonia: null,
  },
  parameter_statuses: { temperature: 'normal', ph: 'normal', turbidity: 'normal', tds: 'normal' },
  active_alerts: [],
};

let suitabilityResult: unknown;
let suitabilityError: boolean;
let operationsError: boolean;
let operationsResult: unknown;

function renderPage(path = '/admin/tanks/1') {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route path="/admin/tanks/:tankId" element={<TankDetail />} />
          <Route path="/admin/tanks" element={<div>Tank directory</div>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('dedicated tank workspace', () => {
  beforeEach(() => {
    tank.lifecycle = 'active';
    tank.is_public = true;
    tank.retired_at = null;
    vi.mocked(api).mockReset();
    suitabilityResult = suitability;
    suitabilityError = false;
    operationsError = false;
    operationsResult = operations;
    vi.mocked(api).mockImplementation((path: string, init?: RequestInit) => {
      if (path === '/fish') return Promise.resolve([]);
      if (path === '/tanks/1' && !init) {
        return Promise.resolve(tank);
      }
      if (path === '/tanks/1' && init?.method === 'DELETE') {
        return Promise.resolve(undefined);
      }
      if (path === '/tanks/1/retire' && init?.method === 'POST') {
        return Promise.resolve({ ...tank, lifecycle: 'retired', is_public: false, retired_at: '2026-08-22T08:00:00Z' });
      }
      if (path === '/tanks/1/operations') {
        return operationsError
          ? Promise.reject(new Error('Operations request failed'))
          : Promise.resolve(operationsResult);
      }
      if (path === '/tanks/1/species-suitability') {
        return suitabilityError
          ? Promise.reject(new Error('Species care request failed'))
          : Promise.resolve(suitabilityResult);
      }
      if (path === '/tanks/1/alerts?include_resolved=true') return Promise.resolve([]);
      if (path === '/tanks/1/monitoring-incidents?state=all&page=1&page_size=10') {
        return Promise.resolve({ items: [], page: 1, page_size: 10, total: 0, total_pages: 0, has_previous: false, has_next: false });
      }
      return Promise.reject(new Error(`Unexpected path ${path}`));
    });
  });

  it('shows operational and Species Care status as separate concepts', async () => {
    renderPage();

    expect(
      await screen.findByRole('heading', { name: 'Species Care' }),
    ).toBeInTheDocument();
    expect(await screen.findByText('Discus')).toBeInTheDocument();
    expect(
      screen.getByText(
        /Below preferred minimum.*Discus prefers 28–31 °C/,
      ),
    ).toBeInTheDocument();
    expect(screen.getByText('Current 25.0 °C')).toBeInTheDocument();
    expect(screen.queryByText('Dissolved oxygen')).not.toBeInTheDocument();
    expect(screen.getByText('Operational water status')).toBeInTheDocument();
    expect(screen.getByText('Operational status')).toBeInTheDocument();
    expect(screen.getByText(/global monitoring thresholds/)).toBeInTheDocument();
    expect(screen.getByText(/does not assess fish-to-fish compatibility/)).toBeInTheDocument();
    expect(screen.getByText('Current readings')).toBeInTheDocument();
  });

  it('labels stale operational values as last known and uses receipt age', async () => {
    operationsResult = {
      ...operations,
      status: 'offline',
      latest_reading: {
        ...operations.latest_reading,
        received_at: new Date(Date.now() - 13 * 60 * 60 * 1000).toISOString(),
      },
    };

    renderPage();

    expect(await screen.findByText('Last known readings')).toBeInTheDocument();
    expect(screen.getAllByText(/No report for approximately 13 hours/).length).toBeGreaterThan(0);
    expect(screen.getByText('Last known temperature')).toBeInTheDocument();
    expect(screen.getByText('Last known pH')).toBeInTheDocument();
    expect(screen.queryByText('Current readings')).not.toBeInTheDocument();
  });

  it('opens retirement confirmation and completes retirement', async () => {
    const user = userEvent.setup();
    renderPage();
    await screen.findByRole('heading', { name: 'Display tank' });

    await user.click(screen.getByRole('button', { name: 'Retire' }));
    expect(
      screen.getByText(
        /registered devices will be disabled, while readings, alerts, assignments, equipment history, configuration, and media remain available/i,
      ),
    ).toBeInTheDocument();
    expect(screen.getByText(/Follow the hardware decommissioning checklist first/i)).toBeInTheDocument();
    const confirm = screen.getByRole('button', { name: 'Retire tank' });
    expect(confirm).toBeEnabled();
    await user.click(confirm);

    await waitFor(() =>
      expect(api).toHaveBeenCalledWith('/tanks/1/retire', {
        method: 'POST',
        body: JSON.stringify({ note: null }),
      }),
    );
    expect(await screen.findByText(/Tank retired. History is retained and live controls are disabled/i)).toBeInTheDocument();
  });

  it('opens a focused tank editor without exposing customer management', async () => {
    renderPage('/admin/tanks/1?edit=1');

    expect(await screen.findByRole('heading', { name: 'Edit Display tank' })).toBeInTheDocument();
    expect(screen.queryByRole('combobox', { name: 'Customer' })).not.toBeInTheDocument();
    expect(await screen.findByText('Public profile')).toBeInTheDocument();
    expect(screen.getByText('Hero image')).toBeInTheDocument();
    expect(screen.getByText('Show public tank page')).toBeInTheDocument();
  });

  it('renders retired detail as historical read-only workspace', async () => {
    tank.lifecycle = 'retired';
    tank.is_public = false;
    tank.retired_at = '2026-08-22T08:00:00Z';
    renderPage();

    expect((await screen.findAllByText('Retired')).length).toBeGreaterThan(0);
    expect((await screen.findAllByText('Species Care history')).length).toBeGreaterThan(0);
    expect(screen.getByText(/Retired tanks do not participate in live Species Care evaluation/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Edit' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Retire' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Add species' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Permanently delete/i })).toBeInTheDocument();
  });

  it('does not report all-clear alerts when operations fail', async () => {
    operationsError = true;
    renderPage();

    expect(
      await screen.findByText('Operational alerts could not be loaded.'),
    ).toBeInTheDocument();
    expect(screen.queryByText('No active alerts')).not.toBeInTheDocument();
    expect(screen.getAllByText('Unavailable').length).toBeGreaterThan(0);
  });

  it('renders suitable, unavailable, no-reading, and request-error care states', async () => {
    suitabilityResult = {
      ...suitability,
      status: 'suitable',
      species_counts: { suitable: 1, attention: 0, unavailable: 0 },
      species: [
        {
          ...suitability.species[0],
          status: 'suitable',
          checks: [
            {
              ...suitability.species[0].checks[0],
              status: 'suitable',
              reason: 'within_preferred_range',
            },
          ],
        },
      ],
    };
    const suitableView = renderPage();
    expect(
      await screen.findByText('Within preferred water ranges across 1 configured check.'),
    ).toBeInTheDocument();

    suitableView.unmount();
    suitabilityResult = {
      ...suitability,
      status: 'unavailable',
      reading: null,
      species_counts: { suitable: 0, attention: 0, unavailable: 1 },
      species: [
        {
          ...suitability.species[0],
          status: 'unavailable',
          checks: [
            {
              ...suitability.species[0].checks[0],
              status: 'unavailable',
              reason: 'no_current_reading',
              message:
                'No current tank reading is available for temperature.',
            },
          ],
        },
      ],
    };
    const unavailableView = renderPage();
    expect(
      await screen.findByText('No current water reading is available.'),
    ).toBeInTheDocument();

    unavailableView.unmount();
    suitabilityError = true;
    renderPage();
    expect(
      await screen.findByText('Species care could not be loaded.'),
    ).toBeInTheDocument();
  });
});
