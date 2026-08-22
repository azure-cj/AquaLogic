import { ApiError, api } from '@/shared/api/client';
import type {
  Alert,
  Fish,
  SpeciesSuitabilityResponse,
  Tank,
  TankOperations,
} from '@/shared/api/models';
import {
  ConfirmDialog,
  EmptyState,
  ErrorState,
  LoadingState,
  Notice,
  PageHeader,
  Panel,
  StatusBadge,
} from '@/shared/components/admin-ui';
import {
  formatDate,
  formatReading,
  formatReportingAge,
  reportingAgeSeconds,
} from '@/shared/utils/formatting';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  AlertTriangle,
  ArrowLeft,
  Copy,
  ExternalLink,
  FishSymbol,
  Pencil,
  QrCode,
  Trash2,
  Archive,
  X,
} from 'lucide-react';
import QRCode from 'qrcode';
import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { CareStatusChip, SpeciesCarePanel } from './SpeciesCarePanel';
import { ActuatorControlPanel, StaffActuatorNotice } from './ActuatorControlPanel';
import { TankEditorDrawer } from './TankEditorDrawer';
import { TankRetireDialog } from './TankRetireDialog';
import { MonitoringIncidentTankPanel } from '@/features/monitoring/MonitoringIncidentViews';
import { publicTankUrl } from './publicLink';
import { useMe } from '@/shared/hooks/useMe';
import './styles.css';

const measurements = [
  ['temperature', 'Temperature', '°C', 1],
  ['ph', 'pH', '', 1],
  ['turbidity', 'Turbidity', 'NTU', 1],
  ['tds', 'TDS', 'ppm', 0],
] as const;

function currentReleaseOperationalStatus(operations: TankOperations): TankOperations['status'] {
  if (operations.status === 'retired') return 'retired';
  if (operations.status === 'offline') return 'offline';
  const statuses = measurements.map(([key]) => operations.parameter_statuses[key]);
  if (statuses.includes('critical')) return 'critical';
  if (statuses.includes('warning')) return 'warning';
  return 'normal';
}

const errorMessage = (error: unknown, fallback: string) =>
  error instanceof Error ? error.message : fallback;

export function TankDetail() {
  const { tankId } = useParams();
  const id = Number(tankId);
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const client = useQueryClient();
  const me = useMe();
  const canManage = me.data?.role !== 'staff';
  const isAdmin = me.data?.role === 'admin';
  const [assigning, setAssigning] = useState(false);
  const [assignBusy, setAssignBusy] = useState(false);
  const [removing, setRemoving] = useState<Fish | null>(null);
  const [removeBusy, setRemoveBusy] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [retireOpen, setRetireOpen] = useState(false);
  const [retireBusy, setRetireBusy] = useState(false);
  const [resolvingId, setResolvingId] = useState<number | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [heroFailed, setHeroFailed] = useState(false);
  const [actionError, setActionError] = useState('');
  const [actionNotice, setActionNotice] = useState('');
  const editing = canManage && params.get('edit') === '1';
  const validId = Number.isInteger(id) && id > 0;

  const tank = useQuery({
    queryKey: ['tank', id],
    queryFn: () => api<Tank>(`/tanks/${id}`),
    enabled: validId,
  });
  const operations = useQuery({
    queryKey: ['tank-operations', id],
    queryFn: () => api<TankOperations>(`/tanks/${id}/operations`),
    enabled: tank.isSuccess,
    refetchInterval: tank.data?.lifecycle === 'active' ? 30_000 : false,
  });
  const suitability = useQuery({
    queryKey: ['species-suitability', id],
    queryFn: () =>
      api<SpeciesSuitabilityResponse>(`/tanks/${id}/species-suitability`),
    enabled: tank.isSuccess && tank.data?.lifecycle === 'active',
    refetchInterval: 30_000,
  });
  const historicalAlerts = useQuery({
    queryKey: ['tank-alert-history', id],
    queryFn: () => api<Alert[]>(`/tanks/${id}/alerts?include_resolved=true`),
    enabled: tank.isSuccess && tank.data?.lifecycle === 'retired',
  });
  const fish = useQuery({
    queryKey: ['fish'],
    queryFn: () => api<Fish[]>('/fish'),
    enabled: assigning,
  });

  useEffect(() => {
    setHeroFailed(false);
  }, [tank.data?.hero_image_url]);

  const closeEditor = () => navigate(`/admin/tanks/${id}`);
  const clearFeedback = () => {
    setActionError('');
    setActionNotice('');
  };
  const invalidateAssignment = () => {
    client.invalidateQueries({ queryKey: ['tank', id] });
    client.invalidateQueries({ queryKey: ['species-suitability', id] });
    client.invalidateQueries({ queryKey: ['fleet'] });
    client.invalidateQueries({ queryKey: ['fish'] });
  };

  const assign = async (fishId: number) => {
    clearFeedback();
    setAssignBusy(true);
    try {
      await api(`/tanks/${id}/fish`, {
        method: 'POST',
        body: JSON.stringify({ fish_species_id: fishId }),
      });
      invalidateAssignment();
      setAssigning(false);
      setActionNotice('Species assigned to this tank.');
    } catch (error) {
      setActionError(errorMessage(error, 'Could not assign the species.'));
    } finally {
      setAssignBusy(false);
    }
  };

  const remove = async () => {
    if (!removing) return;
    clearFeedback();
    setRemoveBusy(true);
    try {
      await api(`/tanks/${id}/fish/${removing.id}`, { method: 'DELETE' });
      setRemoving(null);
      invalidateAssignment();
      setActionNotice('Species removed from this tank.');
    } catch (error) {
      setActionError(errorMessage(error, 'Could not remove the species.'));
    } finally {
      setRemoveBusy(false);
    }
  };

  const resolve = async (alertId: number) => {
    clearFeedback();
    setResolvingId(alertId);
    try {
      await api(`/alerts/${alertId}/resolve`, { method: 'PUT' });
      client.invalidateQueries({ queryKey: ['tank-operations', id] });
      client.invalidateQueries({ queryKey: ['alerts'] });
      client.invalidateQueries({ queryKey: ['fleet'] });
      setActionNotice('Operational alert marked as handled.');
    } catch (error) {
      setActionError(errorMessage(error, 'Could not mark the alert handled.'));
    } finally {
      setResolvingId(null);
    }
  };

  const removeTank = async () => {
    if (!tank.data) return;
    clearFeedback();
    setDeleteBusy(true);
    try {
      await api(`/tanks/${id}`, { method: 'DELETE' });
      client.invalidateQueries({ queryKey: ['tanks'] });
      client.invalidateQueries({ queryKey: ['fleet'] });
      navigate('/admin/tanks');
    } catch (error) {
      setActionError(errorMessage(error, 'Could not delete the tank.'));
      setDeleteOpen(false);
    } finally {
      setDeleteBusy(false);
    }
  };

  const retireTank = async (note: string | null) => {
    clearFeedback();
    setRetireBusy(true);
    try {
      const retired = await api<Tank>(`/tanks/${id}/retire`, {
        method: 'POST',
        body: JSON.stringify({ note }),
      });
      client.setQueryData(['tank', id], retired);
      client.invalidateQueries({ queryKey: ['tanks'] });
      client.invalidateQueries({ queryKey: ['fleet'] });
      setRetireOpen(false);
      setActionNotice('Tank retired. History is retained and live controls are disabled.');
    } catch (error) {
      setActionError(errorMessage(error, 'Could not retire the tank.'));
    } finally {
      setRetireBusy(false);
    }
  };

  if (!validId) {
    return (
      <EmptyState
        title="Tank not found"
        message="The tank identifier is invalid."
      />
    );
  }
  if (tank.isLoading) return <LoadingState label="Loading tank workspace…" />;
  if (tank.isError) {
    const missing = tank.error instanceof ApiError && tank.error.status === 404;
    return (
      <ErrorState
        message={
          missing
            ? 'This tank was not found and may have been deleted.'
            : 'Tank workspace could not be loaded.'
        }
        retry={missing ? undefined : () => tank.refetch()}
      />
    );
  }

  const value = tank.data!;
  const isRetired = value.lifecycle === 'retired';
  const reading = operations.data?.latest_reading;
  const assigned = value.fish_species ?? [];
  const care = suitability.data;
  const operationalStatus = operations.data ? currentReleaseOperationalStatus(operations.data) : null;
  const reportingAge = reportingAgeSeconds(reading?.received_at);
  const isLastKnown = operationalStatus === 'offline' && Boolean(reading);
  const visibleActiveAlerts = operations.data?.active_alerts.filter((alert) =>
    measurements.some(([key]) => key === alert.parameter),
  ) ?? [];
  const publicActions = value.is_public ? (
    <>
      <a
        className="button button-secondary"
        href={publicTankUrl(value)}
        target="_blank"
        rel="noreferrer"
      >
        <ExternalLink size={16} /> Public page
      </a>
      <button
        className="button button-secondary"
        type="button"
        onClick={async () => {
          clearFeedback();
          try {
            await navigator.clipboard.writeText(publicTankUrl(value));
            setActionNotice('Public link copied.');
          } catch {
            setActionError('The public link could not be copied.');
          }
        }}
      >
        <Copy size={16} /> Copy link
      </button>
      <button
        className="button button-secondary"
        type="button"
        onClick={async () => setQr(await QRCode.toDataURL(publicTankUrl(value)))}
      >
        <QrCode size={16} /> QR
      </button>
    </>
  ) : isRetired ? (
    <span className="private-state">Retired — public page disabled</span>
  ) : (
    <span className="private-state">Private — public link disabled</span>
  );

  return (
    <section className="tank-detail">
      <Link className="back-link" to="/admin/tanks">
        <ArrowLeft size={16} /> Back to tanks
      </Link>
      <PageHeader
        eyebrow="Tank workspace"
        title={value.name}
        description={`${value.location}${value.tank_code ? ` · ${value.tank_code}` : ''}${value.water_type ? ` · ${value.water_type}` : ''}${value.volume_liters ? ` · ${value.volume_liters} L` : ''}${value.customer ? ` · ${value.customer.name}` : ''}`}
        actions={
          <div className="tank-detail-actions">
            {canManage && value.lifecycle === 'active' && <>
            <button
              className="button button-primary"
              type="button"
              onClick={() => navigate(`/admin/tanks/${id}?edit=1`)}
            >
              <Pencil size={16} /> Edit
            </button>
            {publicActions}
            <button
              className="button button-danger button-quiet-danger"
              type="button"
              onClick={() => setRetireOpen(true)}
            >
              <Archive size={16} /> Retire
            </button>
            </>}
            {canManage && value.lifecycle === 'retired' && <>
            <StatusBadge value="retired" />
            <button
              className="button button-danger button-quiet-danger"
              type="button"
              onClick={() => setDeleteOpen(true)}
            >
              <Trash2 size={16} /> Permanently delete
            </button>
            </>}
          </div>
        }
      />

      {actionError && <Notice tone="error">{actionError}</Notice>}
      {actionNotice && <Notice>{actionNotice}</Notice>}

      <div className="tank-summary-grid">
        <div className="tank-summary-card">
          <small>{isRetired ? 'Lifecycle state' : 'Operational water status'}</small>
          {operations.isLoading ? (
            <span>Loading…</span>
          ) : operations.isError ? (
            <strong>Unavailable</strong>
          ) : (
            <StatusBadge value={isRetired ? 'retired' : operationalStatus!} />
          )}
        </div>
        <div className="tank-summary-card">
          <small>{isRetired ? 'Species Care history' : 'Species Care status'}</small>
          {isRetired ? (
            <strong>Retained historical assignment</strong>
          ) : suitability.isLoading ? (
            <span>Loading…</span>
          ) : suitability.isError || !care ? (
            <strong>Unavailable</strong>
          ) : (
            <CareStatusChip status={care.status} />
          )}
        </div>
        <div className="tank-summary-card">
          <small>{isRetired ? 'Retained alerts' : 'Active operational alerts'}</small>
          <strong>
            {isRetired
              ? (historicalAlerts.data?.length ?? '—')
              : operations.isLoading || operations.isError ? '—' : visibleActiveAlerts.length}
          </strong>
        </div>
        <div className="tank-summary-card">
          <small>{isRetired ? 'Last known reading' : isLastKnown ? 'Last known reading' : 'Latest reading'}</small>
          <strong>
            {operations.isError
              ? 'Unavailable'
              : formatReportingAge(reportingAge, { offline: operationalStatus === 'offline' })}
          </strong>
        </div>
        <div className="tank-summary-card">
          <small>Assigned species</small>
          <strong>{assigned.length}</strong>
        </div>
      </div>

      <p className="tank-status-explanation">
        {isRetired ? (
          <><strong>Retired</strong> is a historical, read-only state. The last reading, assignments, alerts, configuration, media, and equipment history remain available; no new operational data or controls are accepted.</>
        ) : (
          <><strong>Operational status</strong> uses global monitoring thresholds.{' '}
          <strong>Species Care</strong> compares current supported readings with assigned-species preferences.</>
        )}
      </p>

      <div className="tank-primary-grid">
        <Panel
          title={isRetired ? 'Species Care history' : 'Live care evaluation'}
          description={isRetired ? 'Retained assignment records; no new evaluation is run' : 'Live suitability by assigned species'}
          className="tank-care-panel"
        >
          {isRetired ? <Notice>Retired tanks do not participate in live Species Care evaluation.</Notice> : <SpeciesCarePanel
            result={care}
            loading={suitability.isLoading}
            error={suitability.isError}
            retry={() => suitability.refetch()}
          />}
        </Panel>
        <div className="tank-operations-column">
          <Panel
            title={isRetired || isLastKnown ? 'Last known readings' : 'Current readings'}
            description={
                reading
                 ? `Observed ${formatDate(reading.timestamp)} · ${formatReportingAge(reportingAge, { offline: operationalStatus === 'offline' })}`
                : 'No sensor reading is available'
            }
            className="tank-readings-panel"
          >
            {operations.isLoading ? (
              <LoadingState label="Loading readings…" />
            ) : operations.isError ? (
              <ErrorState
                message="Readings could not be loaded."
                retry={() => operations.refetch()}
              />
            ) : !reading ? (
              <EmptyState
                title="No reading yet"
                message="Operational status will update after the first sensor report."
              />
            ) : (
              <div className="reading-grid">
                {measurements.map(([key, label, unit, decimals]) => (
                  <div className="reading-item" key={key}>
                    <small>{isLastKnown && reading[key] !== null ? `Last known ${label === 'pH' ? 'pH' : label.toLowerCase()}` : label}</small>
                    <strong>{reading[key] === null ? 'Not installed' : formatReading(reading[key], unit, decimals)}</strong>
                    <StatusBadge value={operations.data!.parameter_statuses[key]} />
                  </div>
                ))}
              </div>
            )}
          </Panel>
          <Panel
            title="Operational alerts"
            description={isRetired ? 'Historical alert records retained with this retired tank.' : 'Persisted unresolved alerts only. Mark handled removes an alert from the active queue but does not confirm water recovery.'}
            className="tank-alerts-panel"
            action={
              <Link
                className="text-link"
                to={`/admin/alerts?tank_id=${id}&resolved=false`}
              >
                View history
              </Link>
            }
          >
            {isRetired && historicalAlerts.isLoading ? (
              <LoadingState label="Loading alert history…" />
            ) : isRetired && historicalAlerts.isError ? (
              <ErrorState
                message="Alert history could not be loaded."
                retry={() => historicalAlerts.refetch()}
              />
            ) : !isRetired && operations.isLoading ? (
              <LoadingState label="Loading operational alerts…" />
            ) : !isRetired && operations.isError ? (
              <ErrorState
                message="Operational alerts could not be loaded."
                retry={() => operations.refetch()}
              />
            ) : (isRetired ? historicalAlerts.data ?? [] : visibleActiveAlerts).length ? (
              <div className="alert-feed">
                {(isRetired ? historicalAlerts.data ?? [] : visibleActiveAlerts).map((alert) => (
                  <div className="alert-feed-item" key={alert.id}>
                    <span
                      className={`alert-symbol alert-${alert.severity}`}
                      aria-hidden="true"
                    >
                      <AlertTriangle size={16} />
                    </span>
                    <span>
                      <strong>{alert.parameter.replaceAll('_', ' ')}</strong>
                      <small>{alert.message}</small>
                    </span>
                    {isRetired ? (
                      <span className="muted">{alert.is_resolved ? 'Handled' : 'Unresolved at retirement'}</span>
                    ) : (
                      <button
                        className="button button-secondary"
                        type="button"
                        disabled={resolvingId === alert.id}
                        onClick={() => resolve(alert.id)}
                        aria-label={`Mark ${alert.parameter.replaceAll('_', ' ')} alert handled; this does not confirm water recovery`}
                      >
                        {resolvingId === alert.id ? 'Marking handled…' : 'Mark handled'}
                      </button>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <EmptyState
                title={isRetired ? 'No retained alerts' : 'No active alerts'}
                message={isRetired ? 'No alert records were stored for this tank.' : 'Species Care observations are intentionally separate.'}
              />
            )}
          </Panel>
        </div>
      </div>

      <div className="tank-secondary-grid">
        <Panel
          title="Assigned species"
          description={isRetired ? 'Historical livestock assignment retained for this tank' : 'Manage the livestock assigned to this tank'}
          className="tank-assignments-panel"
          action={
            !isRetired ? (
              <button
                className="button button-secondary"
                type="button"
                onClick={() => setAssigning((open) => !open)}
              >
                Add species
              </button>
            ) : undefined
          }
        >
          {assigning &&
            (fish.isLoading ? (
              <LoadingState label="Loading species…" />
            ) : fish.isError ? (
              <ErrorState
                message="Species could not be loaded."
                retry={() => fish.refetch()}
              />
            ) : (
              <label className="field assignment-picker">
                <span>Choose a species</span>
                <select
                  defaultValue=""
                  disabled={assignBusy}
                  onChange={(event) => {
                    if (event.target.value) assign(Number(event.target.value));
                  }}
                >
                  <option value="">
                    {assignBusy ? 'Assigning…' : 'Choose a species'}
                  </option>
                  {fish.data
                    ?.filter(
                      (item) =>
                        !assigned.some((selected) => selected.id === item.id),
                    )
                    .map((item) => (
                      <option value={item.id} key={item.id}>
                        {item.common_name}
                      </option>
                    ))}
                </select>
              </label>
            ))}
          {assigned.length ? (
            <div className="assignment-list">
              {assigned.map((item) => {
                const speciesStatus = care?.species.find(
                  (entry) => entry.fish_species_id === item.id,
                )?.status;
                return (
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
                    {speciesStatus ? (
                      <CareStatusChip status={speciesStatus} />
                    ) : (
                      <span className="muted">Care status pending</span>
                    )}
                    {!isRetired && (
                      <button
                        className="icon-button icon-danger"
                        type="button"
                        onClick={() => setRemoving(item)}
                        aria-label={`Remove ${item.common_name}`}
                      >
                        <X size={16} />
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          ) : (
            <EmptyState
              title="No assigned species"
              message="Add a species to begin care checks."
            />
          )}
        </Panel>

        <Panel
          title="Tank information"
          description="Read-only configuration and public page settings"
        >
          <dl className="tank-info-list">
            <div>
              <dt>Description</dt>
              <dd>{value.description ?? 'Not configured'}</dd>
            </div>
            <div>
              <dt>Customer</dt>
              <dd>{value.customer?.name ?? 'Unassigned'}</dd>
            </div>
            <div>
              <dt>Location</dt>
              <dd>{value.location}</dd>
            </div>
            <div>
              <dt>Water type</dt>
              <dd>{value.water_type ?? 'Not specified'}</dd>
            </div>
            <div>
              <dt>Volume</dt>
              <dd>{value.volume_liters ? `${value.volume_liters} L` : 'Not recorded'}</dd>
            </div>
            <div>
              <dt>Tank code</dt>
              <dd>{value.tank_code ?? 'Not configured'}</dd>
            </div>
            <div>
              <dt>Habitat label</dt>
              <dd>{value.habitat_label ?? 'Not configured'}</dd>
            </div>
            <div>
              <dt>Public page</dt>
              <dd>{value.is_public ? 'Published' : 'Private'}</dd>
            </div>
            <div>
              <dt>Established</dt>
              <dd>{value.established_on ?? 'Not recorded'}</dd>
            </div>
            <div>
              <dt>Feeding schedule</dt>
              <dd>{value.feeding_schedule ?? 'Not configured'}</dd>
            </div>
            <div>
              <dt>Public care notes</dt>
              <dd>{value.public_care_notes ?? 'Not configured'}</dd>
            </div>
          </dl>
          {value.hero_image_url &&
            (heroFailed ? (
              <div className="tank-hero-fallback">Image unavailable</div>
            ) : (
              <img
                className="tank-hero-preview"
                src={value.hero_image_url}
                alt=""
                onError={() => setHeroFailed(true)}
              />
            ))}
        </Panel>
      </div>

      <MonitoringIncidentTankPanel tankId={id} />

      {isRetired ? (
        isAdmin ? <ActuatorControlPanel tankId={id} variant="full" readOnly /> : <StaffActuatorNotice />
      ) : isAdmin ? <ActuatorControlPanel tankId={id} variant="summary" /> : <StaffActuatorNotice />}

      <TankEditorDrawer
        open={!isRetired && editing}
        tank={value}
        onClose={closeEditor}
        onSaved={() => {
          client.invalidateQueries({ queryKey: ['tank', id] });
          client.invalidateQueries({ queryKey: ['tanks'] });
          client.invalidateQueries({ queryKey: ['fleet'] });
          closeEditor();
        }}
      />

      {qr && (
        <div className="modal-layer modal-centered">
          <button
            className="modal-backdrop"
            type="button"
            onClick={() => setQr(null)}
            aria-label="Close QR code"
          />
          <section
            className="qr-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="tank-detail-qr-title"
          >
            <h2 id="tank-detail-qr-title">{value.name} public QR code</h2>
            <img src={qr} alt={`QR code for ${value.name}`} />
            <button
              className="button button-secondary"
              type="button"
              onClick={() => setQr(null)}
            >
              Close
            </button>
          </section>
        </div>
      )}
      <ConfirmDialog
        open={Boolean(removing)}
        title={`Remove ${removing?.common_name ?? 'species'}?`}
        message="This removes the species from this tank."
        confirmLabel="Remove species"
        busy={removeBusy}
        onConfirm={remove}
        onClose={() => setRemoving(null)}
      />
      <ConfirmDialog
        open={deleteOpen && isRetired}
        title={`Delete ${value.name}?`}
        message="Permanently delete this tank? Its sensor readings, alerts, equipment command and state history, device registrations, species assignments, uploaded tank image, and public tank page will also be removed. This cannot be undone."
        confirmLabel="Delete tank"
        busy={deleteBusy}
        onConfirm={removeTank}
        onClose={() => setDeleteOpen(false)}
      />
      <TankRetireDialog
        tankName={value.name}
        open={retireOpen}
        busy={retireBusy}
        onConfirm={retireTank}
        onClose={() => setRetireOpen(false)}
      />
    </section>
  );
}

export default TankDetail;
