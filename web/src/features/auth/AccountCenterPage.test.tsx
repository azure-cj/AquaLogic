import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';

import AccountCenterPage from './AccountCenterPage';

const meMock = vi.fn();
const apiMock = vi.fn();

vi.mock('@/shared/api/client', () => ({
  api: (...args: unknown[]) => apiMock(...args),
  statusText: (value: string) => value,
}));

vi.mock('@/shared/hooks/useMe', () => ({
  useMe: () => meMock(),
}));

afterEach(() => vi.clearAllMocks());

function renderPage(role: 'admin' | 'staff') {
  meMock.mockReturnValue({ data: { role } });
  apiMock.mockResolvedValue([]);
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <AccountCenterPage />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('AccountCenterPage', () => {
  it('shows personal security and hides staff administration for staff users', () => {
    renderPage('staff');

    expect(screen.getByRole('heading', { name: 'Account center' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Security/ })).toHaveAttribute('href', '/admin/security');
    expect(screen.queryByRole('link', { name: /Staff & roles/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Administration' })).not.toBeInTheDocument();
  });

  it('shows both account destinations for administrators', () => {
    renderPage('admin');

    const accessButton = screen.getByRole('button', { name: 'What you can access' });
    expect(accessButton).toHaveAttribute('aria-expanded', 'false');
    fireEvent.click(accessButton);
    expect(screen.getByRole('dialog', { name: 'What you can access' })).toBeInTheDocument();
    expect(screen.getByText(/Manage staff accounts, roles, account status/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Security/ })).toHaveAttribute('href', '/admin/security');
    expect(screen.getByRole('link', { name: /Staff & roles/ })).toHaveAttribute('href', '/admin/staff');
    expect(screen.getByRole('heading', { name: 'Administration' })).toBeInTheDocument();
  });
});
