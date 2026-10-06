import type { ReactNode } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider, focusManager } from '@tanstack/react-query';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { api } from '@/shared/api/client';
import { TankInsightsSection } from './TankInsightsSection';
import { insightsFixture, parameterFixture } from './currentInsights.fixture';
import { RecentTrendChart, RecentTrendTooltip, recentTrendRows } from './RecentTrendChart';

vi.mock('@/shared/api/client', () => ({ api: vi.fn() }));
// Give the actual chart dimensions in jsdom; chart layers below remain real SVG.
vi.mock('recharts', async (importOriginal) => {
  const original = await importOriginal<typeof import('recharts')>();
  return { ...original, ResponsiveContainer: ({ children }: { children: ReactNode }) =>
    <original.ResponsiveContainer width={800} height={300}>{children as never}</original.ResponsiveContainer> };
});
function Location() { return <output aria-label="Current URL">{useLocation().search}</output>; }
function section(data = insightsFixture(), url = '/admin/analytics') {
  vi.mocked(api).mockImplementation(async (path) => {
    const id = new URL(path, 'http://localhost').searchParams.get('tank_id');
    return id ? { ...data, tanks: data.tanks.filter((tank) => tank.tank_id === Number(id)) } : data;
  });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<MemoryRouter initialEntries={[url]}><QueryClientProvider client={client}><TankInsightsSection /><Location /></QueryClientProvider></MemoryRouter>);
  return client;
}
afterEach(() => { vi.clearAllMocks(); focusManager.setFocused(undefined); });

describe('tank insights structure', () => {
  it('defaults to the first attention tank, renders four cards and category badges, and selects chart by keyboard-capable buttons', async () => {
    section();
    expect(await screen.findByRole('button', { name: 'Temperature' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByLabelText('Insights tank')).toHaveValue('2');
    expect(screen.getAllByRole('article')).toHaveLength(4);
    for (const card of screen.getAllByRole('article')) {
      expect(within(card).getByText('Observed')).toBeInTheDocument();
      expect(within(card).getByText('Derived')).toBeInTheDocument();
      expect(within(card).getByText('Projected')).toBeInTheDocument();
    }
    expect(within(screen.getAllByRole('article')[0]).getByText(/^If the current trend continues/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Turbidity' }));
    expect(screen.getByRole('figure')).toHaveAccessibleName(/Turbidity: Rising/);
    expect(screen.getByRole('figure')).toHaveTextContent('Turbidity is not projected because it changes in sudden events');
    expect(within(screen.getByRole('figure')).queryByText('Projection if trend continues')).not.toBeInTheDocument();
    expect(screen.getByText('How is this calculated?').parentElement).toHaveProperty('tagName', 'DETAILS');
  });
  it('uses first active tank when attention is empty, switches tank by scoped API call and preserves history controls', async () => {
    const data = insightsFixture(); data.attention = [];
    section(data, '/admin/analytics?range=7d&tanks=1&metric=ph');
    await screen.findByRole('button', { name: 'Temperature' });
    expect(screen.getByLabelText('Insights tank')).toHaveValue('1');
    fireEvent.change(screen.getByLabelText('Insights tank'), { target: { value: '2' } });
    await waitFor(() => expect(api).toHaveBeenCalledWith('/analytics/current-insights?tank_id=2'));
    expect(screen.getByLabelText('Current URL')).toHaveTextContent('range=7d&tanks=1&metric=ph&insights_tank=2');
  });
  it.each(['1', '999', 'garbage'])('honors valid deep links and falls back from invalid IDs (%s)', async (id) => {
    section(insightsFixture(), `/admin/analytics?insights_tank=${id}`);
    await screen.findByRole('button', { name: 'Temperature' });
    expect(screen.getByLabelText('Insights tank')).toHaveValue(id === '1' ? '1' : '2');
  });
  it('keeps all cards when observations and inference are unavailable and labels last-known context', async () => {
    const data = insightsFixture(); data.tanks[1].latest.is_current = false;
    const p = data.tanks[1].parameters[0]; p.observed = null; p.trend.status = 'insufficient_data'; p.projection.status = 'stale'; p.projection.band = [];
    p.stability.status = 'insufficient_baseline'; p.stability.baseline_days_covered = 2;
    p.species_range.status = 'conflict'; p.species_range.conflict = { min_species: 'Discus', min: 28, max_species: 'Corydoras', max: 27 };
    section(data);
    await screen.findByRole('button', { name: 'Temperature' });
    expect(screen.getAllByRole('article')).toHaveLength(4);
    expect(screen.getByText('No readings available')).toBeInTheDocument();
    expect(screen.getAllByText('not current')).toHaveLength(3);
    expect(screen.getAllByText('No projection: the latest reading is not current').length).toBeGreaterThan(0);
    expect(screen.getByText('Baseline needs 5 days of readings (2 available)')).toBeInTheDocument();
    expect(screen.getByText(/Assigned species' ranges do not overlap/)).toBeInTheDocument();
  });
  it('handles no active tanks and API errors', async () => {
    section({ ...insightsFixture(), tanks: [], attention: [] });
    expect(await screen.findByText('Add an active tank to see current insights.')).toBeInTheDocument();
  });
  it('shows an error without affecting other sections', async () => {
    section(); vi.mocked(api).mockRejectedValue(new Error('unavailable'));
    // Initial overview is in flight; a new error on scoped selection remains local.
    expect(await screen.findByText('Tank insights could not be loaded.')).toBeInTheDocument();
  });
  it('refetches on focus without a polling interval', async () => {
    const client = section();
    await screen.findByRole('button', { name: 'Temperature' });
    const calls = vi.mocked(api).mock.calls.length;
    const query = client.getQueryCache().find({ queryKey: ['current-insights', 2] })!;
    expect(query.observers[0].options.refetchInterval).toBe(false);
    expect(query.observers[0].options.refetchOnReconnect).toBe(false);
    await act(async () => { focusManager.setFocused(false); focusManager.setFocused(true); });
    await waitFor(() => expect(vi.mocked(api).mock.calls.length).toBeGreaterThan(calls));
  });
});
describe('recent trend chart categories', () => {
  it('renders observed, trend, band and dotted mid layers on one time axis with bounds and Now', () => {
    const { container } = render(<RecentTrendChart parameter={parameterFixture()} evaluatedAt="2026-10-13T12:05:00Z" />);
    expect(screen.getByRole('figure')).toHaveAccessibleName(/Temperature: Rising 0.18/);
    expect(container.querySelector('.recharts-area')).toBeInTheDocument();
    expect(container.querySelectorAll('.recharts-line')).toHaveLength(3);
    expect(container.querySelectorAll('.recharts-reference-line')).toHaveLength(3);
    expect(container.querySelector('.recharts-reference-area')).toBeInTheDocument();
    expect(screen.getByText('Now')).toBeInTheDocument();
    const rows = recentTrendRows(parameterFixture());
    expect(rows[0].timestamp).toBe(new Date('2026-10-13T06:00:00Z').getTime());
    expect(rows[rows.length - 1]?.projectionRange).toEqual([27.5, 28.5]);
    expect(rows.filter((row) => row.observed != null)).toHaveLength(2);
  });
  it('does not render projection when band is empty', () => {
    const p = parameterFixture(); p.projection.band = []; p.projection.status = 'too_uncertain';
    const { container } = render(<RecentTrendChart parameter={p} evaluatedAt="2026-10-13T12:05:00Z" />);
    expect(container.querySelector('.recharts-area')).not.toBeInTheDocument();
    expect(container.querySelectorAll('.recharts-line')).toHaveLength(2);
    expect(screen.getByText('Trend too uncertain to project')).toBeInTheDocument();
  });
  it('labels every tooltip value and never presents projected values as observed', () => {
    render(<RecentTrendTooltip active label={1} unit="°C" payload={[{ payload: {
      timestamp: 1, observed: 25, trend: 26, projectedLow: 27, projectedMid: 28, projectedHigh: 29,
    } }]} />);
    for (const copy of ['Observed: 25 °C', 'Trend: 26 °C', 'Projected low: 27 °C', 'Projected mid: 28 °C', 'Projected high: 29 °C']) expect(screen.getByText(copy)).toBeInTheDocument();
  });
});
