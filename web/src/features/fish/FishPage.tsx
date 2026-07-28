import { api } from '@/shared/api/client';
import type { Fish as ApiFish } from '@/shared/api/models';
import {
  ConfirmDialog,
  Drawer,
  ErrorState,
  LoadingState,
  Notice,
} from '@/shared/components/admin-ui';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  ChevronDown,
  FishSymbol,
  Layers3,
  List,
  Pencil,
  Plus,
  Search,
  ShieldCheck,
  SlidersHorizontal,
  Trash2,
  X,
} from 'lucide-react';
import { FormEvent, useMemo, useState } from 'react';

import './compact.css';
import './grouped.css';
import './styles.css';

type DietType = 'Carnivore' | 'Omnivore' | 'Herbivore';
type ViewMode = 'grouped' | 'compact';

type FishRecord = ApiFish & {
  category: string;
  diet_type?: DietType | null;
  tank_count: number;
};

const viewStorageKey = 'aqualogic:fish-species-view';
const categorySuggestions = [
  'Livebearers',
  'Cichlids',
  'Coldwater',
  'Schooling fish',
  'Bottom dwellers',
  'Labyrinth fish',
  'Marine',
  'Other',
];

function initialView(): ViewMode {
  try {
    return localStorage.getItem(viewStorageKey) === 'compact' ? 'compact' : 'grouped';
  } catch {
    return 'grouped';
  }
}

function SpeciesImage({
  fish,
  compact = false,
}: {
  fish: FishRecord;
  compact?: boolean;
}) {
  const [failed, setFailed] = useState(false);
  const className = compact ? 'compact-fish__thumbnail' : 'fdg-species-image';

  return (
    <span className={className} aria-hidden="true">
      {fish.photo_url && !failed ? (
        <img
          src={fish.photo_url}
          alt=""
          loading="lazy"
          onError={() => setFailed(true)}
        />
      ) : (
        <FishSymbol size={compact ? 22 : 19} />
      )}
    </span>
  );
}

function DietDetails({ fish, compact = false }: { fish: FishRecord; compact?: boolean }) {
  const diet = fish.diet_type ?? 'Not set';
  const normalized = fish.diet_type?.toLowerCase() ?? 'unset';
  return (
    <div className={compact ? 'compact-fish__diet' : 'fdg-diet'}>
      <span
        className={
          compact
            ? `compact-fish__diet-badge compact-fish__diet-badge--${normalized}`
            : `fdg-diet-badge fdg-${normalized}`
        }
      >
        {diet}
      </span>
      <small>{fish.diet || 'No feeding details added.'}</small>
    </div>
  );
}

function Usage({ fish, compact = false }: { fish: FishRecord; compact?: boolean }) {
  const inUse = fish.tank_count > 0;
  if (compact) {
    return (
      <div className={`compact-fish__usage ${inUse ? 'is-assigned' : ''}`}>
        <span className="compact-fish__usage-count">{fish.tank_count}</span>
        <span>
          <strong>
            {inUse
              ? `${fish.tank_count} ${fish.tank_count === 1 ? 'tank' : 'tanks'}`
              : 'Unused'}
          </strong>
          <small>{inUse ? 'Currently assigned' : 'Safe to delete'}</small>
        </span>
      </div>
    );
  }
  return (
    <div className={`fdg-usage ${inUse ? '' : 'is-unused'}`}>
      <strong>
        {inUse
          ? `${fish.tank_count} ${fish.tank_count === 1 ? 'tank' : 'tanks'}`
          : 'Not in use'}
      </strong>
      <small>{inUse ? 'Assigned species' : 'Safe to remove'}</small>
    </div>
  );
}

function RowActions({
  fish,
  compact = false,
  onEdit,
  onDelete,
}: {
  fish: FishRecord;
  compact?: boolean;
  onEdit: (fish: FishRecord) => void;
  onDelete: (fish: FishRecord) => void;
}) {
  const inUse = fish.tank_count > 0;
  const className = compact ? 'compact-fish__actions' : 'fdg-actions';
  return (
    <div className={className}>
      <button
        type="button"
        onClick={() => onEdit(fish)}
        aria-label={`Edit ${fish.common_name}`}
        title={`Edit ${fish.common_name}`}
      >
        <Pencil size={16} />
      </button>
      <button
        className={compact ? 'compact-fish__delete' : 'fdg-delete'}
        type="button"
        disabled={inUse}
        onClick={() => onDelete(fish)}
        aria-label={
          inUse
            ? `Cannot delete ${fish.common_name}; assigned to ${fish.tank_count} tanks`
            : `Delete ${fish.common_name}`
        }
        title={
          inUse
            ? `Remove this species from ${fish.tank_count} tanks before deleting`
            : `Delete ${fish.common_name}`
        }
      >
        {compact && inUse ? <ShieldCheck size={16} /> : <Trash2 size={16} />}
      </button>
    </div>
  );
}

export function Fish() {
  const queryClient = useQueryClient();
  const query = useQuery({
    queryKey: ['/fish'],
    queryFn: () => api<FishRecord[]>('/fish'),
  });
  const [view, setView] = useState<ViewMode>(initialView);
  const [search, setSearch] = useState('');
  const [diet, setDiet] = useState<'All diets' | DietType>('All diets');
  const [onlyInUse, setOnlyInUse] = useState(false);
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const [editing, setEditing] = useState<Partial<FishRecord> | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<FishRecord | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const fish = query.data ?? [];
  const visible = useMemo(() => {
    const normalized = search.trim().toLowerCase();
    return fish.filter((item) => {
      const matchesSearch =
        !normalized ||
        [
          item.common_name,
          item.scientific_name,
          item.category,
          item.description,
          item.diet,
          item.diet_type,
        ].some((value) => value?.toLowerCase().includes(normalized));
      const matchesDiet = diet === 'All diets' || item.diet_type === diet;
      return matchesSearch && matchesDiet && (!onlyInUse || item.tank_count > 0);
    });
  }, [diet, fish, onlyInUse, search]);

  const grouped = useMemo(() => {
    const groups = new Map<string, FishRecord[]>();
    visible.forEach((item) => {
      const category = item.category || 'Other';
      groups.set(category, [...(groups.get(category) ?? []), item]);
    });
    return [...groups.entries()].sort(([left], [right]) => left.localeCompare(right));
  }, [visible]);

  const setViewMode = (next: ViewMode) => {
    setView(next);
    try {
      localStorage.setItem(viewStorageKey, next);
    } catch {
      // The view still changes for this session when storage is unavailable.
    }
  };

  const startEdit = (item: FishRecord) => {
    setError('');
    setEditing(item);
  };

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    const form = new FormData(event.currentTarget);
    const body = Object.fromEntries(
      [
        'common_name',
        'scientific_name',
        'category',
        'diet_type',
        'photo_url',
        'description',
        'diet',
        'compatibility_notes',
        'care_tips',
      ].map((key) => [key, form.get(key) || null]),
    );
    try {
      await api(editing?.id ? `/fish/${editing.id}` : '/fish', {
        method: editing?.id ? 'PUT' : 'POST',
        body: JSON.stringify(body),
      });
      setNotice(`${body.common_name} ${editing?.id ? 'updated' : 'created'} successfully.`);
      setEditing(null);
      await queryClient.invalidateQueries({ queryKey: ['/fish'] });
      await queryClient.invalidateQueries({ queryKey: ['fish'] });
      await queryClient.invalidateQueries({ queryKey: ['species-suitability'] });
      await queryClient.invalidateQueries({ queryKey: ['fleet'] });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to save fish species');
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    if (!deleteTarget) return;
    setBusy(true);
    setError('');
    try {
      await api(`/fish/${deleteTarget.id}`, { method: 'DELETE' });
      setNotice(`${deleteTarget.common_name} deleted successfully.`);
      setDeleteTarget(null);
      await queryClient.invalidateQueries({ queryKey: ['/fish'] });
      await queryClient.invalidateQueries({ queryKey: ['fish'] });
      await queryClient.invalidateQueries({ queryKey: ['species-suitability'] });
      await queryClient.invalidateQueries({ queryKey: ['fleet'] });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to delete fish species');
      setDeleteTarget(null);
    } finally {
      setBusy(false);
    }
  };

  const clearFilters = () => {
    setSearch('');
    setDiet('All diets');
    setOnlyInUse(false);
  };

  return (
    <section className="fdg-page fish-directory">
      <header className="fdg-page-header">
        <div>
          <span className="fdg-eyebrow">Species library</span>
          <h1>Fish species</h1>
          <p>Manage care details and see where each species is currently used.</p>
        </div>
        <div className="fish-directory__header-actions">
          <div className="fish-view-toggle" aria-label="Species view">
            <button
              className={view === 'grouped' ? 'is-active' : ''}
              type="button"
              onClick={() => setViewMode('grouped')}
              aria-pressed={view === 'grouped'}
            >
              <Layers3 size={16} />
              Grouped
            </button>
            <button
              className={view === 'compact' ? 'is-active' : ''}
              type="button"
              onClick={() => setViewMode('compact')}
              aria-pressed={view === 'compact'}
            >
              <List size={16} />
              Compact
            </button>
          </div>
          <button
            className="fdg-primary-button"
            type="button"
            onClick={() => {
              setError('');
              setEditing({ category: 'Other' });
            }}
          >
            <Plus size={17} />
            Add fish species
          </button>
        </div>
      </header>

      {notice && <Notice>{notice}</Notice>}
      {error && !editing && <Notice tone="error">{error}</Notice>}

      <div className="fdg-summary" aria-label="Species library summary">
        <div>
          <strong>{fish.length}</strong>
          <span>Total species</span>
        </div>
        <div>
          <strong>{new Set(fish.map((item) => item.category || 'Other')).size}</strong>
          <span>Care groups</span>
        </div>
        <div>
          <strong>{fish.filter((item) => item.tank_count > 0).length}</strong>
          <span>Currently in use</span>
        </div>
      </div>

      <div className="fdg-toolbar">
        <label className="fdg-search">
          <Search size={17} aria-hidden="true" />
          <span className="fdg-sr-only">Search fish species</span>
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search name, scientific name, or group…"
          />
          {search && (
            <button type="button" onClick={() => setSearch('')} aria-label="Clear search">
              <X size={14} />
            </button>
          )}
        </label>
        <div className="fdg-filters" aria-label="Species filters">
          <SlidersHorizontal size={16} aria-hidden="true" />
          <select
            value={diet}
            onChange={(event) => setDiet(event.target.value as typeof diet)}
            aria-label="Filter by diet"
          >
            <option>All diets</option>
            <option>Carnivore</option>
            <option>Omnivore</option>
            <option>Herbivore</option>
          </select>
          <label className="fdg-toggle">
            <input
              type="checkbox"
              checked={onlyInUse}
              onChange={(event) => setOnlyInUse(event.target.checked)}
            />
            <span aria-hidden="true" />
            In use only
          </label>
        </div>
      </div>

      {query.isLoading ? (
        <div className="fish-directory__state">
          <LoadingState label="Loading fish species…" />
        </div>
      ) : query.isError ? (
        <div className="fish-directory__state">
          <ErrorState message="Fish species could not be loaded." retry={() => query.refetch()} />
        </div>
      ) : visible.length === 0 ? (
        <div className="fdg-empty">
          <FishSymbol size={26} aria-hidden="true" />
          <strong>No matching species</strong>
          <p>Try a broader search or clear one of the active filters.</p>
          <button type="button" onClick={clearFilters}>
            Clear all filters
          </button>
        </div>
      ) : view === 'grouped' ? (
        <>
          <div className="fdg-results-note" aria-live="polite">
            Showing <strong>{visible.length}</strong> species in{' '}
            <strong>{grouped.length}</strong> {grouped.length === 1 ? 'group' : 'groups'}
          </div>
          <div className="fdg-groups">
            {grouped.map(([category, items]) => {
              const isCollapsed = collapsed.has(category);
              const placements = items.reduce((total, item) => total + item.tank_count, 0);
              const groupId = `fish-group-${category.replace(/\W/g, '-').toLowerCase()}`;
              return (
                <article className="fdg-group" key={category}>
                  <button
                    className="fdg-group-header"
                    type="button"
                    onClick={() =>
                      setCollapsed((current) => {
                        const next = new Set(current);
                        next.has(category) ? next.delete(category) : next.add(category);
                        return next;
                      })
                    }
                    aria-expanded={!isCollapsed}
                    aria-controls={groupId}
                  >
                    <span className="fdg-group-icon">
                      <Layers3 size={18} />
                    </span>
                    <span className="fdg-group-title">
                      <strong>{category}</strong>
                      <small>Species with related care requirements</small>
                    </span>
                    <span className="fdg-group-meta">
                      {items.length} species <span aria-hidden="true">·</span> {placements}{' '}
                      tank {placements === 1 ? 'placement' : 'placements'}
                    </span>
                    <ChevronDown className={isCollapsed ? 'is-collapsed' : ''} size={19} />
                  </button>
                  {!isCollapsed && (
                    <div className="fdg-group-body" id={groupId}>
                      <div className="fdg-column-labels" aria-hidden="true">
                        <span>Species</span>
                        <span>Care summary</span>
                        <span>Diet</span>
                        <span>Tank usage</span>
                        <span>Actions</span>
                      </div>
                      {items.map((item) => (
                        <div className="fdg-species-row" key={item.id}>
                          <div className="fdg-species-identity">
                            <SpeciesImage fish={item} />
                            <span>
                              <strong>{item.common_name}</strong>
                              <em>{item.scientific_name}</em>
                            </span>
                          </div>
                          <p className="fdg-description">
                            {item.description || 'No description added yet.'}
                          </p>
                          <DietDetails fish={item} />
                          <Usage fish={item} />
                          <RowActions
                            fish={item}
                            onEdit={startEdit}
                            onDelete={setDeleteTarget}
                          />
                        </div>
                      ))}
                    </div>
                  )}
                </article>
              );
            })}
          </div>
        </>
      ) : (
        <div className="compact-fish__panel fish-directory__compact-panel">
          <div className="compact-fish__table-head" aria-hidden="true">
            <span>Species</span>
            <span>Care summary</span>
            <span>Diet &amp; feeding</span>
            <span>Tank usage</span>
            <span>Actions</span>
          </div>
          {visible.map((item) => (
            <article className="compact-fish__row" key={item.id}>
              <div className="compact-fish__identity">
                <SpeciesImage fish={item} compact />
                <div>
                  <strong>{item.common_name}</strong>
                  <small>{item.scientific_name}</small>
                  <span className="compact-fish__mobile-category">{item.category}</span>
                </div>
              </div>
              <p className="compact-fish__description">
                {item.description || 'No description added yet.'}
              </p>
              <DietDetails fish={item} compact />
              <Usage fish={item} compact />
              <RowActions
                fish={item}
                compact
                onEdit={startEdit}
                onDelete={setDeleteTarget}
              />
            </article>
          ))}
          <footer className="compact-fish__footer">
            <span>
              Showing <strong>{visible.length}</strong> of {fish.length} species
            </span>
            <span>
              <ShieldCheck size={14} />
              Assigned species are protected from deletion
            </span>
          </footer>
        </div>
      )}

      <Drawer
        open={Boolean(editing)}
        title={`${editing?.id ? 'Edit' : 'Add'} fish species`}
        description="Maintain the species profile used by staff and customer tank pages."
        onClose={() => setEditing(null)}
        footer={
          <div className="drawer-actions">
            <button className="button button-secondary" type="button" onClick={() => setEditing(null)}>
              Cancel
            </button>
            <button className="button button-primary" type="submit" form="fish-species-form">
              {busy ? 'Saving…' : 'Save fish species'}
            </button>
          </div>
        }
      >
        <form id="fish-species-form" className="drawer-form" onSubmit={submit}>
          {error && <Notice tone="error">{error}</Notice>}
          <div className="form-section">
            <h3>Identity and grouping</h3>
            <label className="field">
              <span>Common name</span>
              <input
                name="common_name"
                defaultValue={editing?.common_name ?? ''}
                required
              />
            </label>
            <label className="field">
              <span>Scientific name</span>
              <input
                name="scientific_name"
                defaultValue={editing?.scientific_name ?? ''}
                required
              />
            </label>
            <div className="form-grid">
              <label className="field">
                <span>Care group</span>
                <input
                  name="category"
                  list="fish-category-options"
                  defaultValue={editing?.category ?? 'Other'}
                  required
                />
                <datalist id="fish-category-options">
                  {categorySuggestions.map((category) => (
                    <option value={category} key={category} />
                  ))}
                </datalist>
              </label>
              <label className="field">
                <span>Diet type</span>
                <select name="diet_type" defaultValue={editing?.diet_type ?? ''}>
                  <option value="">Not set</option>
                  <option value="Carnivore">Carnivore</option>
                  <option value="Omnivore">Omnivore</option>
                  <option value="Herbivore">Herbivore</option>
                </select>
              </label>
            </div>
            <label className="field">
              <span>Photo URL</span>
              <input name="photo_url" type="url" defaultValue={editing?.photo_url ?? ''} />
            </label>
          </div>
          <div className="form-section">
            <h3>Care information</h3>
            <label className="field">
              <span>Description</span>
              <textarea name="description" defaultValue={editing?.description ?? ''} rows={3} />
            </label>
            <label className="field">
              <span>Feeding details</span>
              <textarea name="diet" defaultValue={editing?.diet ?? ''} rows={3} />
            </label>
            <label className="field">
              <span>Compatibility notes</span>
              <textarea
                name="compatibility_notes"
                defaultValue={editing?.compatibility_notes ?? ''}
                rows={3}
              />
            </label>
            <label className="field">
              <span>Care tips</span>
              <textarea name="care_tips" defaultValue={editing?.care_tips ?? ''} rows={3} />
            </label>
          </div>
        </form>
      </Drawer>

      <ConfirmDialog
        open={Boolean(deleteTarget)}
        title={`Delete ${deleteTarget?.common_name ?? 'fish species'}?`}
        message="This permanently removes the species profile. Assigned species must be removed from every tank first."
        confirmLabel="Delete fish species"
        busy={busy}
        onConfirm={remove}
        onClose={() => setDeleteTarget(null)}
      />
    </section>
  );
}

export default Fish;
