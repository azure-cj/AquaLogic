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

  it('shows equipment freshness and the scoped UV, LED, and feeder controls', async () => {
    renderPanel();
    expect(await screen.findByText('Equipment status')).toBeInTheDocument();
    expect(screen.getByText('Up to date')).toBeInTheDocument();
    expect(screen.queryByText('esp32-control-01')).not.toBeInTheDocument();
    expect(screen.getByText('Online')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'UV light' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Normal LED light' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Fish feeder' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Syringe Pump A' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Syringe Pump B' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Feed now' })).toBeInTheDocument();
    expect(screen.getByText('Up to 3 daily times')).toBeInTheDocument();
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
    expect(dialog).toHaveTextContent('This sends one manual feed request');
    await user.click(within(dialog).getByRole('button', { name: 'Feed now' }));
    await screen.findByText('Manual feed request queued. The system will update its status after processing.');
    const call = vi.mocked(api).mock.calls.find(([path, init]) => path === '/tanks/1/actuators/commands' && init?.method === 'POST');
    expect(call?.[1]?.body).toContain('"device_id":"esp32-control-01"');
    expect(call?.[1]?.body).toContain('"action":"feed_now"');
    expect(document.querySelector('.admin-toast')).toBeInTheDocument();
  });

  it('requires confirmation for pump dispense and retract, and queues the configured-volume test command', async () => {
    const user = userEvent.setup();
    renderPanel();
    expect((await screen.findAllByText('Configured-volume dispense')).length).toBe(2);
    expect(screen.getAllByText('1.00 mL')).toHaveLength(4);
    await user.click(screen.getByRole('button', { name: 'Syringe Pump A dispense/test' }));
    let dialog = screen.getByRole('alertdialog');
    expect(dialog).toHaveTextContent('Manual check only');
    expect(dialog).toHaveTextContent('configured 1.00 mL dose');
    await user.click(within(dialog).getByRole('button', { name: 'Dispense / test' }));
    await screen.findByText('Syringe Pump A dispense/test request queued. The system will update its status after processing.');

    await user.click(screen.getByRole('button', { name: 'Syringe Pump A retract' }));
    dialog = screen.getByRole('alertdialog');
    expect(dialog).toHaveTextContent('retract action');
    await user.click(within(dialog).getByRole('button', { name: 'Retract' }));
    await screen.findByText('Syringe Pump A retract request queued. The system will update its status after processing.');

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
    expect(await screen.findByText('Completed — the equipment confirmed the action')).toBeInTheDocument();
    expect(screen.getByText('Total')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'About command history' }));
    expect(screen.getByRole('tooltip')).toHaveTextContent('administrator actions');
    expect(screen.getByRole('tooltip').parentElement).toBe(document.body);
    await user.click(screen.getByRole('button', { name: 'View details' }));
    expect(screen.getByText('Command ID')).toBeInTheDocument();
    expect(screen.getByText('Equipment result')).toBeInTheDocument();
    await user.selectOptions(screen.getByRole('combobox', { name: 'Filter history by actuator' }), 'uv');
    await user.selectOptions(screen.getByRole('combobox', { name: 'Filter history by status' }), 'succeeded');
    await waitFor(() => expect(vi.mocked(api).mock.calls.some(([path]) => path === '/tanks/1/actuators/history?page=1&page_size=10&actuator=uv&status=succeeded')).toBe(true));
  });

  it('explains failed, executing, and expired command states without overstating hardware results', async () => {
    const commands = [
      {
        command_id: 'executing-command',
        tank_id: 1,
        device_id: 'esp32-control-01',
        actor_user_id: 1,
        actor_name: 'Test Admin',
        actuator: 'uv',
        action: 'on',
        payload: {},
        status: 'executing',
        requested_at: '2026-08-15T10:00:00Z',
        expires_at: '2026-08-15T10:02:00Z',
        executing_at: '2026-08-15T10:00:01Z',
        execution_at: null,
        result: null,
        error: null,
      },
      {
        command_id: 'failed-command',
        tank_id: 1,
        device_id: 'esp32-control-01',
        actor_user_id: 1,
        actor_name: 'Test Admin',
        actuator: 'feeder',
        action: 'feed_now',
        payload: {},
        status: 'failed',
        requested_at: '2026-08-15T10:01:00Z',
        expires_at: '2026-08-15T10:03:00Z',
        executing_at: '2026-08-15T10:01:01Z',
        execution_at: '2026-08-15T10:01:02Z',
        result: null,
        error: 'The equipment did not confirm the action',
      },
      {
        command_id: 'expired-command',
        tank_id: 1,
        device_id: 'esp32-control-01',
        actor_user_id: 1,
        actor_name: 'Test Admin',
        actuator: 'led',
        action: 'on',
        payload: {},
        status: 'expired',
        requested_at: '2026-08-15T10:02:00Z',
        expires_at: '2026-08-15T10:02:01Z',
        executing_at: null,
        execution_at: null,
        result: null,
        error: 'Command expired before execution',
      },
    ];
    vi.mocked(api).mockImplementation((path: string) => {
      if (path === '/tanks/1/actuators/status') return Promise.resolve(status);
      if (path === '/tanks/1/actuators/history?page=1&page_size=10') {
        return Promise.resolve({ items: commands, page: 1, page_size: 10, total: 3, total_pages: 1, has_previous: false, has_next: false, summary: { total: 3, queued: 0, executing: 1, succeeded: 0, failed: 1, expired: 1 } });
      }
      return Promise.reject(new Error(`Unexpected path ${path}`));
    });

    renderPanel();
    expect(await screen.findByText('In progress — the equipment action may be underway')).toBeInTheDocument();
    expect(screen.getByText('Not completed — the equipment did not confirm the action')).toBeInTheDocument();
    expect(screen.getByText('Not sent — the request expired while waiting')).toBeInTheDocument();
    expect(screen.getByText('Never sent')).toBeInTheDocument();
    expect(screen.getByLabelText('executing')).toBeInTheDocument();
    expect(screen.getByLabelText('failed')).toBeInTheDocument();
    expect(screen.getByLabelText('expired')).toBeInTheDocument();
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
    expect(await screen.findByText('Equipment connection is offline or stale')).toBeInTheDocument();
    expect(screen.getByText('Light and feeder requests may expire while waiting. Pump maintenance checks are available only when the connection is online.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Syringe Pump A dispense/test' })).toBeDisabled();
  });

  it('renders a non-usable staff notice without fetching actuator APIs', () => {
    render(<StaffActuatorNotice />);
    expect(screen.getByText('Administrator access required')).toBeInTheDocument();
    expect(api).not.toHaveBeenCalled();
  });
});
