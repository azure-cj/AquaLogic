import { api } from '@/shared/api/client';
import { useMe } from '@/shared/hooks/useMe';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ActuatorDirectoryPage from './ActuatorDirectoryPage';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

vi.mock('@/shared/hooks/useMe', () => ({
  useMe: vi.fn(),
}));

const tanks = [
  {
    id: 1,
    public_id: 'display-one',
    name: 'Display tank',
    location: 'Front room',
    is_public: true,
    customer: { id: 4, name: 'JRed Client' },
  },
  {
    id: 2,
    public_id: 'nursery-two',
    name: 'Nursery tank',
    location: 'Back room',
    is_public: false,
    customer: null,
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
        <ActuatorDirectoryPage />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('actuator directory page', () => {
  beforeEach(() => {
    vi.mocked(api).mockReset();
    vi.mocked(useMe).mockReset();
  });

  it('lets administrators choose a tank and open its scoped controls', async () => {
    vi.mocked(useMe).mockReturnValue(meResult('admin'));
    vi.mocked(api).mockResolvedValue(tanks as never);

    renderPage();

    expect(await screen.findByRole('heading', { name: 'Actuator controls' })).toBeInTheDocument();
    const openControlLinks = await screen.findAllByRole('link', { name: /^Open controls$/ });
    expect(openControlLinks[0]).toHaveAttribute('href', '/admin/tanks/1/actuators');
    const tankWorkspaceLinks = screen.getAllByRole('link', { name: /^Tank workspace$/ });
    expect(tankWorkspaceLinks[0]).toHaveAttribute('href', '/admin/tanks/1');
    expect(screen.getByText('Nursery tank')).toBeInTheDocument();
    expect(screen.getByText('The browser chooses a tank view only. It never chooses a device, receives a device key, or contacts the ESP32 directly.')).toBeInTheDocument();
  });

  it('does not fetch the tank directory for staff users', async () => {
    vi.mocked(useMe).mockReturnValue(meResult('staff'));

    renderPage();

    expect(await screen.findByText('Administrator access required')).toBeInTheDocument();
    expect(api).not.toHaveBeenCalled();
  });
});
