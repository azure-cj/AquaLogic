import { api } from '@/shared/api/client';
import type { FleetTank, Tank } from '@/shared/api/models';
import {
  EmptyState,
  ErrorState,
  LoadingState,
  PageHeader,
  Panel,
  SearchField,
  StatusBadge,
  TankLifecycleBadge,
} from '@/shared/components/admin-ui';
import { Brand } from '@/shared/components/Brand';
import { Dialog, DialogClose, DialogContent, DialogOverlay, DialogPortal, DialogTitle } from '@/shared/components/ui/dialog';
import { IconTooltip, TooltipProvider } from '@/shared/components/ui/tooltip';
import { notify } from '@/shared/lib/notify';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Copy,
  Download,
  Droplets,
  ExternalLink,
  Archive,
  Pencil,
  Plus,
  Printer,
  QrCode,
  X,
} from 'lucide-react';
import QRCode from 'qrcode';
import { type RefObject, useCallback, useRef, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { TankEditorDrawer } from './TankEditorDrawer';
import { TankRetireDialog } from './TankRetireDialog';
import { useMe } from '@/shared/hooks/useMe';
import './styles.css';

function QrModal({
  value,
  onClose,
  returnFocus,
}: {
  value: { data: string; tank: Tank } | null;
  onClose: () => void;
  returnFocus: RefObject<HTMLElement | null>;
}) {
  return (
    <Dialog open={Boolean(value)} onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogPortal>
        <div className="modal-layer modal-centered qr-modal">
          <DialogOverlay />
          {value && <DialogContent className="qr-dialog" onCloseAutoFocus={(event) => { event.preventDefault(); returnFocus.current?.focus(); }}>
        <DialogClose
          className="icon-button qr-close"
          type="button"
          aria-label="Close"
        >
          <X size={20} />
        </DialogClose>
        <div className="print-label">
          <Brand compact />
          <p>Scan to view live tank information</p>
          <img src={value.data} alt={`QR code for ${value.tank.name}`} />
          <DialogTitle>{value.tank.name}</DialogTitle>
          <span>{value.tank.location}</span>
        </div>
        <div className="dialog-actions no-print">
          <button
            className="button button-secondary"
            type="button"
            onClick={() => window.print()}
          >
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
          </DialogContent>}
        </div>
      </DialogPortal>
    </Dialog>
  );
}

export function Tanks() {
  const client = useQueryClient();
  const me = useMe();
  const canManage = me.data?.role !== 'staff';
  const [searchParams, setSearchParams] = useSearchParams();
  const nav = useNavigate();
  const [creating, setCreating] = useState(false);
  const [search, setSearch] = useState('');
  const [qrPreview, setQrPreview] = useState<{
    data: string;
    tank: Tank;
  } | null>(null);
  const qrTriggerRef = useRef<HTMLElement | null>(null);
  const [retireTarget, setRetireTarget] = useState<Tank | null>(null);
  const [retireBusy, setRetireBusy] = useState(false);
  const lifecycle = searchParams.get('lifecycle') === 'retired' || searchParams.get('lifecycle') === 'all'
    ? searchParams.get('lifecycle') as 'retired' | 'all'
    : 'active';

  const tanks = useQuery({
    queryKey: ['tanks', lifecycle],
    queryFn: () => api<Tank[]>(`/tanks?lifecycle=${lifecycle}`),
  });
  const fleet = useQuery({
    queryKey: ['fleet'],
    queryFn: () => api<FleetTank[]>('/fleet'),
  });
  const editTankId = Number(searchParams.get('edit'));
  const chosen = canManage ? tanks.data?.find((tank) => tank.id === editTankId) : undefined;
  const visible = (tanks.data ?? []).filter((tank) =>
    [tank.name, tank.location].some((value) =>
      value.toLowerCase().includes(search.toLowerCase()),
    ),
  );
  const highlightedTankId = Number(searchParams.get('tank_id'));

  const closeDrawer = useCallback(() => {
    setCreating(false);
    nav('/admin/tanks');
  }, [nav]);
  const publicUrl = (tank: Tank) => `${location.origin}/tank/${tank.public_id}`;
  const showQr = async (tank: Tank, trigger: HTMLElement) => {
    qrTriggerRef.current = trigger;
    setQrPreview({ data: await QRCode.toDataURL(publicUrl(tank)), tank });
  };
  const copyUrl = async (tank: Tank) => {
    await navigator.clipboard.writeText(publicUrl(tank));
    notify.success(`Public URL copied for ${tank.name}.`);
  };
  const retireTank = async (note: string | null) => {
    if (!retireTarget) return;
    setRetireBusy(true);
    try {
      await api(`/tanks/${retireTarget.id}/retire`, {
        method: 'POST',
        body: JSON.stringify({ note }),
      });
      notify.success(`${retireTarget.name} was retired. History is retained.`);
      setRetireTarget(null);
      client.invalidateQueries({ queryKey: ['tanks'] });
      client.invalidateQueries({ queryKey: ['fleet'] });
    } catch (error) {
      notify.error(error instanceof Error ? error.message : 'The tank could not be retired.');
    } finally {
      setRetireBusy(false);
    }
  };
  const saved = () => {
    notify.success(`Tank ${chosen ? 'updated' : 'created'} successfully.`);
    client.invalidateQueries({ queryKey: ['tanks'] });
    client.invalidateQueries({ queryKey: ['fleet'] });
    if (chosen) client.invalidateQueries({ queryKey: ['tank', chosen.id] });
    closeDrawer();
  };

  return (
    <TooltipProvider delayDuration={500}>
    <section>
      <PageHeader
        eyebrow="Fleet management"
        title="Tanks"
        description="Manage tanks, public visibility, configuration, and QR labels."
        actions={canManage ? (
          <button
            className="button button-primary"
            type="button"
            onClick={() => setCreating(true)}
          >
            <Plus size={17} /> Add tank
          </button>
        ) : undefined}
      />
      <Panel
        title="Registered tanks"
        description={`${visible.length} of ${tanks.data?.length ?? 0} ${lifecycle} tanks`}
        action={
          <div className="tanks-directory-tools">
            <label className="field tanks-lifecycle-filter">
              <span className="sr-only">Tank lifecycle</span>
              <select
                aria-label="Tank lifecycle"
                value={lifecycle}
                onChange={(event) => {
                  const next = new URLSearchParams(searchParams);
                  if (event.target.value === 'active') next.delete('lifecycle');
                  else next.set('lifecycle', event.target.value);
                  setSearchParams(next);
                }}
              >
                <option value="active">Active tanks</option>
                <option value="retired">Retired tanks</option>
                <option value="all">All tanks</option>
              </select>
            </label>
            <SearchField value={search} onChange={setSearch} placeholder="Search tanks…" />
          </div>
        }
      >
        {tanks.isLoading ? (
          <LoadingState label="Loading tanks…" />
        ) : tanks.isError ? (
          <ErrorState
            message="Tanks could not be loaded."
            retry={() => tanks.refetch()}
          />
        ) : visible.length ? (
          <div className="data-table management-table tanks-table">
            <div className="data-head">
              <span>Tank</span>
              <span>Health</span>
              <span>Public page</span>
              <span>Actions</span>
            </div>
            {visible.map((tank) => {
              const health = fleet.data?.find((item) => item.id === tank.id);
              return (
                <div
                  className={`data-row${tank.id === highlightedTankId ? ' analytics-target-row' : ''}${tank.lifecycle === 'retired' ? ' is-retired' : ''}`}
                  key={tank.id}
                >
                  <span className="tank-cell">
                    <span className="tank-mark" aria-hidden="true">
                      <Droplets size={16} />
                    </span>
                    <span>
                      <Link to={`/admin/tanks/${tank.id}`}>{tank.name}</Link>
                      <small>{tank.location}</small>
                    </span>
                  </span>
                  {tank.lifecycle === 'retired' ? (
                    <TankLifecycleBadge lifecycle="retired" />
                  ) : health ? (
                    <StatusBadge value={health.status} />
                  ) : (
                    <span className="muted">—</span>
                  )}
                  <span className={`publication-state ${tank.is_public ? 'is-public' : 'is-private'}`}>
                    <strong>{tank.is_public ? 'Public' : 'Private'}</strong>
                    <small>{tank.is_public ? 'Published page' : 'Not public'}</small>
                  </span>
                  <span className="row-actions">
                    {canManage && tank.lifecycle === 'active' && <IconTooltip label="Edit tank">
                      <Link
                        className="icon-button"
                        to={`/admin/tanks?edit=${tank.id}`}
                        aria-label={`Edit ${tank.name}`}
                      >
                        <Pencil size={16} />
                      </Link>
                    </IconTooltip>}
                    {tank.lifecycle === 'active' && <IconTooltip label="Show QR code">
                      <button
                        className="icon-button"
                        type="button"
                        onClick={(event) => showQr(tank, event.currentTarget)}
                        aria-label={`Show QR code for ${tank.name}`}
                      >
                        <QrCode size={16} />
                      </button>
                    </IconTooltip>}
                    {tank.lifecycle === 'active' && <IconTooltip label="Copy public URL">
                      <button
                        className="icon-button"
                        type="button"
                        onClick={() => copyUrl(tank)}
                        aria-label={`Copy public URL for ${tank.name}`}
                      >
                        <Copy size={16} />
                      </button>
                    </IconTooltip>}
                    {tank.lifecycle === 'active' && <IconTooltip label="Preview public page">
                      <Link
                        className="icon-button"
                        to={`/tank/${tank.public_id}`}
                        target="_blank"
                        rel="noreferrer"
                        aria-label={`Preview ${tank.name} public page`}
                      >
                        <ExternalLink size={16} />
                      </Link>
                    </IconTooltip>}
                    {canManage && tank.lifecycle === 'active' && <IconTooltip label="Retire tank">
                      <button
                        className="icon-button icon-danger"
                        type="button"
                        onClick={() => setRetireTarget(tank)}
                        aria-label={`Retire ${tank.name}`}
                      >
                        <Archive size={16} />
                      </button>
                    </IconTooltip>}
                  </span>
                </div>
              );
            })}
          </div>
        ) : (
          <EmptyState
            title="No tanks found"
            message="Try another search or add a tank."
          />
        )}
      </Panel>
      {canManage && <TankEditorDrawer
        open={creating || Boolean(chosen)}
        tank={chosen}
        onClose={closeDrawer}
        onSaved={saved}
      />}
      <QrModal value={qrPreview} onClose={() => setQrPreview(null)} returnFocus={qrTriggerRef} />
      {canManage && <TankRetireDialog
        tankName={retireTarget?.name ?? 'tank'}
        open={Boolean(retireTarget)}
        busy={retireBusy}
        onConfirm={retireTank}
        onClose={() => setRetireTarget(null)}
      />}
    </section>
    </TooltipProvider>
  );
}

export default Tanks;
