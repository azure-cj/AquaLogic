import { api } from '@/shared/api/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { ResourceManager } from './ResourceManager';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original =
    await importOriginal<typeof import('@/shared/api/client')>();
  return {
    ...original,
    api: vi.fn(),
  };
});

describe('ResourceManager', () => {
  it('loads records and filters them through the shared search workflow', async () => {
    vi.mocked(api).mockResolvedValueOnce([
      { id: 1, name: 'Coral Bay' },
      { id: 2, name: 'Lobby Reef' },
    ]);
    const user = userEvent.setup();

    render(
      <QueryClientProvider client={new QueryClient()}>
        <ResourceManager
          title="Customers"
          singular="Customer"
          path="/customers"
          description="Customer directory"
          fields={[{ key: 'name', label: 'Name', required: true }]}
          searchValues={(record) => [String(record.name)]}
          renderRecord={(record) => <strong>{String(record.name)}</strong>}
        />
      </QueryClientProvider>,
    );

    expect(await screen.findByText('Coral Bay')).toBeInTheDocument();
    await user.type(screen.getByPlaceholderText('Search customers…'), 'Lobby');
    expect(screen.queryByText('Coral Bay')).not.toBeInTheDocument();
    expect(screen.getByText('Lobby Reef')).toBeInTheDocument();
  });
});
