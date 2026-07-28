import AdminShell from './AdminShell';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { adminNavigation, adminNavigationItemCount, NAVIGATION_FLAT_ITEM_LIMIT } from './navigation';

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

function renderShell(initialEntry = '/admin/fleet') {
  return render(
    <QueryClientProvider client={new QueryClient()}>
      <MemoryRouter initialEntries={[initialEntry]}>
        <Routes>
          <Route path="/admin" element={<AdminShell />}>
            <Route path="fleet" element={<div>Fleet content</div>} />
            <Route path="*" element={<div>Admin content</div>} />
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
    expect(screen.queryByRole('button', { name: 'Configure' })).not.toBeInTheDocument();
  });

  it('keeps all flat navigation entries in the grouped config order', () => {
    expect(adminNavigation.map((group) => group.label)).toEqual(['Monitor', 'Manage', 'Configure']);
    expect(adminNavigation.flatMap((group) => group.items.map((item) => item.label))).toEqual([
      'Fleet overview',
      'Alerts',
      'Analytics',
      'Tanks',
      'Fish species',
      'Customers',
      'Security',
      'Staff & roles',
      'Thresholds',
    ]);
    expect(adminNavigationItemCount).toBeGreaterThan(NAVIGATION_FLAT_ITEM_LIMIT);
  });

  it('prefetches a destination when navigation intent is shown', async () => {
    mocked.me.isError = false;
    mocked.me.data = {
      name: 'Operations Staff',
      role: 'staff',
      must_change_password: false,
    };
    renderShell();
    const alertsLinks = await screen.findAllByRole('link', { name: 'Alerts' });
    fireEvent.pointerEnter(alertsLinks[0]);
    expect(mocked.prefetch).toHaveBeenCalledWith('/admin/alerts');
  });

  it('toggles cluster menus and dismisses them with Escape or an outside pointer', async () => {
    mocked.me.isError = false;
    mocked.me.data = {
      name: 'Demo Admin',
      role: 'admin',
      must_change_password: false,
    };
    renderShell();

    const monitorToggle = screen.getByRole('button', { name: 'Monitor' });
    fireEvent.click(monitorToggle);
    expect(monitorToggle).toHaveAttribute('aria-expanded', 'true');

    fireEvent.keyDown(document, { key: 'Escape' });
    await waitFor(() => expect(monitorToggle).toHaveAttribute('aria-expanded', 'false'));

    fireEvent.click(monitorToggle);
    fireEvent.pointerDown(document.body);
    await waitFor(() => expect(monitorToggle).toHaveAttribute('aria-expanded', 'false'));
  });

  it('closes an open cluster after navigating to one of its pages', async () => {
    mocked.me.isError = false;
    mocked.me.data = {
      name: 'Demo Admin',
      role: 'admin',
      must_change_password: false,
    };
    renderShell();

    const monitorToggle = screen.getByRole('button', { name: 'Monitor' });
    fireEvent.click(monitorToggle);
    fireEvent.click(screen.getAllByRole('link', { name: 'Alerts' })[0]);

    await waitFor(() => expect(monitorToggle).toHaveAttribute('aria-expanded', 'false'));
  });

  it('clears stale horizontal scroll before painting a client-side route', async () => {
    mocked.me.isError = false;
    mocked.me.data = {
      name: 'Demo Admin',
      role: 'admin',
      must_change_password: false,
    };
    renderShell();

    const main = document.querySelector<HTMLElement>('.admin-main');
    expect(main).not.toBeNull();
    document.documentElement.scrollLeft = 96;
    document.body.scrollLeft = 96;
    main!.scrollLeft = 96;

    fireEvent.click(screen.getAllByRole('link', { name: 'Tanks' })[0]);

    await waitFor(() => {
      expect(document.documentElement.scrollLeft).toBe(0);
      expect(document.body.scrollLeft).toBe(0);
      expect(main!.scrollLeft).toBe(0);
    });
  });
});
