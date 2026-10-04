import { api } from '@/shared/api/client';
import type { AlertContext } from '@/shared/api/models';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { afterEach, expect, it, vi } from 'vitest';
import { AlertDetailDrawer } from './AlertDetailDrawer';
import Alerts from './AlertsPage';

vi.mock('@/shared/api/client', async (original) => ({ ...await original<typeof import('@/shared/api/client')>(), api: vi.fn() }));
afterEach(() => vi.resetAllMocks());

const fixture: AlertContext = {
  alert: { id: 123, tank_id: 2, reading_id: 10, parameter: 'temperature', severity: 'warning', message: 'Temperature alert', is_resolved: false, created_at: '2026-10-02T00:00:00Z' },
  tank: { id: 2, display_name: 'Tank Two', lifecycle: 'active' }, evaluated_at: '2026-10-02T00:01:00Z',
  linked_reading: { reading_id: 10, value: 29, unit: '°C', observed_at: '2026-10-01T00:00:00Z', received_at: '2026-10-02T00:00:00Z', reporting_freshness: 'fresh' },
  latest_reading: { reading_id: 11, value: 25, unit: '°C', observed_at: '2026-10-01T01:00:00Z', received_at: '2026-10-02T00:01:00Z', reporting_freshness: 'fresh' },
  linked_threshold: { parameter: 'temperature', unit: '°C', warning_min: 20, warning_max: 28, critical_min: 18, critical_max: 30, source: 'global', enabled: true, updated_at: null },
  current_threshold: { parameter: 'temperature', unit: '°C', warning_min: 20, warning_max: 28, critical_min: 18, critical_max: 30, source: 'tank', enabled: false, updated_at: null },
  guidance: { code: 'temperature.above.v1', direction: 'above', explanation: 'Review the linked measurement.', checks: ['Confirm the measurement.', 'Inspect heater if installed.', 'Verify circulation.'], advisory: 'Handling does not confirm water recovery.' },
};

function Location() { const location = useLocation(); return <output data-testid="location">{location.search}</output>; }
function setup(children: React.ReactNode, url = '/admin/alerts') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const invalidate = vi.spyOn(client, 'invalidateQueries');
  render(<MemoryRouter initialEntries={[url]}><QueryClientProvider client={client}>{children}<Location /></QueryClientProvider></MemoryRouter>);
  return invalidate;
}
function mockContext(data = fixture) {
  vi.mocked(api).mockImplementation(async (path) => {
    if (path === '/auth/me') return { role: 'staff' };
    if (path.includes('/context')) return data;
    return [];
  });
}

it('loads only opened context and separates readings, times, disabled bounds and navigation', async () => {
  mockContext();
  const close = vi.fn();
  setup(<AlertDetailDrawer alertId={123} onClose={close} />);
  expect(await screen.findByText('Reading linked to this alert')).toBeInTheDocument();
  expect(screen.getByText('Latest received reading')).toBeInTheDocument();
  expect(screen.getByText(/Currently disabled/)).toBeInTheDocument();
  expect(screen.getByText(/does not prove the observation is current/)).toBeInTheDocument();
  expect(screen.getByRole('link', { name: 'View equipment' })).toHaveAttribute('href', '/admin/tanks/2?tab=control');
  expect(screen.getByRole('link', { name: 'View tank' })).toHaveAttribute('href', '/admin/tanks/2');
  expect(screen.getByRole('link', { name: 'View Analytics' })).toHaveAttribute('href', '/admin/analytics?tanks=2&metric=temperature');
  fireEvent.click(screen.getByRole('button', { name: 'Close' }));
  expect(close).toHaveBeenCalledOnce();
});

it('preserves URL filters and alert_id while opening and closing a direct detail link', async () => {
  mockContext();
  setup(<Alerts />, '/admin/alerts?severity=warning&tank_id=2&alert_id=123');
  expect(await screen.findByText('Reading linked to this alert')).toBeInTheDocument();
  expect(screen.getByTestId('location').textContent).toContain('alert_id=123');
  fireEvent.click(screen.getByRole('button', { name: 'Close' }));
  await waitFor(() => expect(screen.getByTestId('location').textContent).not.toContain('alert_id'));
  expect(screen.getByTestId('location').textContent).toContain('severity=warning');
  expect(screen.getByTestId('location').textContent).toContain('tank_id=2');
});

it('shows loading and retries a failed context request', async () => {
  let fail = true;
  vi.mocked(api).mockImplementation(async (path) => {
    if (path === '/auth/me') return { role: 'admin' };
    if (fail) throw new Error('Unavailable');
    return fixture;
  });
  setup(<AlertDetailDrawer alertId={123} onClose={() => {}} />);
  expect(await screen.findByText('Alert context could not be loaded.')).toBeInTheDocument();
  fail = false;
  fireEvent.click(screen.getByRole('button', { name: /try again/i }));
  expect(await screen.findByText('Suggested checks')).toBeInTheDocument();
  expect(screen.getByRole('link', { name: 'View equipment' })).toHaveAttribute('href', '/admin/tanks/2/actuators');
});

it('refreshes authoritative context and relevant caches after handling, without optimistic success', async () => {
  let handled = false;
  let fail = true;
  vi.mocked(api).mockImplementation(async (path) => {
    if (path === '/auth/me') return { role: 'admin' };
    if (path.endsWith('/resolve')) { if (fail) throw new Error('Failure'); handled = true; return {}; }
    return { ...fixture, alert: { ...fixture.alert, is_resolved: handled, resolution_source: handled ? 'operator' : null } };
  });
  const invalidate = setup(<AlertDetailDrawer alertId={123} onClose={() => {}} />);
  fireEvent.click(await screen.findByRole('button', { name: 'Mark handled' }));
  await waitFor(() => expect(screen.getByRole('button', { name: 'Mark handled' })).toBeEnabled());
  expect(await screen.findByText('Active')).toBeInTheDocument();
  expect(invalidate).not.toHaveBeenCalled();
  fail = false;
  fireEvent.click(screen.getByRole('button', { name: 'Mark handled' }));
  expect(await screen.findByText('Handled by operator')).toBeInTheDocument();
  for (const key of ['alert-context', 'alerts', 'fleet', 'tank-operations', 'tank-alert-history']) expect(invalidate).toHaveBeenCalledWith({ queryKey: [key] });
});

it('keeps retired and resolved history readable with no handling action', async () => {
  mockContext({ ...fixture, tank: { ...fixture.tank, lifecycle: 'retired' }, linked_reading: null, latest_reading: null, alert: { ...fixture.alert, is_resolved: true, resolution_source: 'system' } });
  setup(<AlertDetailDrawer alertId={123} onClose={() => {}} />);
  expect(await screen.findByText('Automatically resolved')).toBeInTheDocument();
  expect(screen.getAllByText('Reading unavailable.')).toHaveLength(2);
  expect(screen.queryByRole('button', { name: 'Mark handled' })).not.toBeInTheDocument();
});


it('renders current species counts, stored bounds and unavailable comparisons without merged ranges', async () => {
  mockContext({ ...fixture, species_context: { parameter: 'temperature', basis: 'current_assignments_latest_reading', status: 'unavailable', reason: 'stale_observation', unit: '°C', reading: { reading_id: 11, observed_at: '2026-10-01T01:00:00Z', received_at: '2026-10-02T00:01:00Z' }, counts: { assigned: 2, evaluable: 0, within: 0, outside: 0, unavailable: 2 }, species: [{ species_id: 1, name: 'Fictional preference A', stored_min: 20, stored_max: 28, result: 'unavailable', reason: 'stale_observation' }, { species_id: 2, name: 'Fictional preference B', stored_min: null, stored_max: 25, result: 'unavailable', reason: 'stale_observation' }], advisory: "Stored species preferences provide additional context. AquaLogic alerts continue to use the tank's configured thresholds." } });
  setup(<AlertDetailDrawer alertId={123} onClose={() => {}} />);
  expect(await screen.findByText('Stored species preferences')).toBeInTheDocument();
  expect(screen.getByText(/2 distinct species assigned/)).toBeInTheDocument();
  expect(screen.getByText(/including for historical alerts/)).toBeInTheDocument();
  expect(screen.getByText('Fictional preference A')).toBeInTheDocument();
  expect(screen.getByText(/Comparison unavailable: stale observation/)).toBeInTheDocument();
  expect(screen.getByText(/alerts continue to use/)).toBeInTheDocument();
});

it('keeps handling in the fixed footer and simplifies unsupported species context', async () => {
  mockContext({ ...fixture, species_context: { parameter: 'turbidity', basis: 'current_assignments_latest_reading', status: 'unsupported', reason: 'unsupported_parameter', unit: 'NTU', reading: null, counts: { assigned: 1, evaluable: 0, within: 0, outside: 0, unavailable: 1 }, species: [], advisory: 'Additional context.' } });
  setup(<AlertDetailDrawer alertId={123} onClose={() => {}} />);
  const action = await screen.findByRole('button', { name: 'Mark handled' });
  expect(action.closest('.drawer-footer')).not.toBeNull();
  expect(await screen.findByText(/Stored species preferences do not support turbidity comparisons/)).toBeInTheDocument();
  expect(screen.queryByText(/0 evaluable/)).not.toBeInTheDocument();
  expect(screen.queryByText('View individual stored preferences')).not.toBeInTheDocument();
});
