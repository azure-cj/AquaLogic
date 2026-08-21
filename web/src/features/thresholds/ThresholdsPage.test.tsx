import { api } from '@/shared/api/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import Thresholds from './ThresholdsPage';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

function renderPage() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <Thresholds />
    </QueryClientProvider>,
  );
}

afterEach(() => vi.clearAllMocks());

describe('Thresholds', () => {
  it('shows only the currently supported operational parameters', async () => {
    vi.mocked(api).mockResolvedValue([
      { parameter: 'ammonia', unit: 'ppm', warning_min: null, warning_max: 0.25, critical_min: null, critical_max: 0.5, enabled: true },
      { parameter: 'dissolved_oxygen', unit: 'mg/L', warning_min: 5, warning_max: null, critical_min: 3, critical_max: null, enabled: true },
      { parameter: 'temperature', unit: '°C', warning_min: 20, warning_max: 28, critical_min: 18, critical_max: 30, enabled: true },
      { parameter: 'ph', unit: 'pH', warning_min: 6.5, warning_max: 7.8, critical_min: 6, critical_max: 8.5, enabled: true },
      { parameter: 'turbidity', unit: 'NTU', warning_min: null, warning_max: 8, critical_min: null, critical_max: 15, enabled: true },
      { parameter: 'tds', unit: 'ppm', warning_min: 50, warning_max: 400, critical_min: 20, critical_max: 550, enabled: true },
    ]);

    renderPage();

    expect(await screen.findByRole('heading', { name: 'temperature' })).toBeInTheDocument();
    expect(screen.getAllByRole('heading', { level: 2 })).toHaveLength(4);
    expect(screen.queryByRole('heading', { name: 'ammonia' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'dissolved oxygen' })).not.toBeInTheDocument();
  });
});
