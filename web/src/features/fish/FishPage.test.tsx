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
    ideal_temp_min: 24,
    ideal_temp_max: 28,
    ideal_ph_min: 6.5,
    ideal_ph_max: 7.5,
    ideal_tds_min: 100,
    ideal_tds_max: 300,
    diet_type: 'Carnivore',
    diet: 'Micropellets and occasional live food.',
    description: 'Colorful labyrinth fish.',
    tank_count: 2,
    assigned_tanks: [{ id: 1, name: 'Display tank' }, { id: 2, name: 'Quarantine tank' }],
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

    expect(await screen.findByText('Labyrinth fish', { selector: 'strong' })).toBeInTheDocument();
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

  it('supports explicit filters and a readable species details view', async () => {
    const user = userEvent.setup();
    renderPage();

    await user.click(await screen.findByRole('button', { name: 'View details for Betta' }));

    expect(await screen.findByRole('heading', { name: 'Preferred water conditions' })).toBeInTheDocument();
    expect(screen.getByText('24–28 °C')).toBeInTheDocument();
    expect(screen.getByText('Display tank')).toBeInTheDocument();

    await user.click(screen.getAllByRole('button', { name: 'Close' })[0]);
    await user.selectOptions(screen.getByRole('combobox', { name: 'Filter by care group' }), 'Livebearers');

    expect(screen.getByText('Molly', { selector: 'strong' })).toBeInTheDocument();
    expect(screen.queryByText('Betta', { selector: 'strong' })).not.toBeInTheDocument();
  });

  it('submits supported preferred water ranges from the species form', async () => {
    const user = userEvent.setup();
    renderPage();

    await user.click(screen.getByRole('button', { name: 'Add fish species' }));
    await user.type(await screen.findByRole('textbox', { name: 'Common name' }), 'Guppy');
    await user.type(screen.getByRole('textbox', { name: 'Scientific name' }), 'Poecilia reticulata');
    await user.type(screen.getByRole('spinbutton', { name: 'Temperature minimum (°C)' }), '24');
    await user.type(screen.getByRole('spinbutton', { name: 'Temperature maximum (°C)' }), '28');
    await user.click(screen.getByRole('button', { name: 'Save fish species' }));

    expect(api).toHaveBeenCalledWith('/fish', expect.objectContaining({
      method: 'POST',
      body: expect.stringContaining('"ideal_temp_min":"24"'),
    }));
  });

  it('uploads a validated species photo after saving the profile', async () => {
    const user = userEvent.setup();
    vi.mocked(api).mockImplementation((path: string) => Promise.resolve(
      path === '/fish/1' ? species[0] : species,
    ));
    renderPage();

    await user.click(await screen.findByRole('button', { name: 'Edit Betta' }));
    const file = new File(['fish-photo'], 'betta.png', { type: 'image/png' });
    await user.upload(await screen.findByTestId('fish-photo-upload'), file);
    await user.click(screen.getByRole('button', { name: 'Save fish species' }));

    const uploadCall = vi.mocked(api).mock.calls.find(([path]) => path === '/fish/1/photo-image');
    expect(uploadCall?.[1]).toEqual(expect.objectContaining({ method: 'POST', body: expect.any(FormData) }));
    expect((uploadCall?.[1]?.body as FormData).get('image')).toBe(file);
  });
});
