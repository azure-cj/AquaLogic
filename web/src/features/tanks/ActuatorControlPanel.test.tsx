import { api } from '@/shared/api/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { ActuatorControlPanel, StaffActuatorNotice } from './ActuatorControlPanel';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

const status = {
  tank_id: 1,
  device_id: 'esp32-control-01',
  device_online: true,
  device_freshness: 'online' as const,
  last_seen_at: '2026-08-15T10:00:00Z',
  checked_at: '2026-08-15T10:00:01Z',
  actuators: [
    {
      actuator: 'uv' as const,
      refreshed_at: '2026-08-15T10:00:00Z',
      state: {
        on: false,
        remaining_ms: 0,
        total_on_ms: 1000,
        schedule_enabled: true,
        on_time: '08:00',
        off_time: '18:00',
      },
    },
    {
      actuator: 'led' as const,
      refreshed_at: '2026-08-15T10:00:00Z',
      state: {
        on: true,
        remaining_ms: 5000,
        total_on_ms: 2000,
        schedule_enabled: false,
        on_time: '08:00',
        off_time: '18:00',
      },
    },
    {
      actuator: 'feeder' as const,
      refreshed_at: '2026-08-15T10:00:00Z',
      state: {
        feeding: false,
        feed_count: 3,
        last_fed: 'Never',
        open_angle: 125,
        duration_ms: 1000,
        schedule: [
          { enabled: true, time: '08:00' },
          { enabled: false, time: '12:00' },
          { enabled: false, time: '18:00' },
        ],
      },
    },
    {
      actuator: 'pump_a' as const,
      refreshed_at: '2026-08-15T10:00:00Z',
      state: { active: false, dose_count: 0, last_dispensed: 'Never', volume_ml: 1 },
    },
    {
      actuator: 'pump_b' as const,
      refreshed_at: '2026-08-15T10:00:00Z',
      state: { active: false, dose_count: 0, last_dispensed: 'Never', volume_ml: 1 },
    },
  ],
};

const emptySummary = {
  total: 0,
  queued: 0,
  executing: 0,
  succeeded: 0,
  failed: 0,
  expired: 0,
};

function renderPanel(variant: 'full' | 'summary' = 'full') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <ActuatorControlPanel tankId={1} variant={variant} />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('admin actuator controls', () => {
  beforeEach(() => {
    vi.mocked(api).mockReset();
    vi.mocked(api).mockImplementation((path: string, init?: RequestInit) => {
      if (path === '/tanks/1/actuators/status') return Promise.resolve(status);
      if (path === '/tanks/1/actuators/history?page=1&page_size=10') {
        return Promise.resolve({
          items: [],
          page: 1,
          page_size: 10,
          total: 0,
          total_pages: 0,
          has_previous: false,
          has_next: false,
          summary: emptySummary,
        });
      }
      if (path === '/tanks/1/actuators/commands' && init?.method === 'POST') return Promise.resolve({ command_id: 'new-command', status: 'queued' });
      return Promise.reject(new Error(`Unexpected path ${path}`));
    });
  });

  it('shows bridge freshness and the scoped UV, LED, and feeder controls', async () => {
    renderPanel();
    expect(await screen.findByText('Registered device')).toBeInTheDocument();
    expect(screen.getByText('esp32-control-01')).toBeInTheDocument();
    expect(screen.getByText('Online')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'UV light' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Normal LED light' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Fish feeder' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Syringe Pump A' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Syringe Pump B' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Feed now' })).toBeInTheDocument();
    expect(screen.getByText('Three firmware slots')).toBeInTheDocument();
  });

  it('keeps the tank-page snapshot compact and defers history to the full route', async () => {
    renderPanel('summary');

    expect(await screen.findByRole('heading', { name: 'Actuator snapshot' })).toBeInTheDocument();
    expect(await screen.findByRole('heading', { name: 'Syringe pumps' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /^Full controls$/ })).toHaveAttribute('href', '/admin/tanks/1/actuators');
    expect(screen.queryByRole('heading', { name: 'Command history' })).not.toBeInTheDocument();
    expect(vi.mocked(api).mock.calls.some(([path]) => path.includes('/actuators/history'))).toBe(false);
  });

  it('requires confirmation and queues a feed-now command for the registered device', async () => {
    const user = userEvent.setup();
    renderPanel();
    await user.click(await screen.findByRole('button', { name: 'Feed now' }));
    const dialog = screen.getByRole('alertdialog');
    expect(dialog).toHaveTextContent('This sends one manual feed command');
    await user.click(within(dialog).getByRole('button', { name: 'Feed now' }));
    await screen.findByText('Manual feed command queued. The bridge will report the result.');
    const call = vi.mocked(api).mock.calls.find(([path, init]) => path === '/tanks/1/actuators/commands' && init?.method === 'POST');
    expect(call?.[1]?.body).toContain('"device_id":"esp32-control-01"');
    expect(call?.[1]?.body).toContain('"action":"feed_now"');
    expect(document.querySelector('.admin-toast')).toBeInTheDocument();
  });

  it('requires confirmation for pump dispense and retract, and queues the configured-volume test command', async () => {
    const user = userEvent.setup();
    renderPanel();
    expect((await screen.findAllByText('Volume-controlled dispense')).length).toBe(2);
    expect(screen.getAllByText('1.00 mL')).toHaveLength(4);
    await user.click(screen.getByRole('button', { name: 'Syringe Pump A dispense/test' }));
    let dialog = screen.getByRole('alertdialog');
    expect(dialog).toHaveTextContent('Manual test only');
    expect(dialog).toHaveTextContent('configured 1.00 mL dose');
    await user.click(within(dialog).getByRole('button', { name: 'Dispense / test' }));
    await screen.findByText('Syringe Pump A dispense/test command queued. The bridge will report the result.');

    await user.click(screen.getByRole('button', { name: 'Syringe Pump A retract' }));
    dialog = screen.getByRole('alertdialog');
    expect(dialog).toHaveTextContent('firmware retract route');
    await user.click(within(dialog).getByRole('button', { name: 'Retract' }));
    await screen.findByText('Syringe Pump A retract command queued. The bridge will report the result.');

    const calls = vi.mocked(api).mock.calls.filter(([path, init]) => path === '/tanks/1/actuators/commands' && init?.method === 'POST');
    expect(calls.some(([, init]) => init?.body?.toString().includes('"actuator":"pump_a"') && init.body.toString().includes('"action":"dispense"') && init.body.toString().includes('"payload":{}') && init.body.toString().includes('"expires_in_seconds":20'))).toBe(true);
    expect(calls.some(([, init]) => init?.body?.toString().includes('"action":"retract"'))).toBe(true);
  });

  it('paginates command history without losing the page context', async () => {
    const user = userEvent.setup();
    const command = {
      command_id: 'history-command-1',
      tank_id: 1,
      device_id: 'esp32-control-01',
      actor_user_id: 1,
      actor_name: 'Test Admin',
      actuator: 'uv',
      action: 'on',
      payload: {},
      status: 'succeeded',
      requested_at: '2026-08-15T10:00:00Z',
      expires_at: '2026-08-15T10:02:00Z',
      executing_at: '2026-08-15T10:00:01Z',
      execution_at: '2026-08-15T10:00:02Z',
      result: {},
      error: null,
    };
    vi.mocked(api).mockImplementation((path: string) => {
      if (path === '/tanks/1/actuators/status') return Promise.resolve(status);
      if (path === '/tanks/1/actuators/history?page=1&page_size=10') {
        return Promise.resolve({ items: [command], page: 1, page_size: 10, total: 11, total_pages: 2, has_previous: false, has_next: true, summary: { total: 11, queued: 10, executing: 0, succeeded: 1, failed: 0, expired: 0 } });
      }
      if (path === '/tanks/1/actuators/history?page=2&page_size=10') {
        return Promise.resolve({ items: [{ ...command, command_id: 'history-command-11', status: 'expired', executing_at: null, execution_at: null }], page: 2, page_size: 10, total: 11, total_pages: 2, has_previous: true, has_next: false, summary: { total: 11, queued: 10, executing: 0, succeeded: 1, failed: 0, expired: 1 } });
      }
      return Promise.reject(new Error(`Unexpected path ${path}`));
    });

    renderPanel();
    expect(await screen.findByText('Showing 1–10 of 11')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /Next/ }));
    expect(await screen.findByText('Showing 11–11 of 11')).toBeInTheDocument();
    expect(vi.mocked(api).mock.calls.some(([path]) => path === '/tanks/1/actuators/history?page=2&page_size=10')).toBe(true);
  });

  it('filters history and explains the physical execution boundary', async () => {
    const user = userEvent.setup();
    const command = {
      command_id: 'filtered-history-command',
      tank_id: 1,
      device_id: 'esp32-control-01',
      actor_user_id: 1,
      actor_name: 'Test Admin',
      actuator: 'uv',
      action: 'on',
      payload: {},
      status: 'succeeded',
      requested_at: '2026-08-15T10:00:00Z',
      expires_at: '2026-08-15T10:02:00Z',
      executing_at: '2026-08-15T10:00:01Z',
      execution_at: '2026-08-15T10:00:02Z',
      result: {},
      error: null,
    };
    vi.mocked(api).mockImplementation((path: string) => {
      if (path === '/tanks/1/actuators/status') return Promise.resolve(status);
      if (path.startsWith('/tanks/1/actuators/history')) {
        return Promise.resolve({ items: [command], page: 1, page_size: 10, total: 1, total_pages: 1, has_previous: false, has_next: false, summary: { total: 1, queued: 0, executing: 0, succeeded: 1, failed: 0, expired: 0 } });
      }
      return Promise.reject(new Error(`Unexpected path ${path}`));
    });

    renderPanel();
    expect(await screen.findByText('UV light - Turn on')).toBeInTheDocument();
    expect(await screen.findByText('Physical endpoint reported success')).toBeInTheDocument();
    expect(screen.getByText('Total')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'About command history' }));
    expect(screen.getByRole('tooltip')).toHaveTextContent('administrator commands');
    expect(screen.getByRole('tooltip').parentElement).toBe(document.body);
    await user.click(screen.getByRole('button', { name: 'View details' }));
    expect(screen.getByText('Command ID')).toBeInTheDocument();
    expect(screen.getByText('Physical result')).toBeInTheDocument();
    await user.selectOptions(screen.getByRole('combobox', { name: 'Filter history by actuator' }), 'uv');
    await user.selectOptions(screen.getByRole('combobox', { name: 'Filter history by status' }), 'succeeded');
    await waitFor(() => expect(vi.mocked(api).mock.calls.some(([path]) => path === '/tanks/1/actuators/history?page=1&page_size=10&actuator=uv&status=succeeded')).toBe(true));
  });

  it('warns when commands may expire while the bridge is offline', async () => {
    const offlineStatus = { ...status, device_online: false, device_freshness: 'offline' as const };
    vi.mocked(api).mockImplementation((path: string) => {
      if (path === '/tanks/1/actuators/status') return Promise.resolve(offlineStatus);
      if (path === '/tanks/1/actuators/history?page=1&page_size=10') {
        return Promise.resolve({ items: [], page: 1, page_size: 10, total: 0, total_pages: 0, has_previous: false, has_next: false, summary: emptySummary });
      }
      return Promise.reject(new Error(`Unexpected path ${path}`));
    });

    renderPanel();
    expect(await screen.findByText('Bridge is offline or stale')).toBeInTheDocument();
    expect(screen.getByText('Light and feeder commands may expire while waiting. Pump manual tests are not queued until the bridge is online.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Syringe Pump A dispense/test' })).toBeDisabled();
  });

  it('renders a non-usable staff notice without fetching actuator APIs', () => {
    render(<StaffActuatorNotice />);
    expect(screen.getByText('Administrator access required')).toBeInTheDocument();
    expect(api).not.toHaveBeenCalled();
  });
});
