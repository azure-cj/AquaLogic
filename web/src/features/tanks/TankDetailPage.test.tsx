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
  latest_reading: null,
  parameter_statuses: {},
  active_alerts: [],
};

let suitabilityResult: unknown;
let suitabilityError: boolean;
let operationsError: boolean;
let customersRequest: Promise<unknown>;

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
    vi.mocked(api).mockReset();
    suitabilityResult = suitability;
    suitabilityError = false;
    operationsError = false;
    customersRequest = Promise.resolve([
      { id: 4, name: 'JRed Client', is_active: true },
    ]);
    vi.mocked(api).mockImplementation((path: string, init?: RequestInit) => {
      if (path === '/customers') return customersRequest;
      if (path === '/fish') return Promise.resolve([]);
      if (path === '/tanks/1' && !init) {
        return Promise.resolve(tank);
      }
      if (path === '/tanks/1' && init?.method === 'DELETE') {
        return Promise.resolve(undefined);
      }
      if (path === '/tanks/1/operations') {
        return operationsError
          ? Promise.reject(new Error('Operations request failed'))
          : Promise.resolve(operations);
      }
      if (path === '/tanks/1/species-suitability') {
        return suitabilityError
          ? Promise.reject(new Error('Species care request failed'))
          : Promise.resolve(suitabilityResult);
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
    expect(screen.getByText('Operational water status')).toBeInTheDocument();
  });

  it('keeps delete confirmation enabled and completes deletion', async () => {
    const user = userEvent.setup();
    renderPage();
    await screen.findByRole('heading', { name: 'Display tank' });

    await user.click(screen.getByRole('button', { name: 'Delete' }));
    const confirm = screen.getByRole('button', { name: 'Delete tank' });
    expect(confirm).toBeEnabled();
    await user.click(confirm);

    await waitFor(() =>
      expect(api).toHaveBeenCalledWith('/tanks/1', { method: 'DELETE' }),
    );
    expect(await screen.findByText('Tank directory')).toBeInTheDocument();
  });

  it('does not render the edit form until customer options are loaded', async () => {
    let resolveCustomers!: (value: unknown) => void;
    customersRequest = new Promise((resolve) => {
      resolveCustomers = resolve;
    });
    renderPage('/admin/tanks/1?edit=1');

    expect(
      await screen.findByText('Loading customer options…'),
    ).toBeInTheDocument();
    expect(screen.queryByRole('combobox', { name: 'Customer' })).not.toBeInTheDocument();

    resolveCustomers([{ id: 4, name: 'JRed Client', is_active: true }]);
    const customer = await screen.findByRole('combobox', { name: 'Customer' });
    expect(customer).toHaveValue('4');
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
      await screen.findByText('Suitable across 1 configured check.'),
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
      await screen.findByText('No current reading is available.'),
    ).toBeInTheDocument();

    unavailableView.unmount();
    suitabilityError = true;
    renderPage();
    expect(
      await screen.findByText('Species care could not be loaded.'),
    ).toBeInTheDocument();
  });
});
