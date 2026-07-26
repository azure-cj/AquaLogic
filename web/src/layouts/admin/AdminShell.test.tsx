import AdminShell from './AdminShell';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocked = vi.hoisted(() => ({
  prefetch: vi.fn(),
  me: {
    isLoading: false,
    isError: true,
    data: undefined as
      | undefined
      | {
          name: string;
          role: 'admin' | 'staff';
          must_change_password: boolean;
        },
  },
}));

vi.mock('@/app/route-loaders', () => ({
  prefetchAdminRoute: mocked.prefetch,
}));
vi.mock('@/shared/hooks/useMe', () => ({
  useMe: () => mocked.me,
}));
vi.mock('@/shared/api/client', async (importOriginal) => {
  const original =
    await importOriginal<typeof import('@/shared/api/client')>();
  return {
    ...original,
    api: vi.fn().mockResolvedValue([]),
  };
});

function renderShell() {
  return render(
    <QueryClientProvider client={new QueryClient()}>
      <MemoryRouter initialEntries={['/admin/fleet']}>
        <Routes>
          <Route path="/admin" element={<AdminShell />}>
            <Route path="fleet" element={<div>Fleet content</div>} />
          </Route>
          <Route path="/admin/login" element={<div>Login destination</div>} />
          <Route
            path="/admin/change-password"
            element={<div>Password destination</div>}
          />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('admin shell guards and navigation', () => {
  beforeEach(() => {
    mocked.prefetch.mockClear();
    mocked.me.isLoading = false;
    mocked.me.isError = true;
    mocked.me.data = undefined;
  });

  it('redirects failed sessions to login', async () => {
    renderShell();
    expect(await screen.findByText('Login destination')).toBeInTheDocument();
  });

  it('redirects forced password changes before showing admin content', async () => {
    mocked.me.isError = false;
    mocked.me.data = {
      name: 'Demo Admin',
      role: 'admin',
      must_change_password: true,
    };
    renderShell();
    expect(await screen.findByText('Password destination')).toBeInTheDocument();
  });

  it('keeps administrator-only navigation hidden from staff', async () => {
    mocked.me.isError = false;
    mocked.me.data = {
      name: 'Operations Staff',
      role: 'staff',
      must_change_password: false,
    };
    renderShell();
    expect(await screen.findByText('Fleet content')).toBeInTheDocument();
    expect(screen.queryByText('Staff & roles')).not.toBeInTheDocument();
    expect(screen.queryByText('Thresholds')).not.toBeInTheDocument();
  });

  it('prefetches a destination when navigation intent is shown', async () => {
    mocked.me.isError = false;
    mocked.me.data = {
      name: 'Operations Staff',
      role: 'staff',
      must_change_password: false,
    };
    renderShell();
    const alertsLink = await screen.findByRole('link', { name: 'Alerts' });
    fireEvent.pointerEnter(alertsLink);
    expect(mocked.prefetch).toHaveBeenCalledWith('/admin/alerts');
  });
});
