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
    turbidity: 'normal',
    tds: 'normal',
  },
  latest_reading: {
    timestamp: new Date().toISOString(),
    temperature: 25.5,
    ph: 7.2,
    turbidity: 3.1,
    tds: 180,
  },
  fish_species: [
    {
      common_name: 'Neon Tetra',
      scientific_name: 'Paracheirodon innesi',
      category: 'Community',
      description: 'A peaceful schooling fish.',
      diet: 'Micro pellets and fine flakes.',
      care_tips: 'Keep in a planted group.',
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
    expect(screen.getByText('Water conditions healthy')).toBeInTheDocument();
    expect(screen.queryByText('Oxygen level')).not.toBeInTheDocument();
    expect(screen.queryByText('Ammonia')).not.toBeInTheDocument();
    expect(screen.queryByText(/94%/)).not.toBeInTheDocument();
    expect(screen.queryByText(/22–26°C/)).not.toBeInTheDocument();
    expect(mockedApi).toHaveBeenCalledWith('/public/tanks/display-one');
  });

  it('provides accessible page navigation and disclosure controls', async () => {
    renderPage();
    await screen.findByRole('heading', { name: 'Fish in this tank' });

    expect(screen.getByRole('navigation', { name: 'On this page' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Fish' })).toHaveAttribute('href', '#fish');
    expect(screen.getByText('Neon Tetra').closest('summary')).toBeInTheDocument();
    expect(screen.getByText('Community')).toBeInTheDocument();
    expect(screen.getByText('A peaceful schooling fish.')).toBeInTheDocument();
    expect(screen.queryByText('Compatibility')).not.toBeInTheDocument();
    expect(screen.getByText('Are the fish for sale?').closest('summary')).toBeInTheDocument();
    await waitFor(() =>
      expect(document.title).toBe('Display Tank A · JRed Aquatics'),
    );
  });
});
