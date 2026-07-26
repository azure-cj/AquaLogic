import { api } from '@/shared/api/client';
import {
  EmptyState,
  ErrorState,
  LoadingState,
  PageHeader,
  Panel,
} from '@/shared/components/admin-ui';
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import './styles.css';
import {
  AnalyticsRange,
  AnalyticsResponse,
  MetricKey,
  metricOptions,
} from './types';

const formatDate = (value: string) =>
  new Intl.DateTimeFormat('en-PH', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'Asia/Manila',
  }).format(new Date(value));

export default function AnalyticsPage() {
  const [range, setRange] = useState<AnalyticsRange>('24h');
  const [metric, setMetric] = useState<MetricKey>('temperature');
  const query = useQuery({
    queryKey: ['analytics', range],
    queryFn: () => api<AnalyticsResponse>(`/analytics/fleet?range=${range}`),
  });
  const selected = metricOptions.find((option) => option.key === metric)!;
  const values = (query.data?.series ?? []).map((point) => point[metric]);
  const average = values.length
    ? values.reduce((sum, value) => sum + value, 0) / values.length
    : 0;
  const minimum = values.length ? Math.min(...values) : 0;
  const maximum = values.length ? Math.max(...values) : 0;
  const comparison = query.data?.uptime_comparison;
  const tickDate = (value: string) =>
    new Intl.DateTimeFormat('en-PH', {
      month: range === '30d' ? 'short' : undefined,
      day: range === '30d' ? 'numeric' : undefined,
      hour: range === '30d' ? undefined : 'numeric',
      timeZone: 'Asia/Manila',
    }).format(new Date(value));

  return (
    <section>
      <PageHeader
        eyebrow="Performance"
        title="Fleet analytics"
        description="Compare water-quality trends, alert frequency, and reporting uptime."
        actions={
          <label className="range-select">
            <span className="sr-only">Analytics range</span>
            <select
              value={range}
              onChange={(event) => setRange(event.target.value as AnalyticsRange)}
            >
              <option value="24h">Last 24 hours</option>
              <option value="7d">Last 7 days</option>
              <option value="30d">Last 30 days</option>
            </select>
          </label>
        }
      />
      <div className="metric-tabs" role="tablist" aria-label="Water quality metric">
        {metricOptions.map((option) => (
          <button
            key={option.key}
            role="tab"
            aria-selected={metric === option.key}
            className={metric === option.key ? 'active' : ''}
            onClick={() => setMetric(option.key)}
          >
            {option.label}
          </button>
        ))}
      </div>
      {query.isLoading ? (
        <Panel>
          <LoadingState label="Building fleet analytics…" />
        </Panel>
      ) : query.isError ? (
        <Panel>
          <ErrorState message="Analytics could not be loaded." retry={() => query.refetch()} />
        </Panel>
      ) : (
        <>
          <div className="analytics-stats">
            <div>
              <small>Fleet average</small>
              <strong>
                {average.toFixed(2)} <em>{selected.unit}</em>
              </strong>
            </div>
            <div>
              <small>Lowest bucket</small>
              <strong>
                {minimum.toFixed(2)} <em>{selected.unit}</em>
              </strong>
            </div>
            <div>
              <small>Highest bucket</small>
              <strong>
                {maximum.toFixed(2)} <em>{selected.unit}</em>
              </strong>
            </div>
            <div>
              <small>Reporting uptime</small>
              <strong>{comparison?.current.toFixed(1) ?? '0.0'}%</strong>
              <em className={comparison && comparison.change < 0 ? 'trend-down' : 'trend-up'}>
                {comparison && comparison.change < 0 ? '↓' : '↑'}{' '}
                {Math.abs(comparison?.change ?? 0).toFixed(1)}% vs previous period
              </em>
            </div>
          </div>
          <Panel
            title={`${selected.label} trend`}
            description={`Fleet-wide bucket average · ${selected.unit}`}
            className="chart-panel"
          >
            {query.data?.series.length ? (
              <ResponsiveContainer width="100%" height={320}>
                <AreaChart
                  data={query.data.series}
                  margin={{ top: 16, right: 12, left: -10, bottom: 0 }}
                >
                  <defs>
                    <linearGradient id="metricFill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor={selected.color} stopOpacity={0.28} />
                      <stop offset="100%" stopColor={selected.color} stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid stroke="#e5edef" vertical={false} />
                  <XAxis
                    dataKey="timestamp"
                    tickFormatter={tickDate}
                    tick={{ fill: '#6f8590', fontSize: 11 }}
                    axisLine={false}
                    tickLine={false}
                  />
                  <YAxis
                    tick={{ fill: '#6f8590', fontSize: 11 }}
                    axisLine={false}
                    tickLine={false}
                    width={55}
                  />
                  <Tooltip
                    labelFormatter={(value) => formatDate(String(value))}
                    formatter={(value) => [
                      `${Number(value).toFixed(2)} ${selected.unit}`,
                      selected.label,
                    ]}
                  />
                  <Area
                    type="monotone"
                    dataKey={metric}
                    stroke={selected.color}
                    strokeWidth={2.5}
                    fill="url(#metricFill)"
                    activeDot={{ r: 5 }}
                  />
                </AreaChart>
              </ResponsiveContainer>
            ) : (
              <EmptyState title="No trend data" message="No readings exist for this range." />
            )}
          </Panel>
          <div className="analytics-grid">
            <Panel
              title="Alert frequency"
              description={`${query.data?.alert_counts.warning ?? 0} warning · ${query.data?.alert_counts.critical ?? 0} critical`}
              className="chart-panel"
            >
              {query.data?.alert_series.length ? (
                <ResponsiveContainer width="100%" height={230}>
                  <BarChart
                    data={query.data.alert_series}
                    margin={{ top: 12, right: 8, left: -20 }}
                  >
                    <CartesianGrid stroke="#e5edef" vertical={false} />
                    <XAxis
                      dataKey="timestamp"
                      tickFormatter={tickDate}
                      tick={{ fill: '#6f8590', fontSize: 10 }}
                      axisLine={false}
                      tickLine={false}
                    />
                    <YAxis
                      allowDecimals={false}
                      tick={{ fill: '#6f8590', fontSize: 10 }}
                      axisLine={false}
                      tickLine={false}
                    />
                    <Tooltip labelFormatter={(value) => formatDate(String(value))} />
                    <Bar
                      dataKey="warning"
                      stackId="alerts"
                      fill="#e99a21"
                      radius={[3, 3, 0, 0]}
                    />
                    <Bar
                      dataKey="critical"
                      stackId="alerts"
                      fill="#dc5664"
                      radius={[3, 3, 0, 0]}
                    />
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <EmptyState title="No alerts" message="No alerts were recorded in this range." />
              )}
            </Panel>
            <Panel
              title="Tank reporting uptime"
              description="Unique 30-second intervals compared with expected"
            >
              <div className="uptime-list">
                {query.data?.uptime.map((item) => (
                  <div key={item.tank_id}>
                    <span>
                      <strong>{item.tank_name}</strong>
                      <small>{item.uptime}%</small>
                    </span>
                    <span
                      className="progress-track"
                      aria-label={`${item.uptime} percent uptime`}
                    >
                      <i style={{ width: `${item.uptime}%` }} />
                    </span>
                  </div>
                ))}
              </div>
            </Panel>
          </div>
        </>
      )}
    </section>
  );
}
