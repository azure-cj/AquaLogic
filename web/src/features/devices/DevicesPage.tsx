import { api } from '@/shared/api/client';
import type { DeviceKeyRotation, RegisteredDevice } from '@/shared/api/models';
import {
  ConfirmDialog,
  EmptyState,
  ErrorState,
  LoadingState,
  Notice,
  PageHeader,
  Panel,
  SearchField,
} from '@/shared/components/admin-ui';
import { useMe } from '@/shared/hooks/useMe';
import { formatDate, relativeTime } from '@/shared/utils/formatting';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Check, Copy, KeyRound, Power, RefreshCw, Router, ShieldAlert } from 'lucide-react';
import { useMemo, useState } from 'react';
import { Navigate } from 'react-router-dom';
import './styles.css';

type LifecycleTarget = { device: RegisteredDevice; nextActive: boolean };

const statusLabels: Record<RegisteredDevice['status'], string> = {
  online: 'Online',
  offline: 'Offline',
  disabled: 'Disabled',
};

function DeviceStatus({ status }: { status: RegisteredDevice['status']; }) {
  return (
    <span className={`device-status device-status-${status}`}>
      <span className="status-dot" aria-hidden="true" />
      {statusLabels[status]}
    </span>
  );
}

export function DevicesPage() {
  const me = useMe();
  const queryClient = useQueryClient();
  const isAdmin = me.data?.role === 'admin';
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | RegisteredDevice['status']>('all');
  const [lifecycleTarget, setLifecycleTarget] = useState<LifecycleTarget | null>(null);
  const [rotateTarget, setRotateTarget] = useState<RegisteredDevice | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [rotation, setRotation] = useState<DeviceKeyRotation | null>(null);
  const [copied, setCopied] = useState(false);

  const devices = useQuery({
    queryKey: ['devices'],
    queryFn: () => api<RegisteredDevice[]>('/devices'),
    enabled: isAdmin,
  });

  const visibleDevices = useMemo(() => {
    const normalized = search.trim().toLowerCase();
    return (devices.data ?? []).filter((device) => {
      const matchesSearch = !normalized
        || device.device_id.toLowerCase().includes(normalized)
        || device.tank_name.toLowerCase().includes(normalized)
        || String(device.tank_id).includes(normalized);
      return matchesSearch && (statusFilter === 'all' || device.status === statusFilter);
    });
  }, [devices.data, search, statusFilter]);

  if (me.isLoading) {
    return <section className="devices-page"><LoadingState label="Checking administrator access…" /></section>;
  }

  if (me.isError) return <Navigate to="/admin/login" replace />;

  if (!isAdmin) {
    return (
      <section className="devices-page">
        <PageHeader
          eyebrow="Configure"
          title="Device management"
          description="Registered bridge devices are managed by administrators only."
        />
        <Notice tone="warning">Administrator access required</Notice>
      </section>
    );
  }

  const updateLifecycle = async () => {
    if (!lifecycleTarget) return;
    setBusy(true);
    setNotice(null);
    try {
      await api<RegisteredDevice>(`/devices/${lifecycleTarget.device.device_id}`, {
        method: 'PATCH',
        body: JSON.stringify({ is_active: lifecycleTarget.nextActive }),
      });
      await queryClient.invalidateQueries({ queryKey: ['devices'] });
      setNotice(`${lifecycleTarget.device.device_id} is now ${lifecycleTarget.nextActive ? 'active' : 'disabled'}.`);
      setLifecycleTarget(null);
    } catch {
      setNotice('The device state could not be changed. Try again.');
    } finally {
      setBusy(false);
    }
  };

  const rotateKey = async () => {
    if (!rotateTarget) return;
    setBusy(true);
    setNotice(null);
    try {
      const result = await api<DeviceKeyRotation>(`/devices/${rotateTarget.device_id}/rotate-key`, { method: 'POST' });
      setRotation(result);
      setCopied(false);
      await queryClient.invalidateQueries({ queryKey: ['devices'] });
      setRotateTarget(null);
    } catch {
      setNotice('The device key could not be rotated. Try again.');
    } finally {
      setBusy(false);
    }
  };

  const copyKey = async () => {
    if (!rotation) return;
    try {
      await navigator.clipboard.writeText(rotation.device_key);
      setCopied(true);
    } catch {
      setCopied(false);
      setNotice('Copy was unavailable. Select the key and copy it manually.');
    }
  };

  return (
    <section className="devices-page">
      <PageHeader
        eyebrow="Configure"
        title="Device management"
        description="Review registered bridge devices, their tank mappings, and reporting health."
      />

      {notice && <Notice tone="warning">{notice}</Notice>}

      <div className="devices-scope-note" role="note">
        <ShieldAlert size={18} aria-hidden="true" />
        <span><strong>Fixed device mapping</strong><small>Device keys authenticate one bridge to one tank. Keys are shown only after rotation.</small></span>
      </div>

      <Panel
        className="devices-panel"
        title="Registered devices"
        description={`${visibleDevices.length} of ${devices.data?.length ?? 0} devices shown`}
        action={<div className="devices-panel-actions"><SearchField value={search} onChange={setSearch} placeholder="Search device or tank…" /><label className="devices-status-filter"><span className="sr-only">Filter by status</span><select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value as typeof statusFilter)}><option value="all">All statuses</option><option value="online">Online</option><option value="offline">Offline</option><option value="disabled">Disabled</option></select></label></div>}
      >
        {devices.isLoading ? (
          <LoadingState label="Loading registered devices…" />
        ) : devices.isError ? (
          <ErrorState message="Registered devices could not be loaded." retry={() => devices.refetch()} />
        ) : visibleDevices.length ? (
          <div className="device-table-wrap">
            <table className="device-table">
              <thead><tr><th>Device</th><th>Tank mapping</th><th>Status</th><th>Last seen</th><th>Created</th><th><span className="sr-only">Actions</span></th></tr></thead>
              <tbody>
                {visibleDevices.map((device) => (
                  <tr key={device.device_id}>
                    <td><div className="device-identity"><span className="device-icon" aria-hidden="true"><Router size={17} /></span><span><strong>{device.device_id}</strong><small>Registered bridge</small></span></div></td>
                    <td><strong>{device.tank_name}</strong><small>Tank {device.tank_id}</small></td>
                    <td><DeviceStatus status={device.status} /></td>
                    <td><strong>{device.last_seen_at ? relativeTime(device.last_seen_at) : 'Never'}</strong><small>{device.last_seen_at ? formatDate(device.last_seen_at) : 'No bridge report yet'}</small></td>
                    <td><small>{formatDate(device.created_at)}</small></td>
                    <td><div className="device-actions"><button className="button button-secondary button-small" type="button" onClick={() => setLifecycleTarget({ device, nextActive: !device.is_active })}><Power size={14} />{device.is_active ? 'Disable' : 'Activate'}</button><button className="button button-secondary button-small" type="button" onClick={() => setRotateTarget(device)}><KeyRound size={14} />Rotate key</button></div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <EmptyState title={devices.data?.length ? 'No matching devices' : 'No registered devices'} message={devices.data?.length ? 'Try another device, tank, or status filter.' : 'Provision a bridge device through the administrator API to see it here.'} />
        )}
      </Panel>

      <ConfirmDialog
        open={Boolean(lifecycleTarget)}
        title={lifecycleTarget?.nextActive ? 'Activate this device?' : 'Disable this device?'}
        message={lifecycleTarget ? `${lifecycleTarget.device.device_id} will ${lifecycleTarget.nextActive ? 'be allowed to authenticate again' : 'immediately stop ingesting readings and using device-key actuator routes'}.` : ''}
        confirmLabel={lifecycleTarget?.nextActive ? 'Activate device' : 'Disable device'}
        onConfirm={() => void updateLifecycle()}
        onClose={() => setLifecycleTarget(null)}
        busy={busy}
        tone={lifecycleTarget?.nextActive ? 'primary' : 'danger'}
      />

      <ConfirmDialog
        open={Boolean(rotateTarget)}
        title="Rotate device key?"
        message={rotateTarget ? `The current key for ${rotateTarget.device_id} will stop working immediately. The replacement key will be shown once.` : ''}
        confirmLabel="Rotate key"
        onConfirm={() => void rotateKey()}
        onClose={() => setRotateTarget(null)}
        busy={busy}
        tone="danger"
      />

      {rotation && (
        <div className="device-key-modal modal-layer" role="dialog" aria-modal="true" aria-labelledby="device-key-title">
          <button className="modal-backdrop" type="button" aria-label="Close key display" onClick={() => setRotation(null)} />
          <section className="device-key-card">
            <span className="device-key-icon" aria-hidden="true"><KeyRound size={22} /></span>
            <h2 id="device-key-title">New device key</h2>
            <p>Copy this key into the bridge now. It cannot be recovered after this window is closed.</p>
            <code>{rotation.device_key}</code>
            <button className="button button-primary" type="button" onClick={() => void copyKey()}>{copied ? <Check size={16} /> : <Copy size={16} />}{copied ? 'Copied' : 'Copy key'}</button>
            <button className="text-link" type="button" onClick={() => setRotation(null)}>I have saved the key</button>
          </section>
        </div>
      )}
    </section>
  );
}

export default DevicesPage;
