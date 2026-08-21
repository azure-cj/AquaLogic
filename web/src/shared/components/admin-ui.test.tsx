import { metricOptions } from '@/features/analytics/types';
import {
  fleetCounts,
  tankNameForAlert,
} from '@/features/fleet/utils';
import type { Alert, FleetTank } from '@/shared/api/models';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useState } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { Drawer, LifecycleBadge, StatusBadge } from './admin-ui';

const fleet: FleetTank[] = [
  {
    id: 1,
    public_id: 'one',
    name: 'Lobby Reef',
    location: 'Main lobby',
    customer: null,
    latest_reading: null,
    status: 'normal',
    last_reading_at: null,
    reporting_age_seconds: null,
    active_warning_count: 0,
    active_critical_count: 0,
  },
  {
    id: 2,
    public_id: 'two',
    name: 'Koi Pavilion',
    location: 'East wing',
    customer: null,
    latest_reading: null,
    status: 'critical',
    last_reading_at: null,
    reporting_age_seconds: null,
    active_warning_count: 0,
    active_critical_count: 1,
  },
  {
    id: 3,
    public_id: 'three',
    name: 'Quarantine',
    location: 'Back room',
    customer: null,
    latest_reading: null,
    status: 'offline',
    last_reading_at: null,
    reporting_age_seconds: null,
    active_warning_count: 0,
    active_critical_count: 0,
  },
];

describe('admin command center helpers', () => {
  it('counts every fleet status for the KPI cards', () => {
    expect(fleetCounts(fleet)).toEqual({
      total: 3,
      normal: 1,
      warning: 0,
      critical: 1,
      offline: 1,
    });
  });

  it('maps alert tank ids to readable names', () => {
    const alert = { tank_id: 2 } as Alert;
    expect(tankNameForAlert(alert, fleet)).toBe('Koi Pavilion');
  });

  it('exposes only current-release water metrics', () => {
    expect(metricOptions.map((metric) => metric.key)).toEqual([
      'temperature',
      'ph',
      'turbidity',
      'tds',
    ]);
  });
});

describe('admin UI primitives', () => {
  it('announces status without relying on colour', () => {
    render(<StatusBadge value="offline" />);
    expect(screen.getByLabelText(/no recent sensor report/i)).toHaveTextContent('Offline');
  });

  it('uses account lifecycle language instead of fleet status labels', () => {
    render(<LifecycleBadge status="setup_required" />);
    expect(screen.getByLabelText('Password setup required')).toHaveTextContent('Password setup required');
    expect(screen.queryByText('Warning')).not.toBeInTheDocument();
  });

  it('closes a drawer with Escape and restores focus', async () => {
    const onClose = vi.fn();
    const user = userEvent.setup();
    function Harness() {
      const [open, setOpen] = useState(false);
      return (
        <>
          <button type="button" onClick={() => setOpen(true)}>
            Open editor
          </button>
          <Drawer
            open={open}
            title="Edit tank"
            onClose={() => {
              onClose();
              setOpen(false);
            }}
          >
            <input aria-label="Tank name" />
          </Drawer>
        </>
      );
    }
    render(<Harness />);
    const opener = screen.getByRole('button', { name: 'Open editor' });
    await user.click(opener);
    await waitFor(() => expect(screen.getByRole('button', { name: 'Close' })).toHaveFocus());
    fireEvent.keyDown(document, { key: 'Escape' });
    await waitFor(() => expect(opener).toHaveFocus());
    expect(onClose).toHaveBeenCalledOnce();
  });
});
