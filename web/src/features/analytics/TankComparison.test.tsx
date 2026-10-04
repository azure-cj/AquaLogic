import { fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { expect, it, vi } from 'vitest';
import { AnalyticsResultsNotes, TankComparison } from './TankComparison';
import type { AnalyticsResponse, DecisionSupportCard } from './types';

const card: DecisionSupportCard = {
  id: '4.temperature.within_range.v1', tank_id: 4, tank_name: 'Tank Four', scope: 'tank', parameter: 'temperature', rule: 'within_range',
  title: '51.2% of temperature observations within range', explanation: 'Observation proportion, not time or health.',
  window_start: '2026-10-02T00:00:00Z', window_end: '2026-10-02T05:00:00Z', observation_start: '2026-10-02T00:00:00Z', observation_end: '2026-10-02T04:45:00Z',
  samples: 41, unit: '°C', evidence: { percent: 51.22, within: 21, outside: 20, evaluable: 41, excluded: 0 },
  qualifications: ['Operating bounds changed during this period. Expanded bounds do not establish improvement.'], checks: [], related_alert_ids: [],
};
function fixture(): AnalyticsResponse {
  return {
    window: { range: 'custom', start: card.window_start, end: card.window_end, bucket_seconds: 1800, water_quality_bucket_seconds: 1800, timezone: 'Asia/Manila' },
    decision_support_insights: { cards: [card, { ...card, id: '4.temperature.little_change.v1', rule: 'little_change', title: 'Little sustained change in temperature' }], limitations: [{ tank_id: 7, tank_name: 'Sparse tank', parameter: 'temperature', rule: 'within_range', reason: 'Insufficient evaluable observations.', samples: 12 }], advisory: 'Historical observations, not a forecast.' },
    tanks: [], fleet_series: [], previous_fleet_series: [], tank_series: [], stats: {} as AnalyticsResponse['stats'], threshold_segments: [],
    alert_counts: { warning: 1, critical: 0 }, alert_series: [], alert_events: [{ id: 123, tank_id: 4, tank_name: 'Tank Four', parameter: 'temperature', severity: 'warning', reading_id: null, message: 'Temperature alert', timestamp: card.window_start, value: 29 }],
    uptime: [{ tank_id: 4, tank_name: 'Tank Four', uptime: 1.4, previous_uptime: 0.7, reported_intervals: 41, previous_reported_intervals: 20, expected_intervals: 2880, status: 'critical' }],
    uptime_comparison: { current: 1.4, previous: 0.7, change: 0.7 }, uptime_thresholds: { healthy: 90, degraded: 50 }, insights: { alert_count: 1, reporting_gap_count: 2, lowest_uptime_tank_id: 4, primary_driver_by_metric: {} as AnalyticsResponse['insights']['primary_driver_by_metric'] },
  };
}
function setup(data = fixture(), selectedFinding: DecisionSupportCard | null = null) {
  const graph = vi.fn();
  render(<MemoryRouter><TankComparison data={data} metric="temperature" selectedFinding={selectedFinding} onGraph={graph} /></MemoryRouter>);
  return graph;
}

it('joins findings by tank and parameter without substituting reporting coverage for observation evidence', () => {
  setup();
  const row = screen.getByRole('rowheader', { name: /Tank Four/ }).closest('tr')!;
  expect(within(row).getByText('51.2%')).toBeInTheDocument();
  expect(within(row).queryByText('Very limited data')).not.toBeInTheDocument();
  expect(within(row).getByText('41')).toBeInTheDocument();
  expect(within(row).getByText('Temperature showed little sustained change')).toBeInTheDocument();
  expect(within(row).getByText('Range changed')).toBeInTheDocument();
  const sparse = screen.getByRole('rowheader', { name: /Sparse tank/ }).closest('tr')!;
  expect(within(sparse).getAllByText('Unavailable')).toHaveLength(1);
  expect(within(sparse).queryByText('0%')).not.toBeInTheDocument();
});

it('opens the precise highlighted tank evidence and preserves graph navigation', () => {
  const graph = setup(fixture(), card);
  expect(screen.getByRole('button', { name: 'Hide details for Tank Four' })).toHaveAttribute('aria-expanded', 'true');
  expect(screen.getAllByRole('article')).toHaveLength(1);
  expect(screen.queryByText('How this is calculated')).not.toBeInTheDocument();
  const buttons = screen.getAllByRole('button', { name: 'View temperature graph for Tank Four' });
  fireEvent.click(buttons[0]);
  expect(graph).toHaveBeenCalledWith(4, 'temperature');
  expect(screen.getByText(/A wider range does not establish improvement/)).toBeInTheDocument();
});

it('shows fleet reporting and navigable real alert records when additive findings are absent', () => {
  const data = fixture(); data.decision_support_insights = undefined;
  setup(data);
  expect(screen.getByText(/Water-quality findings are unavailable/)).toBeInTheDocument();
  fireEvent.click(screen.getByRole('tab', { name: /Data availability/ }));
  expect(screen.getByRole('table', { name: 'Fleet data availability' })).toHaveTextContent('41 / 2,880');
  expect(screen.getByText(/Previous period: 0.7%/)).not.toBeVisible();
  fireEvent.click(screen.getByRole('tab', { name: /Alerts/ }));
  const params = new URL(screen.getByRole('link', { name: 'Alert #123' }).getAttribute('href')!, 'http://localhost').searchParams;
  expect(params.get('alert_id')).toBe('123');
  expect(params.get('created_after')).toBe(card.window_start);
  expect(params.get('created_before')).toBe(card.window_end);
});

it('bounds large tables, exposes remaining rows and supports keyboard tabs', () => {
  const data = fixture(); data.decision_support_insights!.cards = Array.from({ length: 12 }, (_, index) => ({ ...card, id: String(index), tank_id: index + 20, tank_name: `Tank ${index + 20}` }));
  data.decision_support_insights!.limitations = [];
  setup(data);
  expect(screen.getAllByRole('rowheader')).toHaveLength(8);
  fireEvent.click(screen.getByRole('button', { name: 'Show 4 more rows' }));
  expect(screen.getAllByRole('rowheader')).toHaveLength(12);
  fireEvent.keyDown(screen.getByRole('tab', { name: /Water quality/ }), { key: 'ArrowRight' });
  expect(screen.getByRole('tab', { name: /Data availability/ })).toHaveAttribute('aria-selected', 'true');
});

it('keeps receipt counts inside reporting details and exposes selected-metric limitations in page notes', () => {
  const data = fixture();
  setup(data);
  fireEvent.click(screen.getByRole('tab', { name: /Data availability/ }));
  const detail = screen.getByText('View reporting details').closest('details')!;
  expect(detail).not.toHaveAttribute('open');
  expect(screen.getByText(/41 \/ 2,880 expected receipt intervals/)).not.toBeVisible();
  fireEvent.click(screen.getByText('View reporting details'));
  expect(screen.getByText(/41 \/ 2,880 expected receipt intervals/)).toBeVisible();
  render(<AnalyticsResultsNotes data={data} metric="temperature" />);
  const about = screen.getByText('About these results').closest('details')!;
  expect(about).not.toHaveAttribute('open');
  fireEvent.click(screen.getByText('About these results'));
  expect(screen.getByText(/Insufficient evaluable observations/)).not.toBeVisible();
  fireEvent.click(screen.getByText('View technical details'));
  fireEvent.click(screen.getByText('Temperature technical evidence'));
  expect(screen.getByText(/Insufficient evaluable observations/)).toBeVisible();
  expect(screen.getByText(/fixed 30-minute buckets aligned to :00 and :30/)).toBeVisible();
  expect(screen.getByText(/Contiguous receipt gaps: 2/)).toBeVisible();
});
