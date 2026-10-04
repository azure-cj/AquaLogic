import { api } from '@/shared/api/client';
import { Toaster } from '@/shared/components/ui/sonner';
import { ThemeProvider } from '@/shared/theme/ThemeProvider';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  ActuatorControlPanel,
  StaffActuatorNotice,
  formatCooldownClearsAt,
  formatLastDispensed,
  formatNextScheduledDose,
  formatPumpScheduleEvent,
  formatPumpTimestamp,
} from './ActuatorControlPanel';

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
      state: {
        active: false,
        dose_count: 0,
        last_dispensed: 'Never',
        volume_ml: 1,
        remaining_ml: 5,
        capacity_ml: 5,
        volume_known: true,
        refill_required: false,
        clock_synced: true,
        schedule: [
          { enabled: false, time: '08:00' },
          { enabled: false, time: '12:00' },
          { enabled: false, time: '18:00' },
        ],
        next_eligible_at: 'Available now',
        next_dose_at: '2026-08-15T12:00:00+08:00',
      },
    },
    {
      actuator: 'pump_b' as const,
      refreshed_at: '2026-08-15T10:00:00Z',
      state: {
        active: false,
        dose_count: 0,
        last_dispensed: 'Never',
        volume_ml: 1,
        remaining_ml: 5,
        capacity_ml: 5,
        volume_known: true,
        refill_required: false,
        clock_synced: true,
        schedule: [
          { enabled: false, time: '08:00' },
          { enabled: false, time: '12:00' },
          { enabled: false, time: '18:00' },
        ],
        next_eligible_at: 'Available now',
        next_dose_at: '2026-08-15T12:00:00+08:00',
      },
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
  outcome_unknown: 0,
};

function renderPanel(variant: 'full' | 'summary' = 'full') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <ThemeProvider>
        <Toaster />
        <MemoryRouter>
          <ActuatorControlPanel tankId={1} variant={variant} />
        </MemoryRouter>
      </ThemeProvider>
    </QueryClientProvider>,
  );
}

describe('admin actuator controls', () => {
  afterEach(() => vi.useRealTimers());

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

  it('formats pump timestamps in Manila time and handles missing or sentinel values', () => {
    vi.setSystemTime(new Date('2026-09-30T10:00:00Z'));
    expect(formatPumpTimestamp('2026-09-30T21:27:05+08:00')).toBe('Today, 9:27 PM');
    expect(formatPumpTimestamp('2026-10-01T08:00:00+08:00')).toBe('Oct 1, 2026, 8:00 AM');
    vi.setSystemTime(new Date('2026-09-30T18:00:00Z'));
    expect(formatPumpTimestamp('2026-10-01T02:27:05+08:00')).toBe('Today, 2:27 AM');
    expect(formatPumpTimestamp('Never')).toBe('Time unavailable');
    expect(formatPumpTimestamp('2026-02-30T08:00:00+08:00')).toBe('Time unavailable');
    expect(formatLastDispensed('Never')).toBe('No dispense yet');
    expect(formatLastDispensed('Time not synchronized')).toBe('Device time not synced');
    expect(formatLastDispensed('12:34:56')).toBe('12:34 PM (date unavailable)');
    expect(formatLastDispensed(null)).toBe('No dispense yet');
    expect(formatLastDispensed('')).toBe('No dispense yet');
    expect(formatLastDispensed('not a timestamp')).toBe('Time unavailable');
  });

  it('distinguishes cooldown availability from schedule and device-time availability', () => {
    vi.setSystemTime(new Date('2026-09-30T10:00:00Z'));
    expect(formatCooldownClearsAt('2026-09-30T17:00:00+08:00', true)).toBe('Available now');
    expect(formatCooldownClearsAt('2026-10-01T08:00:00+08:00', true)).toBe('Oct 1, 2026, 8:00 AM');
    expect(formatCooldownClearsAt('Never', true)).toBe('Unavailable');
    expect(formatCooldownClearsAt(null, false)).toBe('Unavailable until device time syncs');
    const enabledSchedule = [{ enabled: true, time: '08:00' }];
    const disabledSchedule = [{ enabled: false, time: '08:00' }];
    expect(formatNextScheduledDose('2026-09-30T21:27:05+08:00', true, enabledSchedule)).toBe('Today, 9:27 PM');
    expect(formatNextScheduledDose('2026-09-30T21:27:05+08:00', false, enabledSchedule)).toBe('Unavailable until device time syncs');
    expect(formatNextScheduledDose('2026-09-30T21:27:05+08:00', false, disabledSchedule)).toBe('No enabled dose time');
    expect(formatNextScheduledDose('2026-09-30T21:27:05+08:00', true, disabledSchedule)).toBe('No enabled dose time');
  });

  it('translates known schedule events and preserves unknown device details', () => {
    expect(formatPumpScheduleEvent('Pump A scheduled dose skipped: Two-hour chemical-dose cooldown until 2026-09-30T21:00:00+08:00').message)
      .toBe('Scheduled dose skipped because the two-hour minimum interval has not passed.');
    expect(formatPumpScheduleEvent('Pump A scheduled dose skipped: could not persist occurrence').message)
      .toBe('Scheduled dose skipped because the equipment status could not be verified.');
    const unknown = 'Unexpected pump event detail';
    expect(formatPumpScheduleEvent(unknown)).toEqual({
      message: 'A pump schedule update needs attention. Review the pump status before continuing.',
      detail: unknown,
    });
  });

  it('shows equipment freshness and the scoped UV, LED, and feeder controls', async () => {
    renderPanel();
    expect(await screen.findByText('Equipment status')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Refresh equipment status' })).toBeInTheDocument();
    expect(screen.getByText('Up to date')).toBeInTheDocument();
    expect(screen.queryByText('esp32-control-01')).not.toBeInTheDocument();
    expect(screen.getByText('Online')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'UV light' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Normal LED light' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Fish feeder' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'pH Up Syringe Pump' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'pH Down Syringe Pump' })).toBeInTheDocument();
    expect(screen.getAllByText('Idle')).toHaveLength(2);
    expect(screen.getAllByText('No dispense yet')).toHaveLength(2);
    expect(screen.getAllByText('Synced · Manila time')).toHaveLength(2);
    expect(screen.getAllByText('No enabled dose time')).toHaveLength(2);
    expect(screen.getAllByText('Dispense count')).toHaveLength(2);
    expect(screen.getAllByText('Last dispense')).toHaveLength(2);
    expect(screen.getAllByText('Estimated remaining')).toHaveLength(2);
    expect(screen.getAllByText('Fill check')).toHaveLength(2);
    expect(screen.getAllByText('Schedule time')).toHaveLength(2);
    expect(screen.getAllByText('Cooldown clears')).toHaveLength(2);
    expect(screen.getAllByText('Next scheduled dose')).toHaveLength(2);
    expect(screen.getAllByText('Dosing schedule')).toHaveLength(2);
    expect(screen.getAllByRole('button', { name: 'Save dosing schedule' })).toHaveLength(2);
    expect(screen.queryByText('Use the manual controls for pump maintenance and set chemical dosing times below.')).not.toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Pump controls' })).toBeInTheDocument();
    expect(screen.getByText('Manage dosing schedules and review syringe levels.')).toBeInTheDocument();
    expect(screen.queryByText(/safety|test|maintenance/i)).not.toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: 'pH Up Syringe Pump manual dispense' })).toHaveLength(1);
    expect(screen.getByRole('button', { name: 'Feed now' })).toBeInTheDocument();
    expect(screen.getByText('Up to 3 daily times')).toBeInTheDocument();
  });

  it('keeps the tank-page snapshot compact and defers history to the full route', async () => {
    renderPanel('summary');

    expect(await screen.findByRole('heading', { name: 'Equipment snapshot' })).toBeInTheDocument();
    expect(await screen.findByRole('heading', { name: 'Syringe pumps' })).toBeInTheDocument();
    expect(screen.getByText('pH Up')).toBeInTheDocument();
    expect(screen.getByText('pH Down')).toBeInTheDocument();
    expect(screen.getByText(/Pump A ·/)).toBeInTheDocument();
    expect(screen.getByText(/Pump B ·/)).toBeInTheDocument();
    expect(screen.queryByText('Pump page')).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: /^Full controls$/ })).toHaveAttribute('href', '/admin/tanks/1/actuators');
    expect(screen.queryByRole('heading', { name: 'Command history' })).not.toBeInTheDocument();
    expect(vi.mocked(api).mock.calls.some(([path]) => path.includes('/actuators/history'))).toBe(false);
  });

  it('does not present an enabled schedule as missing while the device clock is unsynced', async () => {
    const unsyncedStatus = {
      ...status,
      actuators: status.actuators.map((item) => item.actuator === 'pump_a'
        ? { ...item, state: {
          ...item.state,
          clock_synced: false,
          schedule: [
            { enabled: true, time: '08:00' },
            { enabled: false, time: '12:00' },
            { enabled: false, time: '18:00' },
          ],
          next_dose_at: null,
        } }
        : item),
    };
    vi.mocked(api).mockImplementation((path: string) => {
      if (path === '/tanks/1/actuators/status') return Promise.resolve(unsyncedStatus);
      if (path === '/tanks/1/actuators/history?page=1&page_size=10') {
        return Promise.resolve({ items: [], page: 1, page_size: 10, total: 0, total_pages: 0, has_previous: false, has_next: false, summary: emptySummary });
      }
      return Promise.reject(new Error(`Unexpected path ${path}`));
    });

    renderPanel();
    const pumpCard = (await screen.findByRole('heading', { name: 'pH Up Syringe Pump' })).closest('article');
    expect(pumpCard).not.toBeNull();
    const pump = within(pumpCard!);
    expect(pump.getByText('Not synced — dosing paused')).toBeInTheDocument();
    expect(pump.getAllByText('Unavailable until device time syncs')).toHaveLength(2);
    expect(pump.queryByText('Not scheduled')).not.toBeInTheDocument();
    expect(pump.queryByText('No enabled dose time')).not.toBeInTheDocument();
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
    expect(document.querySelector('[data-sonner-toast]')).toBeInTheDocument();
  });

  it('requires confirmation for a manual dispense and retract', async () => {
    const user = userEvent.setup();
    renderPanel();
    expect((await screen.findAllByText('Dose volume')).length).toBe(4);
    expect(screen.getAllByText('1.00 mL')).toHaveLength(4);
    await user.click(screen.getByRole('button', { name: 'pH Up Syringe Pump manual dispense' }));
    let dialog = screen.getByRole('alertdialog');
    expect(dialog).toHaveTextContent('This runs one preset pump cycle (1.00 mL)');
    expect(dialog).toHaveTextContent('water or an empty syringe only; do not use chemicals');
    expect(dialog).toHaveTextContent('Estimated remaining volume may change');
    expect(dialog).toHaveTextContent('does not start the chemical-dose cooldown');
    expect(dialog).toHaveTextContent('Stay beside the equipment and be ready to press Stop');
    expect(dialog).toHaveTextContent('Tank: Tank 1');
    expect(dialog).toHaveTextContent('Equipment: Online');
    expect(dialog).not.toHaveTextContent('esp32-control-01');
    await user.click(within(dialog).getByRole('button', { name: 'Run manual cycle' }));
    await screen.findByText('pH Up Syringe Pump manual dispense request submitted. Pump status will update after processing.');

    await user.click(screen.getByRole('button', { name: 'pH Up Syringe Pump retract' }));
    dialog = screen.getByRole('alertdialog');
    expect(dialog).toHaveTextContent('retract motor action');
    await user.click(within(dialog).getByRole('button', { name: 'Retract' }));
    await screen.findByText('pH Up Syringe Pump retract request submitted. Pump status will update after processing.');

    const calls = vi.mocked(api).mock.calls.filter(([path, init]) => path === '/tanks/1/actuators/commands' && init?.method === 'POST');
    expect(calls.some(([, init]) => init?.body?.toString().includes('"actuator":"pump_a"') && init.body.toString().includes('"action":"test_dispense"') && init.body.toString().includes('"payload":{}') && init.body.toString().includes('"expires_in_seconds":20'))).toBe(true);
    expect(calls.some(([, init]) => init?.body?.toString().includes('"action":"retract"'))).toBe(true);
  });

  it('confirms a chemical dosing schedule before queuing it', async () => {
    const user = userEvent.setup();
    renderPanel();
    const pumpCard = (await screen.findByRole('heading', { name: 'pH Up Syringe Pump' })).closest('article');
    expect(pumpCard).not.toBeNull();
    const pump = within(pumpCard!);
    await user.click(pump.getByRole('checkbox', { name: 'Dose time 1' }));
    await user.click(pump.getByRole('button', { name: 'Save dosing schedule' }));

    const dialog = screen.getByRole('alertdialog');
    expect(dialog).toHaveTextContent('dispense 1.00 mL at 08:00 Manila time');
    expect(dialog).toHaveTextContent('Save the dosing schedule for pH Up Syringe Pump?');
    expect(dialog).toHaveTextContent('Both pumps share a two-hour minimum interval');
    expect(dialog).toHaveTextContent('not triggered by pH');
    expect(dialog).toHaveTextContent('it is skipped and not rescheduled');
    expect(vi.mocked(api).mock.calls.some(([path, init]) => path === '/tanks/1/actuators/commands' && init?.method === 'POST')).toBe(false);

    expect(dialog).toHaveTextContent('Doses follow this schedule and are not triggered by pH');
    await user.click(within(dialog).getByRole('button', { name: 'Save schedule' }));
    await screen.findByText('pH Up Syringe Pump dosing schedule request submitted. Pump status will update after processing.');
    const call = vi.mocked(api).mock.calls.find(([path, init]) => path === '/tanks/1/actuators/commands' && init?.method === 'POST');
    expect(call?.[1]?.body).toContain('"actuator":"pump_a"');
    expect(call?.[1]?.body).toContain('"action":"schedule"');
    expect(call?.[1]?.body).toContain('"slots":[{"enabled":true,"time":"08:00"}');
    expect(call?.[1]?.body).toContain('\"expires_in_seconds\":120');
  });

  it('shows remaining volume and cooldown state, then confirms physical refill without motor movement', async () => {
    const user = userEvent.setup();
    const depletedStatus = {
      ...status,
      actuators: status.actuators.map((item) => item.actuator === 'pump_a'
        ? { ...item, state: { ...item.state, remaining_ml: 0, refill_required: true, next_eligible_at: '2026-08-15T14:00:00+08:00' } }
        : item),
    };
    vi.mocked(api).mockImplementation((path: string, init?: RequestInit) => {
      if (path === '/tanks/1/actuators/status') return Promise.resolve(depletedStatus);
      if (path === '/tanks/1/actuators/history?page=1&page_size=10') {
        return Promise.resolve({ items: [], page: 1, page_size: 10, total: 0, total_pages: 0, has_previous: false, has_next: false, summary: emptySummary });
      }
      if (path === '/tanks/1/actuators/commands' && init?.method === 'POST') return Promise.resolve({ command_id: 'refill-command', status: 'queued' });
      return Promise.reject(new Error(`Unexpected path ${path}`));
    });

    renderPanel();
    const pumpCard = (await screen.findByRole('heading', { name: 'pH Up Syringe Pump' })).closest('article');
    expect(pumpCard).not.toBeNull();
    const pump = within(pumpCard!);
    expect(pump.getByText('0.00 mL of 5.00 mL')).toBeInTheDocument();
    expect(pump.getByText('Confirmation needed')).toBeInTheDocument();
    expect(pump.getByText('Available now')).toBeInTheDocument();
    expect(pump.getByText('No enabled dose time')).toBeInTheDocument();
    expect(pump.getByRole('button', { name: 'pH Up Syringe Pump manual dispense' })).toBeDisabled();

    await user.click(pump.getByRole('button', { name: 'pH Up Syringe Pump confirm refill' }));
    const dialog = screen.getByRole('alertdialog');
    expect(dialog).toHaveTextContent('Physically check the syringe and refill it to 5.00 mL if needed');
    expect(dialog).toHaveTextContent('does not move the motor');
    expect(dialog).toHaveTextContent('does not move the motor or reset the two-hour cooldown');
    expect(dialog).toHaveTextContent('Cooldown clears: Available now');
    await user.click(within(dialog).getByRole('button', { name: 'Confirm refill' }));
    await screen.findByText('pH Up Syringe Pump refill confirmation request submitted. Pump status will update after processing.');
    const call = vi.mocked(api).mock.calls.find(([path, init]) => path === '/tanks/1/actuators/commands' && init?.method === 'POST');
    expect(call?.[1]?.body).toContain('"action":"refill_confirm"');
    expect(call?.[1]?.body).toContain('"actuator":"pump_a"');
    expect(call?.[1]?.body).toContain('\"expires_in_seconds\":120');
  });

  it('translates a blocked scheduled dose inline and in its alert when status changes', async () => {
    const user = userEvent.setup();
    const blockedMessage = 'Scheduled dose skipped: shared two-hour cooldown is active.';
    let statusReads = 0;
    vi.mocked(api).mockImplementation((path: string, init?: RequestInit) => {
      if (path === '/tanks/1/actuators/status') {
        statusReads += 1;
        if (statusReads > 1) {
          return Promise.resolve({
            ...status,
            actuators: status.actuators.map((item) => item.actuator === 'pump_a'
              ? { ...item, state: { ...item.state, schedule_event: blockedMessage } }
              : item),
          });
        }
        return Promise.resolve(status);
      }
      if (path === '/tanks/1/actuators/history?page=1&page_size=10') {
        return Promise.resolve({ items: [], page: 1, page_size: 10, total: 0, total_pages: 0, has_previous: false, has_next: false, summary: emptySummary });
      }
      if (path === '/tanks/1/actuators/commands' && init?.method === 'POST') return Promise.resolve({ command_id: 'feed-command', status: 'queued' });
      return Promise.reject(new Error(`Unexpected path ${path}`));
    });

    renderPanel();
    await user.click(await screen.findByRole('button', { name: 'Feed now' }));
    await user.click(within(screen.getByRole('alertdialog')).getByRole('button', { name: 'Feed now' }));
    await screen.findAllByText('Manual feed request queued. The system will update its status after processing.');
    const operatorMessage = 'Scheduled dose skipped because the two-hour minimum interval has not passed.';
    expect(await screen.findAllByText(operatorMessage)).not.toHaveLength(0);
    await waitFor(() => expect(document.querySelector('[data-sonner-toast]')).toHaveTextContent(operatorMessage));
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
    await user.selectOptions(screen.getByRole('combobox', { name: 'Filter history by equipment' }), 'uv');
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
    expect(screen.getByLabelText('Command executing')).toBeInTheDocument();
    expect(screen.getByLabelText('Command failed')).toBeInTheDocument();
    expect(screen.getByLabelText('Command expired')).toBeInTheDocument();
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
    expect(screen.getByText('Light and feeder requests may expire while waiting. Pump controls are available when the equipment is online.')).toBeInTheDocument();
    expect(screen.getAllByText('Pump controls require an online equipment connection.')).toHaveLength(2);
    expect(screen.getByRole('button', { name: 'pH Up Syringe Pump manual dispense' })).toBeDisabled();
  });

  it('locks only the uncertain pump dispense and gates administrator physical verification', async () => {
    const user = userEvent.setup();
    const unknownStatus = {
      ...status,
      pump_dispense_locks: [{
        actuator: 'pump_a' as const,
        command_id: 'unknown-pump-command',
        status: 'outcome_unknown' as const,
        verification_required: true,
      }],
    };
    const unknownCommand = {
      command_id: 'unknown-pump-command',
      tank_id: 1,
      device_id: 'esp32-control-01',
      actor_user_id: 1,
      actor_name: 'Test Admin',
      actuator: 'pump_a',
      action: 'dispense',
      payload: {},
      status: 'outcome_unknown',
      requested_at: '2026-08-15T10:00:00Z',
      expires_at: '2026-08-15T10:00:20Z',
      executing_at: '2026-08-15T10:00:01Z',
      confirmation_deadline_at: '2026-08-15T10:03:01Z',
      outcome_unknown_at: '2026-08-15T10:03:02Z',
      execution_at: null,
      result: null,
      error: 'Confirmation deadline elapsed; physical outcome is unknown',
      physical_verification_user_id: null,
      physical_verification_actor_name: null,
      physical_verification_at: null,
      physical_verification_note: null,
    };
    vi.mocked(api).mockImplementation((path: string, init?: RequestInit) => {
      if (path === '/tanks/1/actuators/status') return Promise.resolve(unknownStatus);
      if (path.startsWith('/tanks/1/actuators/history')) {
        return Promise.resolve({ items: [unknownCommand], page: 1, page_size: 10, total: 1, total_pages: 1, has_previous: false, has_next: false, summary: { ...emptySummary, total: 1, outcome_unknown: 1 } });
      }
      if (path === '/tanks/1/actuators/commands/unknown-pump-command/clear-uncertainty' && init?.method === 'POST') {
        return Promise.resolve({ ...unknownCommand, physical_verification_user_id: 1, physical_verification_actor_name: 'Test Admin', physical_verification_at: '2026-08-15T10:04:00Z' });
      }
      return Promise.reject(new Error(`Unexpected path ${path}`));
    });

    renderPanel();
    expect(await screen.findByText('The previous dispense may have happened. Check the pump in person before another dispense.')).toBeInTheDocument();
    expect(screen.getByText('Stop remains available while the equipment connection is online. Recording this check only clears the software lock; it does not prove how much was previously dispensed.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'pH Up Syringe Pump manual dispense' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'pH Up Syringe Pump stop' })).toBeEnabled();
    expect(screen.getAllByText('Outcome unknown').length).toBeGreaterThanOrEqual(2);

    await user.click(screen.getByRole('button', { name: 'Record pump check' }));
    const dialog = screen.getByRole('alertdialog');
    expect(dialog).toHaveTextContent('does not prove how much liquid was previously dispensed');
    await user.click(within(dialog).getByRole('button', { name: 'Record pump check' }));
    await screen.findByText('Pump check recorded. The historical command remains Outcome unknown; the software lock is cleared, and the amount previously dispensed is still unknown.');
  });

  it('renders a non-usable staff notice without fetching actuator APIs', () => {
    render(<StaffActuatorNotice />);
    expect(screen.getByText('Administrator access required')).toBeInTheDocument();
    expect(api).not.toHaveBeenCalled();
  });
});
