import { api } from '@/shared/api/client';
import type { Customer, Fish, FleetTank, Tank } from '@/shared/api/models';
import {
  ConfirmDialog,
  Drawer,
  EmptyState,
  ErrorState,
  LoadingState,
  Notice,
  PageHeader,
  Panel,
  SearchField,
  StatusBadge
} from '@/shared/components/admin-ui';
import { Brand } from '@/shared/components/Brand';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Copy,
  CheckCircle2,
  Download,
  Droplets,
  ExternalLink,
  FishSymbol,
  Pencil,
  Plus,
  Printer,
  QrCode,
  Trash2,
  X
} from 'lucide-react';
import QRCode from 'qrcode';
import {
  FormEvent,
  ReactNode,
  useCallback,
  useEffect,
  useState
} from 'react';
import {
  Link,
  useNavigate,
  useParams,
  useSearchParams
} from 'react-router-dom';
import './styles.css';

function ActionTooltip({ label, children }: { label: string; children: ReactNode }) {
  const [dismissed, setDismissed] = useState(false);
  return (
    <span
      className={`action-tooltip${dismissed ? ' is-dismissed' : ''}`}
      data-tooltip={label}
      onClick={() => setDismissed(true)}
      onBlur={() => setDismissed(false)}
      onMouseEnter={() => setDismissed(false)}
    >
      {children}
    </span>
  );
}

function TankForm({
  initial,
  customers,
  onDone,
}: {
  initial?: Tank;
  customers: Customer[];
  onDone: () => void;
}) {
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    const form = new FormData(event.currentTarget);
    const customer = form.get('customer_id');
    const volume = form.get('volume_liters');
    const body = {
      name: form.get('name'),
      location: form.get('location'),
      description: form.get('description') || null,
      is_public: form.get('is_public') === 'on',
      customer_id: customer ? Number(customer) : null,
      feeding_schedule: form.get('feeding_schedule') || null,
      public_care_notes: form.get('public_care_notes') || null,
      tank_code: form.get('tank_code') || null,
      habitat_label: form.get('habitat_label') || null,
      water_type: form.get('water_type') || null,
      volume_liters: volume ? Number(volume) : null,
      established_on: form.get('established_on') || null,
      hero_image_url: form.get('hero_image_url') || null,
    };
    try {
      await api(initial ? `/tanks/${initial.id}` : '/tanks', {
        method: initial ? 'PUT' : 'POST',
        body: JSON.stringify(body),
      });
      onDone();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Could not save tank');
    } finally {
      setBusy(false);
    }
  };
  return (
    <form className="drawer-form" id="tank-form" onSubmit={submit}>
      {error && <Notice tone="error">{error}</Notice>}
      <div className="form-section">
        <h3>Tank identity</h3>
        <div className="form-grid">
          <label className="field">
            <span>Tank name</span>
            <input name="name" defaultValue={initial?.name} required />
          </label>
          <label className="field">
            <span>Location</span>
            <input name="location" defaultValue={initial?.location} required />
          </label>
        </div>
        <label className="field">
          <span>Customer</span>
          <select name="customer_id" defaultValue={initial?.customer_id ?? ''}>
            <option value="">Unassigned</option>
            {customers.map((customer) => (
              <option key={customer.id} value={customer.id}>
                {customer.name}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>Description</span>
          <textarea name="description" defaultValue={initial?.description ?? ''} rows={3} />
        </label>
      </div>
      <div className="form-section">
        <h3>Customer page</h3>
        <div className="form-grid">
          <label className="field">
            <span>Public tank code</span>
            <input
              name="tank_code"
              defaultValue={initial?.tank_code ?? ''}
              placeholder="TANK-01"
              maxLength={32}
            />
          </label>
          <label className="field">
            <span>Habitat label</span>
            <input
              name="habitat_label"
              defaultValue={initial?.habitat_label ?? ''}
              placeholder="Tropical community"
              maxLength={80}
            />
          </label>
          <label className="field">
            <span>Water type</span>
            <select name="water_type" defaultValue={initial?.water_type ?? ''}>
              <option value="">Not specified</option>
              <option value="freshwater">Freshwater</option>
              <option value="saltwater">Saltwater</option>
              <option value="brackish">Brackish</option>
            </select>
          </label>
          <label className="field">
            <span>Volume (liters)</span>
            <input
              name="volume_liters"
              type="number"
              min="1"
              step="1"
              defaultValue={initial?.volume_liters ?? ''}
            />
          </label>
          <label className="field">
            <span>Established on</span>
            <input
              name="established_on"
              type="date"
              defaultValue={initial?.established_on ?? ''}
            />
          </label>
          <label className="field">
            <span>Hero image URL</span>
            <input
              name="hero_image_url"
              type="url"
              defaultValue={initial?.hero_image_url ?? ''}
              placeholder="https://…"
            />
          </label>
        </div>
        <label className="field">
          <span>Feeding schedule</span>
          <input name="feeding_schedule" defaultValue={initial?.feeding_schedule ?? ''} />
        </label>
        <label className="field">
          <span>Public care notes</span>
          <textarea
            name="public_care_notes"
            defaultValue={initial?.public_care_notes ?? ''}
            rows={4}
          />
        </label>
        <label className="toggle-field">
          <input type="checkbox" name="is_public" defaultChecked={initial?.is_public ?? true} />
          <span aria-hidden="true" />
          <strong>Public customer page</strong>
        </label>
      </div>
      <button className="sr-only" disabled={busy}>
        Save tank
      </button>
      {busy && <p className="form-progress">Saving tank…</p>}
    </form>
  );
}

function QrModal({
  value,
  onClose,
}: {
  value: { data: string; tank: Tank; } | null;
  onClose: () => void;
}) {
  if (!value) return null;
  return (
    <div className="modal-layer modal-centered qr-modal">
      <button className="modal-backdrop" type="button" onClick={onClose} aria-label="Close QR code" />
      <section className="qr-dialog" role="dialog" aria-modal="true" aria-labelledby="qr-title">
        <button className="icon-button qr-close" type="button" onClick={onClose} aria-label="Close">
          <X size={20} />
        </button>
        <div className="print-label">
          <Brand compact />
          <p>Scan to view live tank information</p>
          <img src={value.data} alt={`QR code for ${value.tank.name}`} />
          <h2 id="qr-title">{value.tank.name}</h2>
          <span>{value.tank.location}</span>
        </div>
        <div className="dialog-actions no-print">
          <button className="button button-secondary" type="button" onClick={() => window.print()}>
            <Printer size={16} /> Print label
          </button>
          <a
            className="button button-primary"
            href={value.data}
            download={`${value.tank.name}-qr.png`}
          >
            <Download size={16} /> Download QR
          </a>
        </div>
      </section>
    </div>
  );
}

export function Tanks() {
  const client = useQueryClient();
  const params = useParams();
  const [searchParams] = useSearchParams();
  const nav = useNavigate();
  const [creating, setCreating] = useState(false);
  const [search, setSearch] = useState('');
  const [qrPreview, setQrPreview] = useState<{ data: string; tank: Tank; } | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<Tank | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  useEffect(() => {
    if (!notice) return;
    const timeout = window.setTimeout(() => setNotice(''), 3600);
    return () => window.clearTimeout(timeout);
  }, [notice]);
  const tanks = useQuery({ queryKey: ['tanks'], queryFn: () => api<Tank[]>('/tanks') });
  const fleet = useQuery({ queryKey: ['fleet'], queryFn: () => api<FleetTank[]>('/fleet') });
  const customers = useQuery({
    queryKey: ['customers'],
    queryFn: () => api<Customer[]>('/customers'),
  });
  const fish = useQuery({ queryKey: ['fish'], queryFn: () => api<Fish[]>('/fish') });
  const chosen = tanks.data?.find((tank) => String(tank.id) === params.tankId);
  const detail = useQuery({
    queryKey: ['tank', chosen?.id],
    queryFn: () => api<Tank>(`/tanks/${chosen!.id}`),
    enabled: Boolean(chosen),
  });
  const selectedFish = detail.data?.fish_species ?? [];
  const visible = (tanks.data ?? []).filter((tank) =>
    [tank.name, tank.location].some((value) => value.toLowerCase().includes(search.toLowerCase())),
  );
  const highlightedTankId = Number(searchParams.get('tank_id'));
  const closeDrawer = useCallback(() => {
    setCreating(false);
    nav('/admin/tanks');
  }, [nav]);
  const publicUrl = (tank: Tank) => `${location.origin}/tank/${tank.public_id}`;
  const showQr = async (tank: Tank) => {
    setQrPreview({ data: await QRCode.toDataURL(publicUrl(tank)), tank });
  };
  const copyUrl = async (tank: Tank) => {
    await navigator.clipboard.writeText(publicUrl(tank));
    setNotice(`Public URL copied for ${tank.name}.`);
  };
  const assignFish = async (fishId: number) => {
    if (!chosen) return;
    await api(`/tanks/${chosen.id}/fish`, {
      method: 'POST',
      body: JSON.stringify({ fish_species_id: fishId }),
    });
    client.invalidateQueries({ queryKey: ['tank', chosen.id] });
  };
  const removeFish = async (fishId: number) => {
    if (!chosen) return;
    await api(`/tanks/${chosen.id}/fish/${fishId}`, { method: 'DELETE' });
    client.invalidateQueries({ queryKey: ['tank', chosen.id] });
  };
  const removeTank = async () => {
    if (!deleteTarget) return;
    setBusy(true);
    try {
      await api(`/tanks/${deleteTarget.id}`, { method: 'DELETE' });
      setNotice(`${deleteTarget.name} was deleted.`);
      setDeleteTarget(null);
      client.invalidateQueries({ queryKey: ['tanks'] });
      client.invalidateQueries({ queryKey: ['fleet'] });
      closeDrawer();
    } finally {
      setBusy(false);
    }
  };
  const saved = () => {
    setNotice(`Tank ${chosen ? 'updated' : 'created'} successfully.`);
    client.invalidateQueries({ queryKey: ['tanks'] });
    client.invalidateQueries({ queryKey: ['fleet'] });
    if (chosen) client.invalidateQueries({ queryKey: ['tank', chosen.id] });
    closeDrawer();
  };

  return (
    <section>
      <PageHeader
        eyebrow="Fleet management"
        title="Tanks"
        description="Manage installations, customer access, assigned fish, and QR labels."
        actions={
          <button className="button button-primary" type="button" onClick={() => setCreating(true)}>
            <Plus size={17} /> Add tank
          </button>
        }
      />
      {notice && (
        <div className="tanks-toast" role="status" aria-live="polite">
          <CheckCircle2 size={18} aria-hidden="true" />
          <span>{notice}</span>
          <button type="button" onClick={() => setNotice('')} aria-label="Dismiss notification">
            <X size={16} aria-hidden="true" />
          </button>
        </div>
      )}
      <Panel
        title="Registered tanks"
        description={`${visible.length} of ${tanks.data?.length ?? 0} tanks`}
        action={
          <SearchField value={search} onChange={setSearch} placeholder="Search tanks…" />
        }
      >
        {tanks.isLoading ? (
          <LoadingState label="Loading tanks…" />
        ) : tanks.isError ? (
          <ErrorState message="Tanks could not be loaded." retry={() => tanks.refetch()} />
        ) : visible.length ? (
          <div className="data-table management-table tanks-table">
            <div className="data-head">
              <span>Tank</span>
              <span>Customer</span>
              <span>Health</span>
              <span>Public page</span>
              <span>Actions</span>
            </div>
            {visible.map((tank) => {
              const health = fleet.data?.find((item) => item.id === tank.id);
              return (
                <div
                  className={`data-row${tank.id === highlightedTankId ? ' analytics-target-row' : ''}`}
                  key={tank.id}
                >
                  <span className="tank-cell">
                    <span className="tank-mark" aria-hidden="true">
                      <Droplets size={16} />
                    </span>
                    <span>
                      <strong>{tank.name}</strong>
                      <small>{tank.location}</small>
                    </span>
                  </span>
                  <span>
                    {customers.data?.find((customer) => customer.id === tank.customer_id)?.name ??
                      'Unassigned'}
                  </span>
                  {health ? <StatusBadge value={health.status} /> : <span className="muted">—</span>}
                  <span>
                    <StatusBadge value={tank.is_public ? 'normal' : 'offline'} />
                    <small>{tank.is_public ? 'Published' : 'Private'}</small>
                  </span>
                  <span className="row-actions">
                    <ActionTooltip label="Edit tank">
                      <Link
                        className="icon-button"
                        to={`/admin/tanks/${tank.id}`}
                        aria-label={`Edit ${tank.name}`}
                      >
                        <Pencil size={16} />
                      </Link>
                    </ActionTooltip>
                    <ActionTooltip label="Show QR code">
                      <button
                        className="icon-button"
                        type="button"
                        onClick={() => showQr(tank)}
                        aria-label={`Show QR code for ${tank.name}`}
                      >
                        <QrCode size={16} />
                      </button>
                    </ActionTooltip>
                    <ActionTooltip label="Copy public URL">
                      <button
                        className="icon-button"
                        type="button"
                        onClick={() => copyUrl(tank)}
                        aria-label={`Copy public URL for ${tank.name}`}
                      >
                        <Copy size={16} />
                      </button>
                    </ActionTooltip>
                    <ActionTooltip label="Preview public page">
                      <Link
                        className="icon-button"
                        to={`/tank/${tank.public_id}`}
                        target="_blank"
                        aria-label={`Preview ${tank.name} public page`}
                      >
                        <ExternalLink size={16} />
                      </Link>
                    </ActionTooltip>
                    <ActionTooltip label="Delete tank">
                      <button
                        className="icon-button icon-danger"
                        type="button"
                        onClick={() => setDeleteTarget(tank)}
                        aria-label={`Delete ${tank.name}`}
                      >
                        <Trash2 size={16} />
                      </button>
                    </ActionTooltip>
                  </span>
                </div>
              );
            })}
          </div>
        ) : (
          <EmptyState title="No tanks found" message="Try another search or add a tank." />
        )}
      </Panel>
      <Drawer
        open={creating || Boolean(chosen)}
        title={chosen ? `Edit ${chosen.name}` : 'Add tank'}
        description={
          chosen
            ? 'Update tank details, customer access, and assigned fish.'
            : 'Register a new tank in the AquaLogic fleet.'
        }
        onClose={closeDrawer}
        footer={
          <div className="drawer-actions">
            {chosen && (
              <button
                className="button button-danger button-quiet-danger"
                type="button"
                onClick={() => setDeleteTarget(chosen)}
              >
                <Trash2 size={16} /> Delete
              </button>
            )}
            <button className="button button-secondary" type="button" onClick={closeDrawer}>
              Cancel
            </button>
            <button
              className="button button-primary"
              type="submit"
              form="tank-form"
            >
              Save tank
            </button>
          </div>
        }
      >
        <TankForm initial={chosen} customers={customers.data ?? []} onDone={saved} />
        {chosen && (
          <div className="form-section assignment-section">
            <h3>Assigned fish</h3>
            <label className="field">
              <span>Add species</span>
              <select
                defaultValue=""
                onChange={(event) => {
                  if (event.target.value) {
                    assignFish(Number(event.target.value));
                    event.currentTarget.value = '';
                  }
                }}
              >
                <option value="">Choose a species</option>
                {fish.data
                  ?.filter((item) => !selectedFish.some((selected) => selected.id === item.id))
                  .map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.common_name}
                    </option>
                  ))}
              </select>
            </label>
            <div className="assignment-list">
              {detail.isLoading ? (
                <LoadingState label="Loading assigned fish…" />
              ) : selectedFish.length ? (
                selectedFish.map((item) => (
                  <div key={item.id}>
                    <span className="resource-avatar">
                      {item.photo_url ? (
                        <img src={item.photo_url} alt="" />
                      ) : (
                        <FishSymbol size={18} aria-hidden="true" />
                      )}
                    </span>
                    <span>
                      <strong>{item.common_name}</strong>
                      <small>{item.scientific_name}</small>
                    </span>
                    <button
                      className="icon-button icon-danger"
                      type="button"
                      onClick={() => removeFish(item.id)}
                      aria-label={`Remove ${item.common_name}`}
                    >
                      <X size={16} />
                    </button>
                  </div>
                ))
              ) : (
                <p className="muted">No fish species assigned yet.</p>
              )}
            </div>
          </div>
        )}
      </Drawer>
      <QrModal value={qrPreview} onClose={() => setQrPreview(null)} />
      <ConfirmDialog
        open={Boolean(deleteTarget)}
        title={`Delete ${deleteTarget?.name ?? 'tank'}?`}
        message="This permanently removes the tank and cannot be undone."
        confirmLabel="Delete tank"
        busy={busy}
        onConfirm={removeTank}
        onClose={() => setDeleteTarget(null)}
      />
    </section>
  );
}

export default Tanks;
