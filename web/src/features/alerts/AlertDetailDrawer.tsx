import { api } from '@/shared/api/client';
import type { AlertContext, AlertContextReading, AlertContextThreshold } from '@/shared/api/models';
import { Drawer, ErrorState, LoadingState, StatusBadge } from '@/shared/components/admin-ui';
import { formatDate } from '@/shared/utils/formatting';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import './styles.css';
import { notify } from '@/shared/lib/notify';

function Reading({ title, reading }: { title: string; reading: AlertContextReading | null }) {
  return <section className="alert-reading-card"><h3>{title}</h3>{reading ? <>
    <strong className="alert-reading-value">{reading.value ?? 'Unavailable'} <em>{reading.unit}</em></strong>
    <dl className="alert-reading-times"><div><dt>Observed</dt><dd>{formatDate(reading.observed_at)}</dd></div><div><dt>Received</dt><dd>{formatDate(reading.received_at)}</dd></div></dl>
    <small>Reading #{reading.reading_id}</small>
  </> : <p>Reading unavailable.</p>}</section>;
}

function Bounds({ title, threshold }: { title: string; threshold: AlertContextThreshold | null }) {
  return <section><h3>{title}</h3>{threshold ? <>
    <p>{threshold.source === 'tank' ? 'Tank override' : 'Global default'} · {threshold.enabled ? 'Enabled' : 'Currently disabled'}</p>
    <p>Warning bounds: {threshold.warning_min ?? 'No lower bound'} – {threshold.warning_max ?? 'No upper bound'} {threshold.unit}<br />
      Critical bounds: {threshold.critical_min ?? 'No lower bound'} – {threshold.critical_max ?? 'No upper bound'} {threshold.unit}</p>
  </> : <p>Bounds unavailable.</p>}</section>;
}

export function AlertDetailDrawer({ alertId, onClose }: { alertId: number | null; onClose: () => void }) {
  const client = useQueryClient();
  const context = useQuery({ queryKey: ['alert-context', alertId], queryFn: () => api<AlertContext>(`/alerts/${alertId}/context`), enabled: alertId !== null });
  const me = useQuery({ queryKey: ['me'], queryFn: () => api<{ role: string }>('/auth/me'), enabled: alertId !== null });
  const resolve = useMutation({
    mutationFn: () => api(`/alerts/${alertId}/resolve`, { method: 'PUT' }),
    onSuccess: async () => {
      await Promise.all(['alert-context', 'alerts', 'tank-alert-history', 'tank-operations', 'tank', 'fleet'].map((key) => client.invalidateQueries({ queryKey: [key] })));
      notify.success('Alert marked as handled.');
    },
    onError: () => notify.error('The alert could not be marked as handled.'),
  });
  const data = context.data;
  const lifecycle = data?.alert.is_resolved ? data.alert.resolution_source === 'operator' ? 'Handled by operator' : data.alert.resolution_source === 'system' ? 'Automatically resolved' : 'Resolved' : 'Active';
  return <Drawer open={alertId !== null} title="Water-quality alert detail" description="Readings, configured bounds, and suggested checks" onClose={onClose} footer={data && !context.isError ? (
      <div className="alert-detail-footer"><div className="alert-detail-actions">
        <Link className="button button-secondary" to={`/admin/tanks/${data.tank.id}`}>View tank</Link>
        <Link className="button button-secondary" to={me.data?.role === 'admin' ? `/admin/tanks/${data.tank.id}/actuators` : `/admin/tanks/${data.tank.id}?tab=control`}>View equipment</Link>
        <Link className="button button-secondary" to={`/admin/alerts?tank_id=${data.tank.id}`}>View history</Link>
        <Link className="button button-secondary" to={`/admin/analytics?tanks=${data.tank.id}&metric=${data.alert.parameter}`}>View Analytics</Link>
        {!data.alert.is_resolved && data.tank.lifecycle === 'active' && <button className="button button-primary" disabled={resolve.isPending} onClick={() => resolve.mutate()}>{resolve.isPending ? 'Marking handled…' : 'Mark handled'}</button>}
      </div>
      <p className="alert-context-note">Mark handled acknowledges a response. It does not confirm water recovery. Automatic resolution may follow a normal reading or a disabled threshold.</p></div>
    ) : undefined}>
    {context.isLoading ? <LoadingState label="Loading alert context…" /> : context.isError ? <ErrorState message="Alert context could not be loaded." retry={() => context.refetch()} /> : data ? <div className="alert-detail-content">
      <section className="alert-overview"><h2>{data.tank.display_name} · {data.alert.parameter === 'ph' ? 'pH' : data.alert.parameter}</h2><StatusBadge value={data.alert.severity} /> <strong>{lifecycle}</strong>
        <p>{data.alert.message}</p><small>Alert #{data.alert.id} · Created {formatDate(data.alert.created_at)} · Tank {data.tank.lifecycle}</small>
        {data.alert.resolved_at && <p>{lifecycle} {formatDate(data.alert.resolved_at)}</p>}
      </section>
      <div className="alert-reading-comparison">
        <Reading title="Reading linked to this alert" reading={data.linked_reading} />
        <Reading title="Latest received reading" reading={data.latest_reading} />
      </div>
      <p className="alert-context-note">Reporting {data.latest_reading?.reporting_freshness ?? 'unavailable'}. Recent receipt does not prove the observation is current.</p>
      <section className="alert-checks"><h3>Suggested checks</h3><p>{data.guidance.explanation}</p><ul>{data.guidance.checks.map((check) => <li key={check}>{check}</li>)}</ul><p className="alert-context-note">{data.guidance.advisory}</p></section>
      <details className="alert-evidence"><summary>Configured bounds &amp; historical context</summary><div className="alert-bounds-grid">
        <Bounds title="Associated historical bounds" threshold={data.linked_threshold} />
        <Bounds title="Current configured bounds" threshold={data.current_threshold} />
      </div><p className="alert-context-note">Historical bounds are reconstructed from revisions at receipt time; they are not an immutable detection snapshot. Active alerts can link to subsequent abnormal readings.</p></details>
      {data.species_context && <section className="alert-species" aria-label="Stored species preferences"><h3>Stored species preferences</h3>
        <p className="alert-context-note">Current assignments and latest received reading, including for historical alerts.</p>
        {data.species_context.status !== 'unsupported' && <p className="alert-species-summary">{data.species_context.counts.assigned} distinct species assigned · {data.species_context.counts.evaluable} evaluable · {data.species_context.counts.within} within · {data.species_context.counts.outside} outside · {data.species_context.counts.unavailable} unavailable</p>}
        {data.species_context.status === 'unsupported' ? <p className="alert-context-note">Stored species preferences do not support turbidity comparisons. Alerts use the tank's configured thresholds.</p> : <details className="alert-evidence"><summary>View individual stored preferences</summary>{data.species_context.reading && <p>Reading #{data.species_context.reading.reading_id}<br />Observed {formatDate(data.species_context.reading.observed_at)}<br />Received {formatDate(data.species_context.reading.received_at)}</p>}
        {data.species_context.reason && <p>Comparison {data.species_context.status}: {data.species_context.reason.replaceAll('_', ' ')}. </p>}
        <div className="alert-species-rows">{data.species_context.species.map((species) => <p key={species.species_id}><strong>{species.name}</strong><br />{species.stored_min ?? 'No lower bound'} – {species.stored_max ?? 'No upper bound'} {data.species_context?.unit}<br />{species.result} · {species.reason.replaceAll('_', ' ')}</p>)}</div>
        <p className="alert-context-note">{data.species_context.advisory}</p></details>}
      </section>}


    </div> : null}
  </Drawer>;
}
