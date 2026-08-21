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
  Eye,
  ExternalLink,
  FishSymbol,
  ImagePlus,
  Layers3,
  List,
  Pencil,
  Plus,
  Search,
  ShieldCheck,
  SlidersHorizontal,
  Trash2,
  Upload,
  X,
} from 'lucide-react';
import { FormEvent, useEffect, useMemo, useRef, useState } from 'react';
import { useMe } from '@/shared/hooks/useMe';

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

type UsageFilter = 'All usage' | 'In use' | 'Not assigned';

function formatRange(min: number | null | undefined, max: number | null | undefined, unit: string) {
  if (min == null && max == null) return 'Not configured';
  const value = (number: number) => Number.isInteger(number) ? String(number) : number.toFixed(1);
  if (min != null && max != null) return `${value(min)}–${value(max)} ${unit}`.trim();
  if (min != null) return `At least ${value(min)} ${unit}`.trim();
  return `At most ${value(max as number)} ${unit}`.trim();
}

function careProfileState(fish: FishRecord) {
  const configured = [
    fish.ideal_temp_min != null || fish.ideal_temp_max != null,
    fish.ideal_ph_min != null || fish.ideal_ph_max != null,
    fish.ideal_tds_min != null || fish.ideal_tds_max != null,
  ].filter(Boolean).length;
  return configured === 3 ? 'Complete care profile' : configured ? 'Partially configured' : 'Care ranges not configured';
}

const viewStorageKey = 'aqualogic:fish-species-view';
const MAX_FISH_IMAGE_BYTES = 5 * 1024 * 1024;
const FISH_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
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
  onView,
  onDelete,
  canManage,
}: {
  fish: FishRecord;
  compact?: boolean;
  onEdit: (fish: FishRecord) => void;
  onView: (fish: FishRecord) => void;
  onDelete: (fish: FishRecord) => void;
  canManage: boolean;
}) {
  const inUse = fish.tank_count > 0;
  const className = compact ? 'compact-fish__actions' : 'fdg-actions';
  return (
    <div className={className}>
      <button
        type="button"
        onClick={() => onView(fish)}
        aria-label={`View details for ${fish.common_name}`}
        title={`View details for ${fish.common_name}`}
      >
        <Eye size={16} />
      </button>
      {canManage && <>
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
      </>}
    </div>
  );
}

export function Fish() {
  const queryClient = useQueryClient();
  const me = useMe();
  const canManage = me.data?.role !== 'staff';
  const query = useQuery({
    queryKey: ['/fish'],
    queryFn: () => api<FishRecord[]>('/fish'),
  });
  const [view, setView] = useState<ViewMode>(initialView);
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('All care groups');
  const [diet, setDiet] = useState<'All diets' | DietType>('All diets');
  const [usage, setUsage] = useState<UsageFilter>('All usage');
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const [editing, setEditing] = useState<Partial<FishRecord> | null>(null);
  const [viewing, setViewing] = useState<FishRecord | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<FishRecord | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [photoUrl, setPhotoUrl] = useState('');
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState('');
  const photoInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!photoFile) {
      setPhotoPreview(photoUrl);
      return;
    }
    const objectUrl = URL.createObjectURL(photoFile);
    setPhotoPreview(objectUrl);
    return () => URL.revokeObjectURL(objectUrl);
  }, [photoFile, photoUrl]);

  const fish = query.data ?? [];
  const categories = useMemo(
    () => [...new Set(fish.map((item) => item.category || 'Other'))].sort((left, right) => left.localeCompare(right)),
    [fish],
  );
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
      const matchesCategory = category === 'All care groups' || item.category === category;
      const matchesUsage = usage === 'All usage'
        || (usage === 'In use' ? item.tank_count > 0 : item.tank_count === 0);
      return matchesSearch && matchesCategory && matchesDiet && matchesUsage;
    });
  }, [category, diet, fish, search, usage]);

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
    setPhotoUrl(item.photo_url ?? '');
    setPhotoFile(null);
    setPhotoPreview(item.photo_url ?? '');
    if (photoInputRef.current) photoInputRef.current.value = '';
  };

  const startCreate = () => {
    setError('');
    setEditing({ category: 'Other' });
    setPhotoUrl('');
    setPhotoFile(null);
    setPhotoPreview('');
    if (photoInputRef.current) photoInputRef.current.value = '';
  };

  const selectPhotoFile = (file: File | undefined) => {
    if (!file) return;
    if (!FISH_IMAGE_TYPES.includes(file.type)) {
      setError('Choose a JPG, PNG, or WebP image.');
      return;
    }
    if (file.size > MAX_FISH_IMAGE_BYTES) {
      setError('Fish photos must be 5 MB or smaller.');
      return;
    }
    setError('');
    setPhotoUrl('');
    setPhotoFile(file);
  };

  const usePhotoUrl = (value: string) => {
    setPhotoUrl(value);
    if (photoFile) {
      setPhotoFile(null);
      if (photoInputRef.current) photoInputRef.current.value = '';
    }
  };

  const clearPhoto = () => {
    setPhotoFile(null);
    setPhotoUrl('');
    setPhotoPreview('');
    if (photoInputRef.current) photoInputRef.current.value = '';
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
        'ideal_temp_min',
        'ideal_temp_max',
        'ideal_ph_min',
        'ideal_ph_max',
        'ideal_tds_min',
        'ideal_tds_max',
        'diet_type',
        'photo_url',
        'description',
        'diet',
        'compatibility_notes',
        'care_tips',
      ].map((key) => [key, key === 'photo_url' && photoFile ? editing?.photo_url ?? null : form.get(key) || null]),
    );
    try {
      const saved = await api<ApiFish>(editing?.id ? `/fish/${editing.id}` : '/fish', {
        method: editing?.id ? 'PUT' : 'POST',
        body: JSON.stringify(body),
      });
      if (photoFile && saved.id) {
        const upload = new FormData();
        upload.append('image', photoFile);
        try {
          await api(`/fish/${saved.id}/photo-image`, { method: 'POST', body: upload });
        } catch (caught) {
          setError(caught instanceof Error
            ? `Species saved, but the photo could not be uploaded: ${caught.message}`
            : 'Species saved, but the photo could not be uploaded.');
          return;
        }
      }
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
    setCategory('All care groups');
    setDiet('All diets');
    setUsage('All usage');
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
           {canManage && <button
             className="fdg-primary-button"
             type="button"
             onClick={startCreate}
          >
            <Plus size={17} />
            Add fish species
          </button>}
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
            value={category}
            onChange={(event) => setCategory(event.target.value)}
            aria-label="Filter by care group"
          >
            <option>All care groups</option>
            {categories.map((item) => <option key={item}>{item}</option>)}
          </select>
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
          <select
            value={usage}
            onChange={(event) => setUsage(event.target.value as UsageFilter)}
            aria-label="Filter by tank usage"
          >
            <option>All usage</option>
            <option>In use</option>
            <option>Not assigned</option>
          </select>
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
                            onView={setViewing}
                            onDelete={setDeleteTarget}
                            canManage={canManage}
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
                onView={setViewing}
                onDelete={setDeleteTarget}
                canManage={canManage}
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
        open={Boolean(viewing)}
        title={viewing?.common_name ?? 'Species details'}
        description={viewing?.scientific_name ?? 'Read-only care profile'}
        onClose={() => setViewing(null)}
        footer={
          <div className="drawer-actions">
            <button className="button button-secondary" type="button" onClick={() => setViewing(null)}>
              Close
            </button>
            {canManage && viewing && (
              <button
                 className="button button-primary"
                 type="button"
                 onClick={() => {
                   startEdit(viewing);
                   setViewing(null);
                 }}
              >
                Edit profile
              </button>
            )}
          </div>
        }
      >
        {viewing && (
          <div className="fish-details">
            <div className="fish-details__identity">
              <SpeciesImage fish={viewing} />
              <div>
                <span className="fish-details__category">{viewing.category}</span>
                <h3>{viewing.common_name}</h3>
                <em>{viewing.scientific_name}</em>
              </div>
            </div>
            <div className="fish-details__status-row">
              <span className="fish-details__profile-status">{careProfileState(viewing)}</span>
              <span className="fish-details__usage-status">
                {viewing.tank_count ? `${viewing.tank_count} assigned ${viewing.tank_count === 1 ? 'tank' : 'tanks'}` : 'Not assigned to a tank'}
              </span>
            </div>

            <section className="fish-details__section">
              <h3>Preferred water conditions</h3>
              <p className="fish-details__helper">Used for care guidance against the tank’s latest supported readings.</p>
              <div className="fish-details__ranges">
                <div><span>Temperature</span><strong>{formatRange(viewing.ideal_temp_min, viewing.ideal_temp_max, '°C')}</strong></div>
                <div><span>pH</span><strong>{formatRange(viewing.ideal_ph_min, viewing.ideal_ph_max, '')}</strong></div>
                <div><span>TDS</span><strong>{formatRange(viewing.ideal_tds_min, viewing.ideal_tds_max, 'ppm')}</strong></div>
              </div>
            </section>

            <section className="fish-details__section">
              <h3>Diet and care</h3>
              <div className="fish-details__copy-grid">
                <div><span>Diet type</span><strong>{viewing.diet_type ?? 'Not set'}</strong></div>
                <div><span>Feeding details</span><p>{viewing.diet || 'No feeding details added.'}</p></div>
                <div><span>Compatibility</span><p>{viewing.compatibility_notes || 'No compatibility notes added.'}</p></div>
                <div><span>Care tips</span><p>{viewing.care_tips || 'No care tips added.'}</p></div>
              </div>
            </section>

            <section className="fish-details__section">
              <h3>Assigned tanks</h3>
              {viewing.assigned_tanks?.length ? (
                <ul className="fish-details__tank-list">
                  {viewing.assigned_tanks.map((tank) => (
                    <li key={tank.id}>
                      <a href={`/admin/tanks/${tank.id}`}>
                        {tank.name}
                        <ExternalLink size={13} aria-hidden="true" />
                      </a>
                    </li>
                  ))}
                </ul>
              ) : viewing.tank_count ? (
                <p className="fish-details__helper">This species is assigned, but tank names are not available in the current response.</p>
              ) : (
                <p className="fish-details__helper">Assign this species from a tank workspace to begin care checks.</p>
              )}
            </section>
          </div>
        )}
      </Drawer>

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
          </div>
          <div className="form-section fish-photo-section">
              <div>
                <h3>Species photo</h3>
                <p className="form-section__copy">Use a hosted image URL or upload a JPG, PNG, or WebP image for this species.</p>
              </div>
              <label className="field">
                <span>Image URL <small>Optional</small></span>
                <input
                  name="photo_url"
                  type="url"
                  value={photoUrl}
                  onChange={(event) => usePhotoUrl(event.target.value)}
                  placeholder="https://images.example.com/fish.jpg"
                  maxLength={500}
                  disabled={Boolean(photoFile)}
                  aria-describedby="fish-photo-help"
                />
              </label>
              <label className="field">
                <span>Upload image <small>JPG, PNG, or WebP · max 5 MB</small></span>
                <span className="fish-file-input-wrap">
                  <Upload size={16} aria-hidden="true" />
                  <input
                    ref={photoInputRef}
                    type="file"
                    accept="image/jpeg,image/png,image/webp"
                    aria-label="Upload fish photo"
                    data-testid="fish-photo-upload"
                    onChange={(event) => selectPhotoFile(event.target.files?.[0])}
                    disabled={!editing?.id || busy}
                  />
                </span>
                <small id="fish-photo-help" className="field-help">
                  {editing?.id ? 'Uploading replaces the current species photo after you save.' : 'Save the species first, then edit it to upload an image.'}
                </small>
              </label>
              {photoPreview ? (
                <div className="fish-photo-preview-wrap">
                  <img className="fish-photo-preview" src={photoPreview} alt="Species photo preview" onError={() => setPhotoPreview('')} />
                  <button className="button button-secondary fish-photo-clear" type="button" onClick={clearPhoto} disabled={busy}>
                    <Trash2 size={15} /> Remove image
                  </button>
                </div>
              ) : (
                <div className="fish-photo-empty" role="status">
                  <ImagePlus size={20} aria-hidden="true" />
                  <span>No species photo selected</span>
                </div>
              )}
          </div>
          <div className="form-section">
            <h3>Preferred water conditions</h3>
            <p className="form-section__copy">
              These ranges support species-care guidance and are separate from operational tank alert thresholds.
            </p>
            <div className="fish-range-grid">
              <label className="field">
                <span>Temperature minimum (°C)</span>
                <input name="ideal_temp_min" type="number" min="0" max="50" step="0.1" defaultValue={editing?.ideal_temp_min ?? ''} placeholder="e.g. 24" />
              </label>
              <label className="field">
                <span>Temperature maximum (°C)</span>
                <input name="ideal_temp_max" type="number" min="0" max="50" step="0.1" defaultValue={editing?.ideal_temp_max ?? ''} placeholder="e.g. 28" />
              </label>
              <label className="field">
                <span>pH minimum</span>
                <input name="ideal_ph_min" type="number" min="0" max="14" step="0.1" defaultValue={editing?.ideal_ph_min ?? ''} placeholder="e.g. 6.5" />
              </label>
              <label className="field">
                <span>pH maximum</span>
                <input name="ideal_ph_max" type="number" min="0" max="14" step="0.1" defaultValue={editing?.ideal_ph_max ?? ''} placeholder="e.g. 7.5" />
              </label>
              <label className="field">
                <span>TDS minimum (ppm)</span>
                <input name="ideal_tds_min" type="number" min="0" step="1" defaultValue={editing?.ideal_tds_min ?? ''} placeholder="e.g. 100" />
              </label>
              <label className="field">
                <span>TDS maximum (ppm)</span>
                <input name="ideal_tds_max" type="number" min="0" step="1" defaultValue={editing?.ideal_tds_max ?? ''} placeholder="e.g. 300" />
              </label>
            </div>
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
