import { api } from '@/shared/api/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';

import AnalyticsPage from './AnalyticsPage';
import type { AnalyticsResponse, MetricKey } from './types';
import { analyticsCsv, thresholdZones } from './utils';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

const values = (overrides: Partial<Record<MetricKey, number | null>> = {}) => ({
  temperature: 25,
  ph: 7.1,
  turbidity: 2,
  dissolved_oxygen: 6,
  tds: 180,
  ammonia: .1,
  ...overrides,
});

const response = (): AnalyticsResponse => ({
  window: {
    range: '24h',
    start: '2026-07-26T00:00:00Z',
    end: '2026-07-27T00:00:00Z',
    bucket_seconds: 900,
    timezone: 'Asia/Manila',
  },
  tanks: [{ id: 1, name: 'Tank A' }],
  fleet_series: [
    {
      timestamp: '2026-07-26T00:00:00Z',
      values: values(),
      sample_count: 30,
      contributor_count: 1,
    },
  ],
  previous_fleet_series: [
    {
      timestamp: '2026-07-25T00:00:00Z',
      values: values({ temperature: 24 }),
      sample_count: 30,
      contributor_count: 1,
    },
  ],
  tank_series: [],
  stats: Object.fromEntries(
    (['temperature', 'ph', 'turbidity', 'dissolved_oxygen', 'tds', 'ammonia'] as MetricKey[])
      .map((metric) => [
        metric,
        {
          average: values()[metric],
          minimum: values()[metric],
          maximum: values()[metric],
          previous_average: values()[metric],
          absolute_change: 0,
          percent_change: 0,
        },
      ]),
  ) as AnalyticsResponse['stats'],
  alert_counts: { warning: 0, critical: 0 },
  alert_series: [
    { timestamp: '2026-07-26T00:00:00Z', warning: 0, critical: 0 },
  ],
  alert_events: [],
  threshold_segments: [
    {
      parameter: 'temperature',
      unit: '°C',
      start: '2026-07-26T00:00:00Z',
      end: '2026-07-27T00:00:00Z',
      warning_min: 20,
      warning_max: 28,
      critical_min: 18,
      critical_max: 30,
      enabled: true,
    },
  ],
  uptime: [
    {
      tank_id: 1,
      tank_name: 'Tank A',
      uptime: 42.5,
      previous_uptime: 40,
      reported_intervals: 1224,
      previous_reported_intervals: 1152,
      expected_intervals: 2880,
      status: 'critical',
    },
  ],
  uptime_comparison: { current: 42.5, previous: 40, change: 2.5 },
  uptime_thresholds: { healthy: 99, degraded: 95 },
  insights: {
    alert_count: 0,
    reporting_gap_count: 1,
    lowest_uptime_tank_id: 1,
    primary_driver_by_metric: {
      temperature: 1,
      ph: 1,
      turbidity: 1,
      dissolved_oxygen: 1,
      tds: 1,
      ammonia: 1,
    },
  },
});

function renderPage(path = '/admin/analytics') {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <QueryClientProvider
        client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}
      >
        <AnalyticsPage />
      </QueryClientProvider>
    </MemoryRouter>,
  );
}

describe('fleet analytics', () => {
  it('uses URL state and renders diagnostic uptime rows', async () => {
    vi.mocked(api).mockImplementation(async (path) => {
      if (path === '/tanks') return [{ id: 1, name: 'Tank A' }];
      const result = response();
      if (path.includes('tank_id=1')) {
        result.tank_series = [{
          tank_id: 1,
          tank_name: 'Tank A',
          series: result.fleet_series,
        }];
      }
      return result;
    });

    renderPage('/admin/analytics?metric=ph&previous=1&tanks=1');

    expect(await screen.findByRole('tab', { name: 'pH' })).toHaveAttribute(
      'aria-selected',
      'true',
    );
    const progress = await screen.findByRole('progressbar', {
      name: 'Tank A reporting uptime',
    });
    expect(progress).toHaveAttribute('aria-valuenow', '42.5');
    expect(progress.closest('a')).toHaveAttribute('href', '/admin/tanks?tank_id=1');
    expect(screen.getByLabelText('Alert severity legend')).toHaveTextContent('Warning');
    expect(screen.getByRole('button', { name: /Export CSV/i })).toBeEnabled();
    await waitFor(() =>
      expect(api).toHaveBeenCalledWith(
        expect.stringContaining('tank_id=1'),
      ),
    );
  });

  it('limits tank comparison selection to three', async () => {
    vi.mocked(api).mockImplementation(async (path) => {
      if (path === '/tanks') {
        return [1, 2, 3, 4].map((id) => ({ id, name: `Tank ${id}` }));
      }
      return response();
    });
    const user = userEvent.setup();
    renderPage('/admin/analytics?tanks=1,2,3');
    await user.click(await screen.findByText('3 tanks selected'));
    expect(screen.getByRole('checkbox', { name: 'Tank 4' })).toBeDisabled();
  });

  it('exports escaped long-form CSV with thresholds', () => {
    const data = response();
    data.tanks[0].name = 'Tank "A", display';
    data.tank_series = [{
      tank_id: 1,
      tank_name: data.tanks[0].name,
      series: data.fleet_series,
    }];
    const csv = analyticsCsv(data, ['temperature']);
    expect(csv).toContain('warning_min');
    expect(csv).toContain('"Tank ""A"", display"');
    expect(csv).toContain('Asia/Manila');
  });

  it('maps configured threshold values to visible warning and critical bands', () => {
    const segment = response().threshold_segments[0];
    expect(thresholdZones(segment, [16, 32])).toEqual([
      { tone: 'critical', y1: 16, y2: 18 },
      { tone: 'warning', y1: 18, y2: 20 },
      { tone: 'warning', y1: 28, y2: 30 },
      { tone: 'critical', y1: 30, y2: 32 },
    ]);
  });
});
