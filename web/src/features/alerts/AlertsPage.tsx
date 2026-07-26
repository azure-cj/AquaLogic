import { metricOptions } from '@/features/analytics/types';
import { tankNameForAlert } from '@/features/fleet/utils';
import { api } from '@/shared/api/client';
import type { Alert, FleetTank } from '@/shared/api/models';
import {
  EmptyState,
  ErrorState,
  LoadingState,
  Notice,
  PageHeader,
  Panel,
  StatusBadge
} from '@/shared/components/admin-ui';
import {
  formatDate,
  relativeTime
} from '@/shared/utils/formatting';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Check,
  X
} from 'lucide-react';
import {
  useEffect,
  useState
} from 'react';
import { useSearchParams } from 'react-router-dom';
import './styles.css';

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
  const [notice, setNotice] = useState('');
  const filters = new URLSearchParams();
  if (severity) filters.set('severity', severity);
  if (parameter) filters.set('parameter', parameter);
  if (resolved) filters.set('resolved', resolved);
  if (tankId) filters.set('tank_id', tankId);
  if (after) filters.set('created_after', new Date(after).toISOString());
  if (before) filters.set('created_before', new Date(before).toISOString());
  const query = filters.toString();
  useEffect(() => {
    if (query !== urlParams.toString()) {
      setUrlParams(filters, { replace: true });
    }
  }, [query, setUrlParams, urlParams]);
  const alerts = useQuery({
    queryKey: ['alerts', query],
    queryFn: () => api<Alert[]>(`/alerts/history${query ? `?${query}` : ''}`),
  });
  const fleet = useQuery({ queryKey: ['fleet'], queryFn: () => api<FleetTank[]>('/fleet') });
  const resolve = useMutation({
    mutationFn: (id: number) => api(`/alerts/${id}/resolve`, { method: 'PUT' }),
    onSuccess: () => {
      setNotice('Alert marked as resolved.');
      client.invalidateQueries({ queryKey: ['alerts'] });
    },
  });
  const visibleAlerts = alerts.data ?? [];
  const clear = () => {
    setSeverity('');
    setParameter('');
    setResolved('');
    setTankId('');
    setAfter('');
    setBefore('');
  };

  return (
    <section>
      <PageHeader
        eyebrow="Fleet history"
        title="Alert history"
        description="Filter, investigate, and resolve water-quality events across the fleet."
        actions={
          <button className="button button-secondary" type="button" onClick={clear}>
            <X size={16} /> Clear filters
          </button>
        }
      />
      {notice && <Notice>{notice}</Notice>}
      <Panel className="filter-panel">
        <div className="filter-grid">
          <label className="field">
            <span>Tank</span>
            <select value={tankId} onChange={(event) => setTankId(event.target.value)}>
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
            <select value={severity} onChange={(event) => setSeverity(event.target.value)}>
              <option value="">All severities</option>
              <option value="warning">Warning</option>
              <option value="critical">Critical</option>
            </select>
          </label>
          <label className="field">
            <span>Parameter</span>
            <select value={parameter} onChange={(event) => setParameter(event.target.value)}>
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
            <select value={resolved} onChange={(event) => setResolved(event.target.value)}>
              <option value="">All states</option>
              <option value="false">Unresolved</option>
              <option value="true">Resolved</option>
            </select>
          </label>
          <label className="field">
            <span>From</span>
            <input type="datetime-local" value={after} onChange={(event) => setAfter(event.target.value)} />
          </label>
          <label className="field">
            <span>To</span>
            <input type="datetime-local" value={before} onChange={(event) => setBefore(event.target.value)} />
          </label>
        </div>
      </Panel>
      <Panel
        title="Recorded events"
        description={`${visibleAlerts.length} alert${visibleAlerts.length === 1 ? '' : 's'} match the current filters`}
      >
        {alerts.isLoading ? (
          <LoadingState label="Loading alert history…" />
        ) : alerts.isError ? (
          <ErrorState message="Alert history could not be loaded." retry={() => alerts.refetch()} />
        ) : visibleAlerts.length ? (
          <div className="data-table alerts-table">
            <div className="data-head">
              <span>Event</span>
              <span>Tank</span>
              <span>Severity</span>
              <span>Created</span>
              <span>State</span>
            </div>
            {visibleAlerts.map((alert) => (
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
                        <Check size={14} /> Resolved
                      </span>
                      <small>{formatDate(alert.resolved_at)}</small>
                    </>
                  ) : (
                    <button
                      className="button button-secondary button-small"
                      type="button"
                      disabled={resolve.isPending && resolve.variables === alert.id}
                      onClick={() => resolve.mutate(alert.id)}
                    >
                      {resolve.isPending && resolve.variables === alert.id
                        ? 'Resolving…'
                        : 'Resolve'}
                    </button>
                  )}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <EmptyState title="No alerts found" message="Adjust the filters to broaden the results." />
        )}
      </Panel>
    </section>
  );
}

export default Alerts;
