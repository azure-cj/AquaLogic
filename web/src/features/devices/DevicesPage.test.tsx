import { api } from '@/shared/api/client';
import { useMe } from '@/shared/hooks/useMe';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import DevicesPage from './DevicesPage';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

vi.mock('@/shared/hooks/useMe', () => ({
  useMe: vi.fn(),
}));

const devices = [
  {
    device_id: 'bridge-front',
    tank_id: 1,
    tank_name: 'Front display',
    is_active: true,
    created_at: '2026-08-20T08:00:00Z',
    last_seen_at: '2026-08-21T08:00:00Z',
    status: 'online' as const,
  },
  {
    device_id: 'bridge-old',
    tank_id: 2,
    tank_name: 'Quarantine tank',
    is_active: false,
    created_at: '2026-08-19T08:00:00Z',
    last_seen_at: null,
    status: 'disabled' as const,
  },
];

function meResult(role: 'admin' | 'staff') {
  return {
    data: {
      id: 1,
      name: role === 'admin' ? 'Admin User' : 'Staff User',
      email: `${role}@example.test`,
      role,
      is_active: true,
      must_change_password: false,
    },
    isLoading: false,
    isError: false,
  } as unknown as ReturnType<typeof useMe>;
}

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <DevicesPage />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('DevicesPage', () => {
  beforeEach(() => {
    vi.mocked(api).mockReset();
    vi.mocked(useMe).mockReset();
  });

  it('shows the administrator device inventory without exposing keys', async () => {
    vi.mocked(useMe).mockReturnValue(meResult('admin'));
    vi.mocked(api).mockResolvedValue(devices as never);

    renderPage();

    expect(await screen.findByRole('heading', { name: 'Device management' })).toBeInTheDocument();
    expect(await screen.findByText('bridge-front')).toBeInTheDocument();
    expect(screen.getByText('Front display')).toBeInTheDocument();
    expect(screen.getAllByText('Online').length).toBeGreaterThan(1);
    expect(screen.queryByText(/device-key|secret/i)).not.toBeInTheDocument();
  });

  it('requires confirmation before disabling a device', async () => {
    vi.mocked(useMe).mockReturnValue(meResult('admin'));
    vi.mocked(api).mockResolvedValue(devices as never);

    renderPage();

    await screen.findByText('bridge-front');
    fireEvent.click(screen.getAllByRole('button', { name: 'Disable' })[0]);
    expect(screen.getByRole('alertdialog', { name: 'Disable this device?' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Disable device' }));

    await waitFor(() => expect(api).toHaveBeenCalledWith('/devices/bridge-front', expect.objectContaining({ method: 'PATCH' })));
    expect(screen.queryByRole('alertdialog', { name: 'Disable this device?' })).not.toBeInTheDocument();
  });

  it('shows a rotated key once after confirmation', async () => {
    vi.mocked(useMe).mockReturnValue(meResult('admin'));
    vi.mocked(api)
      .mockResolvedValueOnce(devices as never)
      .mockResolvedValueOnce({ device_key: 'one-time-key', device_id: 'bridge-front', tank_id: 1, rotated_at: '2026-08-21T08:00:00Z' } as never)
      .mockResolvedValue(devices as never);

    renderPage();

    await screen.findByText('bridge-front');
    fireEvent.click(screen.getAllByRole('button', { name: 'Rotate key' })[0]);
    fireEvent.click(within(screen.getByRole('alertdialog')).getByRole('button', { name: 'Rotate key' }));

    expect(await screen.findByRole('heading', { name: 'New device key' })).toBeInTheDocument();
    expect(screen.getByText('one-time-key')).toBeInTheDocument();
    expect(window.localStorage.getItem('aqualogic-device-key')).toBeNull();
    expect(window.sessionStorage.getItem('aqualogic-device-key')).toBeNull();
  });

  it('does not fetch device data for staff users', async () => {
    vi.mocked(useMe).mockReturnValue(meResult('staff'));

    renderPage();

    expect(await screen.findByText('Administrator access required')).toBeInTheDocument();
    expect(api).not.toHaveBeenCalled();
  });
});
