import { metricOptions } from '@/features/analytics/types';
import { tankNameForAlert } from '@/features/fleet/utils';
import { api } from '@/shared/api/client';
import type { Alert, AlertHistoryPage, FleetTank } from '@/shared/api/models';
import {
  EmptyState,
  ErrorState,
  LoadingState,
  PageHeader,
  Panel,
  StatusBadge
} from '@/shared/components/admin-ui';
import { notify } from '@/shared/lib/notify';
import {
  formatDate,
  relativeTime
} from '@/shared/utils/formatting';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Check,
  ChevronLeft,
  ChevronRight,
  X
} from 'lucide-react';
import {
  useEffect,
  useState
} from 'react';
import { useSearchParams } from 'react-router-dom';
import './styles.css';
import { MonitoringIncidentHistory } from '@/features/monitoring/MonitoringIncidentViews';

const ALERTS_PAGE_SIZE = 25;

export function resolutionLabel(source: Alert['resolution_source']): string {
  if (source === 'system') return 'Automatically resolved';
  if (source === 'operator') return 'Handled by operator';
  return 'Resolved';
}

export function Alerts() {
  const client = useQueryClient();
  const [urlParams, setUrlParams] = useSearchParams();
  const inputDate = (value: string | null) => {
    if (!value) return '';
    const date = new Date(value);
    const offset = date.getTimezoneOffset() * 60_000;
    return new Date(date.getTime() - offset).toISOString().slice(0, 16);
  };
  const [severity, setSeverity] = useState(urlParams.get('severity') ?? '');
  const [parameter, setParameter] = useState(urlParams.get('parameter') ?? '');
  const [resolved, setResolved] = useState(urlParams.get('resolved') ?? '');
  const [tankId, setTankId] = useState(urlParams.get('tank_id') ?? '');
  const [after, setAfter] = useState(inputDate(urlParams.get('created_after')));
  const [before, setBefore] = useState(inputDate(urlParams.get('created_before')));
  const [historyMode, setHistoryMode] = useState<'alerts' | 'monitoring'>(urlParams.get('view') === 'monitoring' ? 'monitoring' : 'alerts');
  const initialPage = Number(urlParams.get('page'));
  const [page, setPage] = useState(
    Number.isInteger(initialPage) && initialPage > 0 ? initialPage : 1,
  );
  const filters = new URLSearchParams();
  if (severity) filters.set('severity', severity);
  if (parameter) filters.set('parameter', parameter);
  if (resolved) filters.set('resolved', resolved);
  if (tankId) filters.set('tank_id', tankId);
  if (after) filters.set('created_after', new Date(after).toISOString());
  if (before) filters.set('created_before', new Date(before).toISOString());
  filters.set('page', String(page));
  const query = filters.toString();
  const alertQueryParams = new URLSearchParams(filters);
  metricOptions.forEach((metric) => alertQueryParams.append('parameters', metric.key));
  alertQueryParams.set('page_size', String(ALERTS_PAGE_SIZE));
  const alertQuery = alertQueryParams.toString();
  useEffect(() => {
    if (query !== urlParams.toString()) {
      setUrlParams(filters, { replace: true });
    }
  }, [query, setUrlParams, urlParams]);
  const alerts = useQuery({
    queryKey: ['alerts', alertQuery],
    queryFn: () => api<AlertHistoryPage>(`/alerts/history?${alertQuery}`),
  });
  useEffect(() => {
    if (!alerts.data) return;
    const lastPage = Math.max(alerts.data.total_pages, 1);
    if (page > lastPage) setPage(lastPage);
  }, [alerts.data, page]);
  const fleet = useQuery({ queryKey: ['fleet'], queryFn: () => api<FleetTank[]>('/fleet') });
  const resolve = useMutation({
    mutationFn: (id: number) => api(`/alerts/${id}/resolve`, { method: 'PUT' }),
    onSuccess: () => {
      notify.success('Alert marked as handled.');
      client.invalidateQueries({ queryKey: ['alerts'] });
    },
    onError: () => {
      notify.error('The alert could not be marked as handled.');
    },
  });
  const clear = () => {
    setSeverity('');
    setParameter('');
    setResolved('');
    setTankId('');
    setAfter('');
    setBefore('');
    setPage(1);
  };

  return (
    <section>
      <PageHeader
        eyebrow="Fleet history"
        title="Alert history"
        description="Filter, investigate, and mark water-quality events handled across the fleet."
        actions={
          <button className="button button-secondary" type="button" onClick={clear}>
            <X size={16} /> Clear filters
          </button>
        }
      />
      <div className="monitoring-incident-mode" role="tablist" aria-label="Operational history type">
        <button type="button" className={historyMode === 'alerts' ? 'active' : ''} role="tab" aria-selected={historyMode === 'alerts'} onClick={() => setHistoryMode('alerts')}>Water-quality alerts</button>
        <button type="button" className={historyMode === 'monitoring' ? 'active' : ''} role="tab" aria-selected={historyMode === 'monitoring'} onClick={() => setHistoryMode('monitoring')}>Monitoring outages</button>
      </div>
      {historyMode === 'monitoring' ? (
        <MonitoringIncidentHistory tankId={tankId ? Number(tankId) : undefined} />
      ) : <>
      <Panel className="filter-panel">
        <div className="filter-grid">
          <label className="field">
            <span>Tank</span>
            <select value={tankId} onChange={(event) => {
              setPage(1);
              setTankId(event.target.value);
            }}>
              <option value="">All tanks</option>
              {fleet.data?.map((tank) => (
                <option key={tank.id} value={tank.id}>
                  {tank.name}
                </option>
              ))}
            </select>
          </label>
          <label className="field">
            <span>Severity</span>
            <select value={severity} onChange={(event) => {
              setPage(1);
              setSeverity(event.target.value);
            }}>
              <option value="">All severities</option>
              <option value="warning">Warning</option>
              <option value="critical">Critical</option>
            </select>
          </label>
          <label className="field">
            <span>Parameter</span>
            <select value={parameter} onChange={(event) => {
              setPage(1);
              setParameter(event.target.value);
            }}>
              <option value="">All parameters</option>
              {metricOptions.map((metric) => (
                <option key={metric.key} value={metric.key}>
                  {metric.label}
                </option>
              ))}
            </select>
          </label>
          <label className="field">
            <span>State</span>
            <select value={resolved} onChange={(event) => {
              setPage(1);
              setResolved(event.target.value);
            }}>
              <option value="">All states</option>
              <option value="false">Unresolved</option>
              <option value="true">Resolved</option>
            </select>
          </label>
          <label className="field">
            <span>From</span>
            <input type="datetime-local" value={after} onChange={(event) => {
              setPage(1);
              setAfter(event.target.value);
            }} />
          </label>
          <label className="field">
            <span>To</span>
            <input type="datetime-local" value={before} onChange={(event) => {
              setPage(1);
              setBefore(event.target.value);
            }} />
          </label>
        </div>
      </Panel>
      <Panel
        title="Recorded events"
        description={alerts.data
          ? `${alerts.data.total} alert${alerts.data.total === 1 ? '' : 's'} match the current filters`
          : 'Alerts matching the current filters'}
      >
        <p className="alert-handling-note">
          Mark handled removes an alert from the active queue. It does not confirm that water conditions have recovered; a later abnormal reading may create another alert.
        </p>
        {alerts.isLoading ? (
          <LoadingState label="Loading alert history…" />
        ) : alerts.isError ? (
          <ErrorState message="Alert history could not be loaded." retry={() => alerts.refetch()} />
        ) : alerts.data && page > Math.max(alerts.data.total_pages, 1) ? (
          <LoadingState label="Loading the last available page…" />
        ) : alerts.data?.items.length ? (
          <div className="data-table alerts-table">
            <div className="data-head">
              <span>Event</span>
              <span>Tank</span>
              <span>Severity</span>
              <span>Created</span>
              <span>State</span>
            </div>
            {alerts.data.items.map((alert) => (
              <div className="data-row" key={alert.id}>
                <span>
                  <strong>{alert.parameter.replaceAll('_', ' ')}</strong>
                  <small>{alert.message}</small>
                </span>
                <span>{tankNameForAlert(alert, fleet.data ?? [])}</span>
                <StatusBadge value={alert.severity} />
                <span>
                  <strong>{relativeTime(alert.created_at)}</strong>
                  <small>{formatDate(alert.created_at)}</small>
                </span>
                <span>
                  {alert.is_resolved ? (
                    <>
                      <span className="resolved-label">
                        <Check size={14} /> {resolutionLabel(alert.resolution_source)}
                      </span>
                      <small>{formatDate(alert.resolved_at)}</small>
                    </>
                  ) : (
                    <button
                      className="button button-secondary button-small"
                      type="button"
                      disabled={resolve.isPending && resolve.variables === alert.id}
                      onClick={() => resolve.mutate(alert.id)}
                      aria-label={`Mark ${alert.parameter.replaceAll('_', ' ')} alert handled; this does not confirm water recovery`}
                    >
                      {resolve.isPending && resolve.variables === alert.id
                        ? 'Marking handled…'
                        : 'Mark handled'}
                    </button>
                  )}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <EmptyState title="No alerts found" message="Adjust the filters to broaden the results." />
        )}
        {alerts.data && alerts.data.total > 0 && page <= alerts.data.total_pages && (
          <div className="alert-history-footer">
            <span aria-live="polite">
              Showing {((alerts.data.page - 1) * alerts.data.page_size) + 1}–
              {Math.min(alerts.data.page * alerts.data.page_size, alerts.data.total)} of {alerts.data.total}
            </span>
            <nav className="alert-history-pagination" aria-label="Alert history pagination">
              <button
                className="button button-secondary button-small"
                type="button"
                disabled={!alerts.data.has_previous || alerts.isFetching}
                onClick={() => setPage((current) => Math.max(1, current - 1))}
              >
                <ChevronLeft size={14} /> Previous
              </button>
              <span>Page {alerts.data.page} of {alerts.data.total_pages}</span>
              <button
                className="button button-secondary button-small"
                type="button"
                disabled={!alerts.data.has_next || alerts.isFetching}
                onClick={() => setPage((current) => current + 1)}
              >
                Next <ChevronRight size={14} />
              </button>
            </nav>
          </div>
        )}
      </Panel>
      </>}
    </section>
  );
}

export default Alerts;
