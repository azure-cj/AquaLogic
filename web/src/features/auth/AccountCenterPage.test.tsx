import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';

import AccountCenterPage from './AccountCenterPage';

const meMock = vi.fn();

vi.mock('@/shared/hooks/useMe', () => ({
  useMe: () => meMock(),
}));

afterEach(() => vi.clearAllMocks());

function renderPage(role: 'admin' | 'staff') {
  meMock.mockReturnValue({ data: { role } });
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

    expect(screen.getByRole('link', { name: /Security/ })).toHaveAttribute('href', '/admin/security');
    expect(screen.getByRole('link', { name: /Staff & roles/ })).toHaveAttribute('href', '/admin/staff');
    expect(screen.getByRole('heading', { name: 'Administration' })).toBeInTheDocument();
  });
});
