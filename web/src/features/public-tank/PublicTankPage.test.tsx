import { api } from '@/shared/api/client';
import { ThemeProvider } from '@/shared/theme/ThemeProvider';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PublicTank } from './PublicTankPage';

vi.mock('@/shared/api/client', () => ({ api: vi.fn() }));

const mockedApi = vi.mocked(api);

const tank = {
  public_id: 'display-one',
  name: 'Display Tank A',
  location: 'Front display',
  description: 'A peaceful tropical community.',
  tank_code: 'TANK-01',
  habitat_label: 'Tropical community',
  water_type: 'freshwater',
  volume_liters: 180,
  established_on: '2026-03-01',
  hero_image_url: null,
  status: 'critical',
  parameter_statuses: {
    temperature: 'normal',
    ph: 'normal',
    dissolved_oxygen: 'normal',
    turbidity: 'normal',
    tds: 'normal',
    ammonia: 'critical',
  },
  latest_reading: {
    timestamp: new Date().toISOString(),
    temperature: 25.5,
    ph: 7.2,
    dissolved_oxygen: 6.2,
    turbidity: 3.1,
    tds: 180,
    ammonia: 0.7,
  },
  fish_species: [
    {
      id: 1,
      common_name: 'Neon Tetra',
      scientific_name: 'Paracheirodon innesi',
      ideal_temp_min: 22,
      ideal_temp_max: 26,
      ideal_ph_min: 6,
      ideal_ph_max: 7,
      diet: 'Micro pellets and fine flakes.',
    },
  ],
};

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <ThemeProvider>
        <MemoryRouter initialEntries={['/tank/display-one']}>
          <Routes>
            <Route path="/tank/:publicId" element={<PublicTank />} />
          </Routes>
        </MemoryRouter>
      </ThemeProvider>
    </QueryClientProvider>,
  );
}

describe('public tank experience', () => {
  beforeEach(() => mockedApi.mockResolvedValue(tank));

  it('renders qualitative and threshold-backed public status wording', async () => {
    renderPage();

    expect(await screen.findByRole('heading', { name: 'Display Tank A' })).toBeInTheDocument();
    expect(screen.getByText('Staff alerted')).toBeInTheDocument();
    expect(screen.getByText('Needs attention')).toBeInTheDocument();
    expect(screen.queryByText(/94%/)).not.toBeInTheDocument();
    expect(mockedApi).toHaveBeenCalledWith('/public/tanks/display-one');
  });

  it('provides accessible page navigation and disclosure controls', async () => {
    renderPage();
    await screen.findByRole('heading', { name: 'Fish in this tank' });

    expect(screen.getByRole('navigation', { name: 'On this page' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Fish' })).toHaveAttribute('href', '#fish');
    expect(screen.getByText('Neon Tetra').closest('summary')).toBeInTheDocument();
    expect(screen.getByText('Are the fish for sale?').closest('summary')).toBeInTheDocument();
    await waitFor(() =>
      expect(document.title).toBe('Display Tank A · JRed Aquatics'),
    );
  });
});
