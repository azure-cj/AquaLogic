import { AnalyticsRange, AnalyticsResponse } from '@/features/analytics/types';
import { fleetCounts, tankNameForAlert } from '@/features/fleet/utils';
import { api } from '@/shared/api/client';
import type { Alert, FleetTank } from '@/shared/api/models';
import {
  EmptyState,
  ErrorState,
  FleetStatus,
  LoadingState,
  Panel,
  StatusBadge
} from '@/shared/components/admin-ui';
import {
  formatReading as reading,
  relativeTime
} from '@/shared/utils/formatting';
import { useQuery } from '@tanstack/react-query';
import {
  AlertTriangle,
  BellRing,
  Check,
  ChevronRight,
  Droplets,
  WifiOff
} from 'lucide-react';
import {
  useState
} from 'react';
import {
  Link
} from 'react-router-dom';
import './styles.css';

function StatCard({
  label,
  value,
  detail,
  status,
  active,
  onClick,
}: {
  label: string;
  value: number;
  detail: string;
  status?: FleetStatus;
  active: boolean;
  onClick: () => void;
}) {
  const Icon =
    status === 'normal'
      ? Check
      : status === 'warning'
        ? AlertTriangle
        : status === 'critical'
          ? BellRing
          : status === 'offline'
            ? WifiOff
            : Droplets;
  return (
    <button
      type="button"
      className={`stat-card ${status ? `stat-${status}` : 'stat-total'} ${active ? 'active' : ''}`}
      onClick={onClick}
      aria-pressed={active}
    >
      <span>
        <small>{label}</small>
        <strong>{value}</strong>
        <em>{detail}</em>
      </span>
      <span className="stat-icon" aria-hidden="true">
        <Icon size={18} />
      </span>
    </button>
  );
}

function FleetTable({ tanks }: { tanks: FleetTank[]; }) {
  if (!tanks.length) {
    return <EmptyState title="No matching tanks" message="Choose another status filter." />;
  }
  return (
    <>
      <div className="data-table fleet-table">
        <div className="data-head">
          <span>Tank</span>
          <span>Status</span>
          <span>Species Care</span>
          <span>Temperature</span>
          <span>pH</span>
          <span>Ammonia</span>
          <span>Reporting</span>
          <span aria-hidden="true" />
        </div>
        {tanks.map((tank) => (
          <Link className="data-row" to={`/admin/tanks/${tank.id}`} key={tank.id}>
            <span className="tank-cell">
              <span className="tank-mark" aria-hidden="true">
                <Droplets size={16} />
              </span>
              <span>
                <strong>{tank.name}</strong>
                <small>
                  {tank.customer?.name ?? 'Unassigned'} · {tank.location}
                </small>
              </span>
            </span>
            <StatusBadge value={tank.status} />
            <span><StatusBadge value={tank.species_care_status ?? 'unavailable'} /><small>{tank.assigned_species_count ?? 0} assigned</small></span>
            <span className="metric-cell">
              {reading(tank.latest_reading?.temperature, '°C')}
            </span>
            <span className="metric-cell">{reading(tank.latest_reading?.ph, '', 1)}</span>
            <span className="metric-cell">
              {reading(tank.latest_reading?.ammonia, 'ppm', 2)}
            </span>
            <span>
              <strong className={tank.status === 'offline' ? 'text-critical' : ''}>
                {relativeTime(tank.last_reading_at)}
              </strong>
              <small>
                {tank.active_critical_count + tank.active_warning_count
                  ? `${tank.active_critical_count} critical · ${tank.active_warning_count} warning`
                  : 'No active alerts'}
              </small>
            </span>
            <ChevronRight size={17} aria-hidden="true" />
          </Link>
        ))}
      </div>
      <div className="fleet-card-list">
        {tanks.map((tank) => (
          <Link className="fleet-mobile-card" to={`/admin/tanks/${tank.id}`} key={tank.id}>
            <div>
              <span className="tank-mark" aria-hidden="true">
                <Droplets size={16} />
              </span>
              <span>
                <strong>{tank.name}</strong>
                <small>{tank.location}</small>
              </span>
              <StatusBadge value={tank.status} />
            </div>
            <dl>
              <div>
                <dt>Temp</dt>
                <dd>{reading(tank.latest_reading?.temperature, '°C')}</dd>
              </div>
              <div>
                <dt>pH</dt>
                <dd>{reading(tank.latest_reading?.ph, '')}</dd>
              </div>
              <div>
                <dt>NH₃</dt>
                <dd>{reading(tank.latest_reading?.ammonia, 'ppm', 2)}</dd>
              </div>
            </dl>
            <small>Last report {relativeTime(tank.last_reading_at)}</small>
            <small>Species Care: {tank.species_care_status ?? 'unavailable'} · {tank.assigned_species_count ?? 0} assigned</small>
          </Link>
        ))}
      </div>
    </>
  );
}

export function Fleet() {
  const [filter, setFilter] = useState<'all' | FleetStatus>('all');
  const [uptimeRange, setUptimeRange] =
    useState<Exclude<AnalyticsRange, 'custom'>>('24h');
  const fleet = useQuery({
    queryKey: ['fleet'],
    queryFn: () => api<FleetTank[]>('/fleet'),
    refetchInterval: 30_000,
  });
  const alerts = useQuery({
    queryKey: ['alerts', 'unresolved'],
    queryFn: () => api<Alert[]>('/alerts/history?resolved=false'),
    refetchInterval: 30_000,
  });
  const analytics = useQuery({
    queryKey: ['analytics', uptimeRange],
    queryFn: () => api<AnalyticsResponse>(`/analytics/fleet?range=${uptimeRange}`),
    refetchInterval: 30_000,
  });

  const tanks = fleet.data ?? [];
  const counts = fleetCounts(tanks);
  const filtered = filter === 'all' ? tanks : tanks.filter((tank) => tank.status === filter);
  const uptimeValues = analytics.data?.uptime ?? [];
  const averageUptime = analytics.data?.uptime_comparison.current ?? 0;
  const uptimeChange = analytics.data?.uptime_comparison.change ?? 0;
  const best = [...uptimeValues].sort((a, b) => b.uptime - a.uptime)[0];
  const rangeConfig = {
    '24h': {
      period: '24 hours',
      barCount: 24,
      barHours: 1,
      bucketMinutes: 15,
      expectedPerBar: 4,
      axis: ['24h ago', '18h', '12h', '6h', 'Now'],
      bucketLabel: '15-minute analytics buckets',
    },
    '7d': {
      period: '7 days',
      barCount: 28,
      barHours: 6,
      bucketMinutes: 60,
      expectedPerBar: 6,
      axis: ['7d ago', '5d', '3d', '1d', 'Now'],
      bucketLabel: 'Hourly analytics buckets',
    },
    '30d': {
      period: '30 days',
      barCount: 30,
      barHours: 24,
      bucketMinutes: 360,
      expectedPerBar: 4,
      axis: ['30d ago', '23d', '15d', '7d', 'Now'],
      bucketLabel: '6-hour analytics buckets',
    },
  }[uptimeRange];
  const reportingBars = Array.from({ length: rangeConfig.barCount }, (_, index) => {
    const end =
      Date.now() -
      (rangeConfig.barCount - 1 - index) * rangeConfig.barHours * 60 * 60 * 1000;
    const start = end - rangeConfig.barHours * 60 * 60 * 1000;
    const bucketCount = new Set(
      (analytics.data?.fleet_series ?? [])
        .filter((point) => {
          const timestamp = new Date(point.timestamp).getTime();
          return point.sample_count > 0 && timestamp >= start && timestamp < end;
        })
        .map((point) =>
          Math.floor(
            new Date(point.timestamp).getTime() /
            (rangeConfig.bucketMinutes * 60 * 1000),
          ),
        ),
    ).size;
    return Math.min(100, (bucketCount / rangeConfig.expectedPerBar) * 100);
  });
  const recentAlerts = [...(alerts.data ?? [])]
    .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
    .slice(0, 4);

  return (
    <section>
      <div className="stats-grid">
        <StatCard
          label="Total tanks"
          value={counts.total}
          detail="Registered fleet"
          active={filter === 'all'}
          onClick={() => setFilter('all')}
        />
        <StatCard
          label="Normal"
          value={counts.normal}
          detail="Within configured range"
          status="normal"
          active={filter === 'normal'}
          onClick={() => setFilter('normal')}
        />
        <StatCard
          label="Warning"
          value={counts.warning}
          detail="Needs attention soon"
          status="warning"
          active={filter === 'warning'}
          onClick={() => setFilter('warning')}
        />
        <StatCard
          label="Critical"
          value={counts.critical}
          detail="Immediate action required"
          status="critical"
          active={filter === 'critical'}
          onClick={() => setFilter('critical')}
        />
        <StatCard
          label="Offline"
          value={counts.offline}
          detail="No recent report"
          status="offline"
          active={filter === 'offline'}
          onClick={() => setFilter('offline')}
        />
      </div>
      <div className="fleet-workspace">
        <Panel
          title="Tank health"
          description="Live readings and reporting status"
          className="fleet-health-panel"
          action={
            <div className="segmented" aria-label="Fleet status filter">
              <button className={filter === 'all' ? 'active' : ''} onClick={() => setFilter('all')}>
                All tanks
              </button>
              <button
                className={filter !== 'all' ? 'active' : ''}
                onClick={() => filter === 'all' && setFilter('warning')}
              >
                Needs action · {counts.warning + counts.critical + counts.offline}
              </button>
            </div>
          }
        >
          {fleet.isLoading ? (
            <LoadingState label="Loading fleet status…" />
          ) : fleet.isError ? (
            <ErrorState message="Fleet data could not be loaded." retry={() => fleet.refetch()} />
          ) : (
            <FleetTable tanks={filtered} />
          )}
        </Panel>
        <div className="fleet-rail">
          <Panel
            title="Recent alerts"
            description={`${alerts.data?.length ?? 0} unresolved across the fleet`}
            action={
              <Link className="text-link" to="/admin/alerts">
                View all <ChevronRight size={15} />
              </Link>
            }
          >
            {alerts.isLoading ? (
              <LoadingState label="Loading alerts…" />
            ) : alerts.isError ? (
              <ErrorState message="Alerts are temporarily unavailable." />
            ) : recentAlerts.length ? (
              <div className="alert-feed">
                {recentAlerts.map((alert) => (
                  <Link to="/admin/alerts" className="alert-feed-item" key={alert.id}>
                    <span className={`alert-symbol alert-${alert.severity}`} aria-hidden="true">
                      <AlertTriangle size={16} />
                    </span>
                    <span>
                      <strong>
                        {alert.parameter.replaceAll('_', ' ')} · {tankNameForAlert(alert, tanks)}
                      </strong>
                      <small>{alert.message}</small>
                    </span>
                    <time>{relativeTime(alert.created_at)}</time>
                  </Link>
                ))}
              </div>
            ) : (
              <EmptyState title="All clear" message="There are no unresolved alerts." />
            )}
          </Panel>
          <Panel
            title="Reporting uptime"
            description={`Fleet-wide · last ${rangeConfig.period}`}
            action={
              <label>
                <span className="sr-only">Uptime range</span>
                <select
                  className="uptime-range"
                  value={uptimeRange}
                  onChange={(event) =>
                    setUptimeRange(
                      event.target.value as Exclude<AnalyticsRange, 'custom'>,
                    )
                  }
                >
                  <option value="24h">24 hours</option>
                  <option value="7d">7 days</option>
                  <option value="30d">30 days</option>
                </select>
              </label>
            }
          >
            {analytics.isLoading ? (
              <LoadingState label="Calculating uptime…" />
            ) : analytics.isError ? (
              <ErrorState message="Uptime data is temporarily unavailable." />
            ) : (
              <div className="uptime-card-body">
                <div className="uptime-value-row">
                  <strong>{averageUptime.toFixed(1)}%</strong>
                  <span className={uptimeChange < 0 ? 'trend-down' : 'trend-up'}>
                    {uptimeChange >= 0 ? '↑' : '↓'} {Math.abs(uptimeChange).toFixed(1)}%
                    {' '}vs previous {rangeConfig.period}
                  </span>
                </div>
                <div
                  className="uptime-bars"
                  role="img"
                  aria-label={`Reporting coverage over the last ${rangeConfig.period}. Fleet uptime ${averageUptime.toFixed(1)} percent.`}
                >
                  {reportingBars.map((value, index) => (
                    <span
                      className={value === 0 ? 'no-report' : value < 50 ? 'partial-report' : ''}
                      style={{ height: `${Math.max(value, 8)}%` }}
                      key={index}
                      title={`${value.toFixed(0)}% reporting coverage`}
                    />
                  ))}
                </div>
                <div className="uptime-axis" aria-hidden="true">
                  {rangeConfig.axis.map((label) => <span key={label}>{label}</span>)}
                </div>
                <div className="uptime-footer">
                  <span><i aria-hidden="true" />{rangeConfig.bucketLabel}</span>
                  <span>{best ? `Best: ${best.tank_name} · ${best.uptime}%` : 'No reporting data'}</span>
                </div>
              </div>
            )}
          </Panel>
        </div>
      </div>
    </section>
  );
}

export default Fleet;
