import { api } from '@/shared/api/client';
import { useMe } from '@/shared/hooks/useMe';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ActuatorControlPage from './ActuatorControlPage';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

vi.mock('@/shared/hooks/useMe', () => ({
  useMe: vi.fn(),
}));

vi.mock('./ActuatorControlPanel', () => ({
  ActuatorControlPanel: ({ tankId, variant }: { tankId: number; variant: string }) => (
    <div data-testid="actuator-panel">Panel for tank {tankId} · {variant}</div>
  ),
  StaffActuatorNotice: () => <div>Administrator access required</div>,
}));

const tank = {
  id: 7,
  public_id: 'tank-seven',
  name: 'Quarantine tank',
  location: 'Test room',
  is_public: false,
};

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

function renderPage(path = '/admin/tanks/7/actuators') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route path="/admin/tanks/:tankId/actuators" element={<ActuatorControlPage />} />
          <Route path="/admin/tanks/:tankId" element={<div>Tank detail</div>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('dedicated actuator control page', () => {
  beforeEach(() => {
    vi.mocked(api).mockReset();
    vi.mocked(useMe).mockReset();
  });

  it('renders the full actuator workspace for an administrator', async () => {
    vi.mocked(useMe).mockReturnValue(meResult('admin'));
    vi.mocked(api).mockResolvedValue(tank as never);

    renderPage();

    expect(await screen.findByRole('heading', { name: 'Actuator control center' })).toBeInTheDocument();
    expect(await screen.findByTestId('actuator-panel')).toHaveTextContent('Panel for tank 7 · full');
    expect(screen.getByText(/Tank operations · Quarantine tank/)).toBeInTheDocument();
    expect(api).toHaveBeenCalledWith('/tanks/7');
  });

  it('shows the restriction notice for staff without fetching tank or actuator data', async () => {
    vi.mocked(useMe).mockReturnValue(meResult('staff'));

    renderPage();

    expect(await screen.findByRole('heading', { name: 'Actuator controls' })).toBeInTheDocument();
    expect(screen.getByText('Administrator access required')).toBeInTheDocument();
    expect(api).not.toHaveBeenCalled();
  });
});
