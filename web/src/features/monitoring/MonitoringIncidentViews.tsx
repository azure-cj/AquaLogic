import { api } from '@/shared/api/client';
import type { MonitoringIncident, MonitoringIncidentPage } from '@/shared/api/models';
import {
  EmptyState,
  ErrorState,
  LoadingState,
  Notice,
  Panel,
  StatusBadge,
} from '@/shared/components/admin-ui';
import { formatDate, relativeTime } from '@/shared/utils/formatting';
import { useQuery } from '@tanstack/react-query';
import { ChevronLeft, ChevronRight, RadioTower } from 'lucide-react';
import { useEffect, useState } from 'react';
import './styles.css';

function durationLabel(seconds: number): string {
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  if (hours < 24) return remainingMinutes ? `${hours}h ${remainingMinutes}m` : `${hours}h`;
  const days = Math.floor(hours / 24);
  const remainingHours = hours % 24;
  return remainingHours ? `${days}d ${remainingHours}h` : `${days}d`;
}

function reasonLabel(incident: MonitoringIncident): string {
  if (incident.resolution_reason === 'reporting_recovered') return 'Reporting recovered automatically';
  if (incident.resolution_reason === 'monitoring_disabled') return 'Monitoring disabled';
  if (incident.resolution_reason === 'tank_retired') return 'Tank retired';
  return 'Still active';
}

function IncidentRow({ incident }: { incident: MonitoringIncident }) {
  const active = incident.state === 'active';
  return (
    <article className={`monitoring-incident-row ${active ? 'is-active' : 'is-resolved'}`}>
      <div className="monitoring-incident-icon" aria-hidden="true"><RadioTower size={17} /></div>
      <div className="monitoring-incident-main">
        <div className="monitoring-incident-heading">
          <strong>{active ? 'Monitoring outage recorded' : 'Monitoring outage'}</strong>
          <StatusBadge value={active ? 'critical' : 'normal'} />
        </div>
        <span className="monitoring-incident-tank">{incident.tank_name}</span>
        <dl>
          <div><dt>Started</dt><dd>{formatDate(incident.started_at)}</dd></div>
          <div><dt>Detected</dt><dd>{formatDate(incident.detected_at)}</dd></div>
          <div><dt>Last accepted report</dt><dd>{incident.last_reading_received_at ? relativeTime(incident.last_reading_received_at) : 'None recorded'}</dd></div>
          <div><dt>{active ? 'Current duration' : 'Duration'}</dt><dd>{durationLabel(incident.duration_seconds)}</dd></div>
        </dl>
        <small className="monitoring-incident-reason">{reasonLabel(incident)}</small>
      </div>
    </article>
  );
}

type IncidentHistoryProps = {
  tankId?: number;
  pageSize?: number;
  title?: string;
  description?: string;
  compact?: boolean;
};

export function MonitoringIncidentHistory({
  tankId,
  pageSize = 25,
  title = 'Monitoring outages',
  description = 'Tank-level reporting incidents are separate from water-quality alerts. They close only after accepted reporting resumes or monitoring is intentionally disabled.',
  compact = false,
}: IncidentHistoryProps) {
  const [page, setPage] = useState(1);
  useEffect(() => setPage(1), [tankId]);
  const query = new URLSearchParams({ state: 'all', page: String(page), page_size: String(pageSize) });
  if (tankId !== undefined) query.set('tank_id', String(tankId));
  const incidents = useQuery({
    queryKey: ['monitoring-incidents', tankId ?? 'all', page, pageSize],
    queryFn: () => api<MonitoringIncidentPage>(`/monitoring-incidents?${query.toString()}`),
  });
  const data = incidents.data;

  const content = incidents.isLoading ? (
    <LoadingState label="Loading monitoring outages…" />
  ) : incidents.isError ? (
    <ErrorState message="Monitoring outage history could not be loaded." retry={() => incidents.refetch()} />
  ) : data?.items.length ? (
    <>
      <div className="monitoring-incident-list">
        {data.items.map((incident) => <IncidentRow incident={incident} key={incident.id} />)}
      </div>
      <div className="monitoring-incident-footer">
        <span aria-live="polite">Showing {((data.page - 1) * data.page_size) + 1}–{Math.min(data.page * data.page_size, data.total)} of {data.total}</span>
        <div className="monitoring-incident-pagination" aria-label="Monitoring outage history pagination">
          <button className="button button-secondary button-small" type="button" disabled={!data.has_previous || incidents.isFetching} onClick={() => setPage((current) => Math.max(1, current - 1))}>
            <ChevronLeft size={14} /> Previous
          </button>
          <span>Page {data.page} of {data.total_pages}</span>
          <button className="button button-secondary button-small" type="button" disabled={!data.has_next || incidents.isFetching} onClick={() => setPage((current) => current + 1)}>
            Next <ChevronRight size={14} />
          </button>
        </div>
      </div>
    </>
  ) : (
    <EmptyState title="No monitoring outages recorded" message="Accepted reporting has not crossed the unattended outage grace period for this scope." />
  );

  return (
    <Panel title={title} description={description} className={`monitoring-incident-panel ${compact ? 'is-compact' : ''}`}>
      {!compact && <Notice>Offline remains the live 90-second freshness state. A recorded outage does not describe water quality and has no manual resolution action.</Notice>}
      {content}
    </Panel>
  );
}

export function MonitoringIncidentTankPanel({ tankId }: { tankId: number }) {
  return (
    <MonitoringIncidentHistory
      tankId={tankId}
      pageSize={10}
      title="Monitoring outage history"
      description="Reporting continuity for this tank, kept separate from water-quality alerts. Last-known readings remain context while an outage is active."
      compact
    />
  );
}
