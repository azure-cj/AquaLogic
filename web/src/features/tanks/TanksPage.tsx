import { api } from '@/shared/api/client';
import type { Customer, FleetTank, Tank } from '@/shared/api/models';
import {
  ConfirmDialog,
  EmptyState,
  ErrorState,
  LoadingState,
  PageHeader,
  Panel,
  SearchField,
  StatusBadge,
} from '@/shared/components/admin-ui';
import { Brand } from '@/shared/components/Brand';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  CheckCircle2,
  Copy,
  Download,
  Droplets,
  ExternalLink,
  Pencil,
  Plus,
  Printer,
  QrCode,
  Trash2,
  X,
} from 'lucide-react';
import QRCode from 'qrcode';
import { ReactNode, useCallback, useEffect, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { TankEditorDrawer } from './TankEditorDrawer';
import './styles.css';

function ActionTooltip({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
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

function QrModal({
  value,
  onClose,
}: {
  value: { data: string; tank: Tank } | null;
  onClose: () => void;
}) {
  if (!value) return null;
  return (
    <div className="modal-layer modal-centered qr-modal">
      <button
        className="modal-backdrop"
        type="button"
        onClick={onClose}
        aria-label="Close QR code"
      />
      <section
        className="qr-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="qr-title"
      >
        <button
          className="icon-button qr-close"
          type="button"
          onClick={onClose}
          aria-label="Close"
        >
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
      </section>
    </div>
  );
}

export function Tanks() {
  const client = useQueryClient();
  const [searchParams] = useSearchParams();
  const nav = useNavigate();
  const [creating, setCreating] = useState(false);
  const [search, setSearch] = useState('');
  const [qrPreview, setQrPreview] = useState<{
    data: string;
    tank: Tank;
  } | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<Tank | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');

  useEffect(() => {
    if (!notice) return;
    const timeout = window.setTimeout(() => setNotice(''), 3600);
    return () => window.clearTimeout(timeout);
  }, [notice]);

  const tanks = useQuery({
    queryKey: ['tanks'],
    queryFn: () => api<Tank[]>('/tanks'),
  });
  const fleet = useQuery({
    queryKey: ['fleet'],
    queryFn: () => api<FleetTank[]>('/fleet'),
  });
  const customers = useQuery({
    queryKey: ['customers'],
    queryFn: () => api<Customer[]>('/customers'),
  });
  const editTankId = Number(searchParams.get('edit'));
  const chosen = tanks.data?.find((tank) => tank.id === editTankId);
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
  const showQr = async (tank: Tank) => {
    setQrPreview({ data: await QRCode.toDataURL(publicUrl(tank)), tank });
  };
  const copyUrl = async (tank: Tank) => {
    await navigator.clipboard.writeText(publicUrl(tank));
    setNotice(`Public URL copied for ${tank.name}.`);
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
        description="Manage installations, customer access, configuration, and QR labels."
        actions={
          <button
            className="button button-primary"
            type="button"
            onClick={() => setCreating(true)}
          >
            <Plus size={17} /> Add tank
          </button>
        }
      />
      {notice && (
        <div className="tanks-toast" role="status" aria-live="polite">
          <CheckCircle2 size={18} aria-hidden="true" />
          <span>{notice}</span>
          <button
            type="button"
            onClick={() => setNotice('')}
            aria-label="Dismiss notification"
          >
            <X size={16} aria-hidden="true" />
          </button>
        </div>
      )}
      <Panel
        title="Registered tanks"
        description={`${visible.length} of ${tanks.data?.length ?? 0} tanks`}
        action={
          <SearchField
            value={search}
            onChange={setSearch}
            placeholder="Search tanks…"
          />
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
                      <Link to={`/admin/tanks/${tank.id}`}>{tank.name}</Link>
                      <small>{tank.location}</small>
                    </span>
                  </span>
                  <span>
                    {customers.data?.find(
                      (customer) => customer.id === tank.customer_id,
                    )?.name ?? 'Unassigned'}
                  </span>
                  {health ? (
                    <StatusBadge value={health.status} />
                  ) : (
                    <span className="muted">—</span>
                  )}
                  <span>
                    <StatusBadge value={tank.is_public ? 'normal' : 'offline'} />
                    <small>{tank.is_public ? 'Published' : 'Private'}</small>
                  </span>
                  <span className="row-actions">
                    <ActionTooltip label="Edit tank">
                      <Link
                        className="icon-button"
                        to={`/admin/tanks?edit=${tank.id}`}
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
                        rel="noreferrer"
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
          <EmptyState
            title="No tanks found"
            message="Try another search or add a tank."
          />
        )}
      </Panel>
      <TankEditorDrawer
        open={creating || Boolean(chosen)}
        tank={chosen}
        customers={customers.data ?? []}
        customersLoading={customers.isLoading}
        customersError={customers.isError}
        onRetryCustomers={() => customers.refetch()}
        onClose={closeDrawer}
        onSaved={saved}
      />
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
