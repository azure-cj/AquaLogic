import { api } from '@/shared/api/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import Fish from './FishPage';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

const species = [
  {
    id: 1,
    common_name: 'Betta',
    scientific_name: 'Betta splendens',
    category: 'Labyrinth fish',
    diet_type: 'Carnivore',
    diet: 'Micropellets and occasional live food.',
    description: 'Colorful labyrinth fish.',
    tank_count: 2,
  },
  {
    id: 2,
    common_name: 'Molly',
    scientific_name: 'Poecilia sphenops',
    category: 'Livebearers',
    diet_type: 'Omnivore',
    diet: 'Algae-based food and flakes.',
    description: 'Hardy community fish.',
    tank_count: 0,
  },
];

function renderPage() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <Fish />
    </QueryClientProvider>,
  );
}

describe('Fish species directory', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.mocked(api).mockReset();
    vi.mocked(api).mockResolvedValue(species);
  });

  it('defaults to grouped view, protects assigned species, and remembers compact view', async () => {
    const user = userEvent.setup();
    renderPage();

    expect(await screen.findByText('Labyrinth fish')).toBeInTheDocument();
    const totalSpecies = screen.getByText('Total species');
    expect(totalSpecies.parentElement?.tagName).toBe('DIV');
    expect(totalSpecies.parentElement).toHaveTextContent('2Total species');
    expect(screen.getByRole('button', { name: 'Grouped' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    expect(
      screen.getByRole('button', {
        name: 'Cannot delete Betta; assigned to 2 tanks',
      }),
    ).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Delete Molly' })).toBeEnabled();

    await user.click(screen.getByRole('button', { name: 'Compact' }));

    expect(screen.getByRole('button', { name: 'Compact' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    expect(localStorage.getItem('aqualogic:fish-species-view')).toBe('compact');
    expect(screen.getByText('Diet & feeding')).toBeInTheDocument();
  });
});
