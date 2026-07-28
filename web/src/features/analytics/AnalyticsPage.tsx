import { api } from '@/shared/api/client';
import {
  EmptyState,
  ErrorState,
  LoadingState,
  PageHeader,
  Panel,
} from '@/shared/components/admin-ui';
import { useQuery } from '@tanstack/react-query';
import {
  AlertTriangle,
  CalendarRange,
  Download,
  Info,
  Layers3,
  Search,
} from 'lucide-react';
import { KeyboardEvent, useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import {
  Area,
  Bar,
  BarChart,
  CartesianGrid,
  ComposedChart,
  Line,
  LineChart,
  ReferenceArea,
  ReferenceDot,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import './styles.css';
import {
  AnalyticsAlert,
  AnalyticsBucket,
  AnalyticsRange,
  AnalyticsResponse,
  MetricKey,
  metricOptions,
  ThresholdSegment,
} from './types';
import {
  activeThreshold,
  analyticsCsv,
  formatAnalyticsDate,
  MANILA_TIMEZONE,
  thresholdZones,
} from './utils';

const ranges: AnalyticsRange[] = ['24h', '7d', '30d', 'custom'];
const buckets: AnalyticsBucket[] = ['auto', '15m', '1h', '6h', '1d'];
const metrics = metricOptions.map((option) => option.key);
const tankColors = ['#4169a1', '#8a6a3d', '#7659a5'];

const localInputValue = (date: Date) => {
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
};

const validMetric = (value: string | null): value is MetricKey =>
  metrics.includes(value as MetricKey);

const boundLabel = (
  minimum: number | null,
  maximum: number | null,
  unit: string,
) => {
  if (minimum != null && maximum != null) return `${minimum}–${maximum} ${unit}`;
  if (minimum != null) return `below ${minimum} ${unit}`;
  if (maximum != null) return `above ${maximum} ${unit}`;
  return 'not configured';
};

function InfoLabel({ label, explanation }: { label: string; explanation: string; }) {
  return (
    <span className="metric-label" title={explanation}>
      {label} <Info size={12} aria-hidden="true" />
    </span>
  );
}

function AlertMarker({
  cx,
  cy,
  event,
  onOpen,
}: {
  cx?: number;
  cy?: number;
  event: AnalyticsAlert;
  onOpen: (event: AnalyticsAlert) => void;
}) {
  if (cx == null || cy == null) return null;
  const label = `${event.severity} alert for ${event.tank_name}: ${event.message}, ${formatAnalyticsDate(event.timestamp)}`;
  const openWithKeyboard = (keyboardEvent: KeyboardEvent<SVGGElement>) => {
    if (keyboardEvent.key === 'Enter' || keyboardEvent.key === ' ') {
      keyboardEvent.preventDefault();
      onOpen(event);
    }
  };
  return (
    <g
      className={`analytics-alert-marker marker-${event.severity}`}
      role="link"
      tabIndex={0}
      aria-label={label}
      onClick={() => onOpen(event)}
      onKeyDown={openWithKeyboard}
    >
      <title>{label}</title>
      <circle cx={cx} cy={cy} r={6} />
      <circle cx={cx} cy={cy} r={2} className="marker-core" />
    </g>
  );
}

type ChartRow = {
  timestamp: number;
  fleet: number | null;
  previous: number | null;
  contributors: number;
  samples: number;
  [key: `tank-${number}`]: number | null;
};

function chartRows(data: AnalyticsResponse, metric: MetricKey): ChartRow[] {
  return data.fleet_series.map((point, index) => {
    const row: ChartRow = {
      timestamp: new Date(point.timestamp).getTime(),
      fleet: point.values[metric],
      previous: data.previous_fleet_series[index]?.values[metric] ?? null,
      contributors: point.contributor_count,
      samples: point.sample_count,
    };
    data.tank_series.forEach((tank) => {
      row[`tank-${tank.tank_id}`] = tank.series[index]?.values[metric] ?? null;
    });
    return row;
  });
}

function chartDomain(
  rows: ChartRow[],
  metric: MetricKey,
  segments: ThresholdSegment[],
) {
  const values = rows.flatMap((row) => [
    row.fleet,
    row.previous,
    ...Object.entries(row)
      .filter(([key]) => key.startsWith('tank-'))
      .map(([, value]) => value as number | null),
  ]).filter((value): value is number => value != null && Number.isFinite(value));
  segments
    .filter((segment) => segment.parameter === metric && segment.enabled)
    .forEach((segment) => {
      [
        segment.warning_min,
        segment.warning_max,
        segment.critical_min,
        segment.critical_max,
      ].forEach((value) => {
        if (value != null) values.push(value);
      });
    });
  if (!values.length) return [0, 1] as [number, number];
  const minimum = Math.min(...values);
  const maximum = Math.max(...values);
  const padding = Math.max((maximum - minimum) * 0.12, Math.abs(maximum) * 0.03, 0.1);
  return [minimum - padding, maximum + padding] as [number, number];
}

function ChartTooltip({
  active,
  payload,
  label,
  unit,
}: {
  active?: boolean;
  payload?: Array<{ name: string; value: number | null; color?: string; payload?: ChartRow; }>;
  label?: number;
  unit: string;
}) {
  if (!active || !payload?.length || label == null) return null;
  return (
    <div className="analytics-tooltip">
      <strong>{formatAnalyticsDate(label)}</strong>
      {payload
        .filter((item) => item.value != null)
        .map((item) => (
          <span key={item.name}>
            <i style={{ background: item.color }} />
            {item.name}: {Number(item.value).toFixed(2)} {unit}
          </span>
        ))}
      <small>
        {payload[0]?.payload?.contributors ?? 0} contributing tank(s) ·{' '}
        {payload[0]?.payload?.samples ?? 0} samples
      </small>
    </div>
  );
}

function ThresholdOverlays({
  segments,
  metric,
  domain,
}: {
  segments: ThresholdSegment[];
  metric: MetricKey;
  domain: [number, number];
}) {
  return (
    <>
      {segments
        .filter((segment) => segment.parameter === metric && segment.enabled)
        .flatMap((segment, segmentIndex) => {
          const x1 = new Date(segment.start).getTime();
          const x2 = new Date(segment.end).getTime();
          const zones: JSX.Element[] = thresholdZones(segment, domain).map(
            (zone, zoneIndex) => (
              <ReferenceArea
                key={`${segmentIndex}-${zone.tone}-${zoneIndex}`}
                x1={x1}
                x2={x2}
                y1={zone.y1}
                y2={zone.y2}
                fill={zone.tone === 'warning' ? '#e99a21' : '#dc5664'}
                fillOpacity={zone.tone === 'warning' ? 0.18 : 0.16}
                strokeOpacity={0}
              />
            ),
          );
          [
            ['warning-min', segment.warning_min, '#e99a21'],
            ['warning-max', segment.warning_max, '#e99a21'],
            ['critical-min', segment.critical_min, '#dc5664'],
            ['critical-max', segment.critical_max, '#dc5664'],
          ].forEach(([name, value, color]) => {
            if (typeof value !== 'number') return;
            zones.push(
              <ReferenceLine
                key={`${segmentIndex}-${name}`}
                segment={[{ x: x1, y: value }, { x: x2, y: value }]}
                stroke={String(color)}
                strokeDasharray="4 4"
                strokeWidth={1}
              />,
            );
          });
          return zones;
        })}
    </>
  );
}

function TrendChart({
  data,
  metric,
  showPrevious,
  onAlert,
  height = 330,
}: {
  data: AnalyticsResponse;
  metric: MetricKey;
  showPrevious: boolean;
  onAlert: (event: AnalyticsAlert) => void;
  height?: number;
}) {
  const selected = metricOptions.find((option) => option.key === metric)!;
  const rows = chartRows(data, metric);
  const domain = chartDomain(rows, metric, data.threshold_segments);
  const alerts = data.alert_events.filter(
    (event) => event.parameter === metric && event.value != null,
  );
  const hasReadings = rows.some((row) =>
    [row.fleet, ...data.tank_series.map((tank) => row[`tank-${tank.tank_id}`])]
      .some((value) => value != null),
  );
  if (!hasReadings) {
    return <EmptyState title="No readings" message="No readings match this range and scope." />;
  }
  return (
    <ResponsiveContainer width="100%" height={height}>
      <ComposedChart
        data={rows}
        syncId="analytics-time"
        margin={{ top: 22, right: 18, left: -6, bottom: 4 }}
      >
        <defs>
          <linearGradient id={`metric-fill-${metric}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={selected.color} stopOpacity={0.24} />
            <stop offset="100%" stopColor={selected.color} stopOpacity={0.02} />
          </linearGradient>
        </defs>
        <CartesianGrid stroke="#e5edef" vertical={false} />
        <XAxis
          dataKey="timestamp"
          type="number"
          domain={['dataMin', 'dataMax']}
          scale="time"
          tickFormatter={(value) =>
            new Intl.DateTimeFormat('en-PH', {
              month: data.window.range === '30d' ? 'short' : undefined,
              day: data.window.range === '30d' ? 'numeric' : undefined,
              hour: data.window.range === '30d' ? undefined : 'numeric',
              timeZone: MANILA_TIMEZONE,
            }).format(new Date(value))
          }
          tick={{ fill: '#6f8590', fontSize: 11 }}
          axisLine={false}
          tickLine={false}
          minTickGap={28}
        />
        <YAxis
          domain={domain}
          tick={{ fill: '#6f8590', fontSize: 11 }}
          axisLine={false}
          tickLine={false}
          width={58}
          tickFormatter={(value) => Number(value).toFixed(1)}
        />
        <Tooltip content={<ChartTooltip unit={selected.unit} />} />
        <ThresholdOverlays
          segments={data.threshold_segments}
          metric={metric}
          domain={domain}
        />
        {showPrevious && (
          <Line
            type="monotone"
            dataKey="previous"
            name="Previous period"
            stroke="#8da0a8"
            strokeWidth={1.5}
            strokeDasharray="6 5"
            dot={false}
            connectNulls={false}
          />
        )}
        <Area
          type="monotone"
          dataKey="fleet"
          name="Fleet average"
          stroke={selected.color}
          strokeWidth={data.tank_series.length ? 1.8 : 2.6}
          strokeDasharray={data.tank_series.length ? '7 4' : undefined}
          fill={data.tank_series.length ? 'transparent' : `url(#metric-fill-${metric})`}
          connectNulls={false}
          activeDot={{ r: 5 }}
        />
        {data.tank_series.map((tank, index) => (
          <Line
            key={tank.tank_id}
            type="monotone"
            dataKey={`tank-${tank.tank_id}`}
            name={tank.tank_name}
            stroke={tankColors[index]}
            strokeWidth={2}
            dot={false}
            connectNulls={false}
          />
        ))}
        {alerts.map((event) => (
          <ReferenceDot
            key={event.id}
            x={new Date(event.timestamp).getTime()}
            y={event.value!}
            ifOverflow="extendDomain"
            shape={(props) => (
              <AlertMarker {...props} event={event} onOpen={onAlert} />
            )}
          />
        ))}
      </ComposedChart>
    </ResponsiveContainer>
  );
}

function MetricPreview({
  data,
  metric,
  onSelect,
}: {
  data: AnalyticsResponse;
  metric: MetricKey;
  onSelect: () => void;
}) {
  const option = metricOptions.find((item) => item.key === metric)!;
  const rows = chartRows(data, metric);
  const hasData = rows.some((row) => row.fleet != null);
  return (
    <button
      className="metric-preview"
      type="button"
      onClick={onSelect}
      aria-label={`Show ${option.label} as primary metric`}
    >
      <span>
        <strong>{option.label}</strong>
        <small>{data.stats[metric].average?.toFixed(2) ?? 'No data'} {option.unit}</small>
      </span>
      {hasData ? (
        <ResponsiveContainer width="100%" height={72}>
          <LineChart data={rows} syncId="analytics-time">
            <XAxis dataKey="timestamp" type="number" domain={['dataMin', 'dataMax']} hide />
            <YAxis domain={['auto', 'auto']} hide />
            <Tooltip content={() => null} cursor={{ stroke: '#9aabb2', strokeWidth: 1 }} />
            <Line
              dataKey="fleet"
              type="monotone"
              stroke={option.color}
              strokeWidth={1.8}
              dot={false}
              connectNulls={false}
            />
          </LineChart>
        </ResponsiveContainer>
      ) : (
        <span className="preview-empty">No readings</span>
      )}
    </button>
  );
}

export default function AnalyticsPage() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const [tankSearch, setTankSearch] = useState('');
  const range = ranges.includes(searchParams.get('range') as AnalyticsRange)
    ? searchParams.get('range') as AnalyticsRange
    : '24h';
  const bucket = buckets.includes(searchParams.get('bucket') as AnalyticsBucket)
    ? searchParams.get('bucket') as AnalyticsBucket
    : 'auto';
  const metric = validMetric(searchParams.get('metric'))
    ? searchParams.get('metric') as MetricKey
    : 'temperature';
  const compareMetric = validMetric(searchParams.get('compare')) &&
    searchParams.get('compare') !== metric
    ? searchParams.get('compare') as MetricKey
    : null;
  const showPrevious = searchParams.get('previous') === '1';
  const rawTankIds = (searchParams.get('tanks') ?? '')
    .split(',')
    .filter(Boolean)
    .map(Number)
    .filter((value) => Number.isInteger(value) && value > 0)
    .slice(0, 3);
  const defaultEnd = localInputValue(new Date());
  const defaultStart = localInputValue(new Date(Date.now() - 86_400_000));
  const customStart = searchParams.get('start') ?? defaultStart;
  const customEnd = searchParams.get('end') ?? defaultEnd;
  const selectedDurationSeconds = range === 'custom'
    ? (new Date(customEnd).getTime() - new Date(customStart).getTime()) / 1_000
    : { '24h': 86_400, '7d': 604_800, '30d': 2_592_000 }[range];
  const selectedBucketSeconds =
    { '15m': 900, '1h': 3_600, '6h': 21_600, '1d': 86_400 }[
      bucket as Exclude<AnalyticsBucket, 'auto'>
    ];
  const validBucket =
    bucket === 'auto' ||
    (
      Number.isFinite(selectedDurationSeconds) &&
      selectedDurationSeconds > 0 &&
      Math.ceil(selectedDurationSeconds / selectedBucketSeconds) <= 1_000
    );

  const tanksQuery = useQuery({
    queryKey: ['analytics-tanks'],
    queryFn: () => api<Array<{ id: number; name: string; }>>('/tanks'),
  });
  const knownTankIds = new Set((tanksQuery.data ?? []).map((tank) => tank.id));
  const selectedTankIds = tanksQuery.isSuccess
    ? rawTankIds.filter((tankId) => knownTankIds.has(tankId))
    : rawTankIds;

  const setState = (changes: Record<string, string | null>) => {
    setSearchParams((current) => {
      const next = new URLSearchParams(current);
      Object.entries(changes).forEach(([key, value]) => {
        if (value == null || value === '') next.delete(key);
        else next.set(key, value);
      });
      return next;
    }, { replace: true });
  };

  useEffect(() => {
    if (!tanksQuery.isSuccess) return;
    const normalized = selectedTankIds.join(',');
    if (normalized !== rawTankIds.join(',')) {
      setState({ tanks: normalized || null });
    }
  // setState intentionally reads the latest URL state.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tanksQuery.isSuccess, selectedTankIds.join(','), rawTankIds.join(',')]);

  useEffect(() => {
    const changes: Record<string, string | null> = {};
    if (searchParams.has('range') && !ranges.includes(searchParams.get('range') as AnalyticsRange)) {
      changes.range = null;
    }
    if (searchParams.has('bucket') && !buckets.includes(searchParams.get('bucket') as AnalyticsBucket)) {
      changes.bucket = null;
    }
    if (searchParams.has('metric') && !validMetric(searchParams.get('metric'))) {
      changes.metric = null;
    }
    if (searchParams.has('compare') && !validMetric(searchParams.get('compare'))) {
      changes.compare = null;
    }
    if (!validBucket) changes.bucket = null;
    if (Object.keys(changes).length) setState(changes);
  // Normalize only when parsed URL state changes.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [range, bucket, metric, compareMetric, validBucket]);

  const requestQuery = useMemo(() => {
    const params = new URLSearchParams({ range, bucket });
    if (range === 'custom') {
      const parsedStart = new Date(customStart);
      const parsedEnd = new Date(customEnd);
      if (Number.isFinite(parsedStart.getTime())) params.set('start', parsedStart.toISOString());
      if (Number.isFinite(parsedEnd.getTime())) params.set('end', parsedEnd.toISOString());
    }
    selectedTankIds.forEach((tankId) => params.append('tank_id', String(tankId)));
    return params.toString();
  }, [range, bucket, customStart, customEnd, selectedTankIds.join(',')]);

  const validCustomRange =
    range !== 'custom' ||
    (
      Number.isFinite(new Date(customStart).getTime()) &&
      Number.isFinite(new Date(customEnd).getTime()) &&
      new Date(customStart) < new Date(customEnd) &&
      new Date(customEnd).getTime() - new Date(customStart).getTime() <= 30 * 86_400_000
    );
  const query = useQuery({
    queryKey: ['analytics', requestQuery],
    queryFn: () => api<AnalyticsResponse>(`/analytics/fleet?${requestQuery}`),
    enabled: validCustomRange && validBucket && (!rawTankIds.length || tanksQuery.isSuccess),
  });
  const data = query.data;
  const selected = metricOptions.find((option) => option.key === metric)!;
  const stats = data?.stats[metric];
  const hasAnyReadings = data?.fleet_series.some((point) =>
    metrics.some((key) => point.values[key] != null),
  ) ?? false;

  const openAlert = (event: AnalyticsAlert) => {
    const timestamp = new Date(event.timestamp);
    const after = new Date(timestamp.getTime() - 15 * 60_000).toISOString();
    const before = new Date(timestamp.getTime() + 15 * 60_000).toISOString();
    navigate(
      `/admin/alerts?tank_id=${event.tank_id}&parameter=${event.parameter}` +
      `&severity=${event.severity}&created_after=${encodeURIComponent(after)}` +
      `&created_before=${encodeURIComponent(before)}`,
    );
  };

  const toggleTank = (tankId: number) => {
    const next = selectedTankIds.includes(tankId)
      ? selectedTankIds.filter((value) => value !== tankId)
      : [...selectedTankIds, tankId].slice(0, 3);
    setState({ tanks: next.join(',') || null });
  };

  const exportData = () => {
    if (!data || !hasAnyReadings) return;
    const content = analyticsCsv(data, compareMetric ? [metric, compareMetric] : [metric]);
    const blob = new Blob([`\uFEFF${content}`], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download =
      `aqualogic-analytics-${range}-${metric}-${new Date().toISOString().slice(0, 10)}-Asia-Manila.csv`;
    anchor.click();
    URL.revokeObjectURL(url);
  };

  const lowest = data?.uptime.find(
    (item) => item.tank_id === data.insights.lowest_uptime_tank_id,
  );
  const driverId = data?.insights.primary_driver_by_metric[metric];
  const driver = data?.tanks.find((tank) => tank.id === driverId);
  const metricChange = stats?.absolute_change;
  const currentThreshold = data
    ? activeThreshold(
        data.threshold_segments,
        metric,
        new Date(new Date(data.window.end).getTime() - 1).toISOString(),
      )
    : undefined;

  return (
    <section className="analytics-page">
      <PageHeader
        eyebrow="Performance"
        title="Fleet analytics"
        description="Diagnose water-quality trends, threshold events, and reporting health."
        actions={
          <button
            className="button button-secondary"
            type="button"
            onClick={exportData}
            disabled={!hasAnyReadings}
          >
            <Download size={16} /> Export CSV
          </button>
        }
      />

      <Panel className="analytics-controls">
        <div className="analytics-control-grid">
          <label className="field">
            <span>Timeframe</span>
            <select
              value={range}
              onChange={(event) => {
                const next = event.target.value as AnalyticsRange;
                setState({
                  range: next === '24h' ? null : next,
                  start: next === 'custom' ? customStart : null,
                  end: next === 'custom' ? customEnd : null,
                });
              }}
            >
              <option value="24h">Last 24 hours</option>
              <option value="7d">Last 7 days</option>
              <option value="30d">Last 30 days</option>
              <option value="custom">Custom range</option>
            </select>
          </label>
          <label className="field">
            <span>Resolution</span>
            <select
              value={bucket}
              onChange={(event) =>
                setState({ bucket: event.target.value === 'auto' ? null : event.target.value })
              }
            >
              <option value="auto">Automatic</option>
              <option
                value="15m"
                disabled={selectedDurationSeconds / 900 > 1_000}
              >
                15 minutes
              </option>
              <option
                value="1h"
                disabled={selectedDurationSeconds / 3_600 > 1_000}
              >
                Hourly
              </option>
              <option value="6h">6 hours</option>
              <option value="1d">Daily</option>
            </select>
          </label>
          <details className="tank-picker">
            <summary>
              <Layers3 size={15} />
              {selectedTankIds.length
                ? `${selectedTankIds.length} tank${selectedTankIds.length === 1 ? '' : 's'} selected`
                : 'Fleet average'}
            </summary>
            <div className="tank-picker-popover">
              <label className="tank-picker-search">
                <Search size={14} aria-hidden="true" />
                <input
                  type="search"
                  value={tankSearch}
                  onChange={(event) => setTankSearch(event.target.value)}
                  placeholder="Find a tank"
                />
              </label>
              <small>Select up to three tanks. Fleet average remains visible.</small>
              {(tanksQuery.data ?? [])
                .filter((tank) => tank.name.toLowerCase().includes(tankSearch.toLowerCase()))
                .map((tank) => (
                  <label key={tank.id}>
                    <input
                      type="checkbox"
                      checked={selectedTankIds.includes(tank.id)}
                      disabled={
                        selectedTankIds.length >= 3 && !selectedTankIds.includes(tank.id)
                      }
                      onChange={() => toggleTank(tank.id)}
                    />
                    <span>{tank.name}</span>
                  </label>
                ))}
            </div>
          </details>
          <label className="field compare-select">
            <span>Compare parameter</span>
            <select
              value={compareMetric ?? ''}
              onChange={(event) => setState({ compare: event.target.value || null })}
            >
              <option value="">None</option>
              {metricOptions
                .filter((option) => option.key !== metric)
                .map((option) => (
                  <option key={option.key} value={option.key}>{option.label}</option>
                ))}
            </select>
          </label>
          <label className="toggle-field analytics-previous-toggle">
            <input
              type="checkbox"
              checked={showPrevious}
              onChange={(event) => setState({ previous: event.target.checked ? '1' : null })}
            />
            <span aria-hidden="true" />
            <strong>Previous period</strong>
          </label>
        </div>
        {range === 'custom' && (
          <div className="custom-range-fields">
            <label className="field">
              <span>From</span>
              <input
                type="datetime-local"
                value={customStart}
                onChange={(event) => setState({ start: event.target.value })}
              />
            </label>
            <label className="field">
              <span>To</span>
              <input
                type="datetime-local"
                value={customEnd}
                onChange={(event) => setState({ end: event.target.value })}
              />
            </label>
            {!validCustomRange && (
              <p role="alert">Choose a valid range of no more than 30 days.</p>
            )}
          </div>
        )}
      </Panel>

      <div className="metric-tabs" role="tablist" aria-label="Water quality metric">
        {metricOptions.map((option) => (
          <button
            key={option.key}
            role="tab"
            aria-selected={metric === option.key}
            className={metric === option.key ? 'active' : ''}
            onClick={() =>
              setState({
                metric: option.key === 'temperature' ? null : option.key,
                compare: compareMetric === option.key ? null : compareMetric,
              })
            }
          >
            {option.label}
          </button>
        ))}
      </div>

      {!validCustomRange ? (
        <Panel>
          <EmptyState
            title="Invalid custom range"
            message="The end must be after the start and no more than 30 days later."
          />
        </Panel>
      ) : query.isLoading || (rawTankIds.length > 0 && tanksQuery.isLoading) ? (
        <Panel><LoadingState label="Building fleet analytics…" /></Panel>
      ) : query.isError ? (
        <Panel>
          <ErrorState message="Analytics could not be loaded." retry={() => query.refetch()} />
        </Panel>
      ) : !data?.tanks.length ? (
        <Panel>
          <EmptyState title="No tanks configured" message="Add a tank before analyzing the fleet." />
        </Panel>
      ) : data ? (
        <>
          <div className="analytics-stats">
            <div>
              <InfoLabel
                label="Fleet average"
                explanation="Average of all readings reported by all tanks in this period."
              />
              <strong>{stats?.average?.toFixed(2) ?? '—'} <em>{selected.unit}</em></strong>
              {showPrevious && (
                <em>
                  Previous {stats?.previous_average?.toFixed(2) ?? '—'} {selected.unit}
                </em>
              )}
            </div>
            <div>
              <InfoLabel
                label="Lowest reading"
                explanation="Lowest individual reading recorded in the selected period."
              />
              <strong>{stats?.minimum?.toFixed(2) ?? '—'} <em>{selected.unit}</em></strong>
            </div>
            <div>
              <InfoLabel
                label="Highest reading"
                explanation="Highest individual reading recorded in the selected period."
              />
              <strong>{stats?.maximum?.toFixed(2) ?? '—'} <em>{selected.unit}</em></strong>
            </div>
            <div>
              <InfoLabel
                label="Reporting uptime"
                explanation="Unique 30-second reporting intervals divided by expected intervals."
              />
              <strong>{data.uptime_comparison.current.toFixed(1)}%</strong>
              <em className={data.uptime_comparison.change < 0 ? 'trend-down' : 'trend-up'}>
                {data.uptime_comparison.change < 0 ? '↓' : '↑'}{' '}
                {Math.abs(data.uptime_comparison.change).toFixed(1)}% vs previous
              </em>
            </div>
          </div>

          <Panel
            title={`${selected.label} trend`}
            description={`Fleet context and selected tanks · ${selected.unit}`}
            className="chart-panel main-trend-panel"
            action={
              <div className="chart-legend" aria-label="Trend chart legend">
                <span><i className="legend-line fleet-line" /> Fleet average</span>
                <span title="Configured warning bounds active at the end of this period">
                  <i className="legend-zone warning-zone" />
                  Warning limits {currentThreshold
                    ? boundLabel(
                        currentThreshold.warning_min,
                        currentThreshold.warning_max,
                        currentThreshold.unit,
                      )
                    : 'not configured'}
                </span>
                <span title="Configured critical bounds active at the end of this period">
                  <i className="legend-zone critical-zone" />
                  Critical limits {currentThreshold
                    ? boundLabel(
                        currentThreshold.critical_min,
                        currentThreshold.critical_max,
                        currentThreshold.unit,
                      )
                    : 'not configured'}
                </span>
                <span><i className="legend-dot warning-dot" /> Warning alert</span>
                <span><i className="legend-dot critical-dot" /> Critical alert</span>
              </div>
            }
          >
            <TrendChart
              data={data}
              metric={metric}
              showPrevious={showPrevious}
              onAlert={openAlert}
            />
          </Panel>

          {compareMetric && (
            <Panel
              title={`${metricOptions.find((item) => item.key === compareMetric)!.label} comparison`}
              description="Aligned timeframe with an independent scale"
              className="chart-panel comparison-panel"
            >
              <TrendChart
                data={data}
                metric={compareMetric}
                showPrevious={showPrevious}
                onAlert={openAlert}
                height={240}
              />
            </Panel>
          )}

          <div className="metric-previews" aria-label="Other water-quality parameters">
            {metricOptions
              .filter((option) => option.key !== metric)
              .map((option) => (
                <MetricPreview
                  key={option.key}
                  data={data}
                  metric={option.key}
                  onSelect={() =>
                    setState({
                      metric: option.key === 'temperature' ? null : option.key,
                      compare: compareMetric === option.key ? metric : compareMetric,
                    })
                  }
                />
              ))}
          </div>

          <Panel
            title="Operational insight"
            description="Deterministic summary of the selected period"
            className="insight-panel"
          >
            <div className="insight-grid">
              <div>
                <AlertTriangle size={18} aria-hidden="true" />
                <strong>{data.insights.alert_count}</strong>
                <span>threshold alert{data.insights.alert_count === 1 ? '' : 's'}</span>
              </div>
              <div>
                <CalendarRange size={18} aria-hidden="true" />
                <strong>{data.insights.reporting_gap_count}</strong>
                <span>contiguous reporting gap{data.insights.reporting_gap_count === 1 ? '' : 's'}</span>
              </div>
              <div>
                <strong>{lowest?.tank_name ?? 'Insufficient data'}</strong>
                <span>{lowest ? `lowest uptime at ${lowest.uptime}%` : 'no reporting tank to rank'}</span>
              </div>
              <div>
                <strong>{driver?.name ?? 'Insufficient data'}</strong>
                <span>{driver ? `largest ${selected.label.toLowerCase()} deviation` : 'no tank variance available'}</span>
              </div>
            </div>
            {metricChange != null && (
              <p className="period-comparison">
                {selected.label} changed {metricChange >= 0 ? 'up' : 'down'} by{' '}
                {Math.abs(metricChange).toFixed(2)} {selected.unit} from the previous period
                {stats?.percent_change != null
                  ? ` (${Math.abs(stats.percent_change).toFixed(1)}%)`
                  : ''}.
              </p>
            )}
          </Panel>

          <div className="analytics-grid">
            <Panel
              title="Alert frequency"
              description={`${data.alert_counts.warning} warning · ${data.alert_counts.critical} critical`}
              className="chart-panel"
              action={
                <div className="alert-legend" aria-label="Alert severity legend">
                  <span><i className="warning-swatch" /> Warning</span>
                  <span><i className="critical-swatch" /> Critical</span>
                </div>
              }
            >
              {data.alert_counts.warning + data.alert_counts.critical > 0 ? (
                <ResponsiveContainer width="100%" height={240}>
                  <BarChart data={data.alert_series} margin={{ top: 12, right: 8, left: -20 }}>
                    <CartesianGrid stroke="#e5edef" vertical={false} />
                    <XAxis
                      dataKey="timestamp"
                      tickFormatter={(value) =>
                        new Intl.DateTimeFormat('en-PH', {
                          hour: 'numeric',
                          month: range === '30d' ? 'short' : undefined,
                          day: range === '30d' ? 'numeric' : undefined,
                          timeZone: MANILA_TIMEZONE,
                        }).format(new Date(value))
                      }
                      tick={{ fill: '#6f8590', fontSize: 10 }}
                      axisLine={false}
                      tickLine={false}
                      minTickGap={24}
                    />
                    <YAxis allowDecimals={false} tick={{ fill: '#6f8590', fontSize: 10 }} axisLine={false} tickLine={false} />
                    <Tooltip labelFormatter={(value) => formatAnalyticsDate(String(value))} />
                    <Bar dataKey="warning" stackId="alerts" fill="#e99a21" radius={[3, 3, 0, 0]} />
                    <Bar dataKey="critical" stackId="alerts" fill="#dc5664" radius={[3, 3, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <EmptyState title="No alerts" message="No alerts were recorded in this range." />
              )}
            </Panel>
            <Panel
              title="Tank reporting uptime"
              description="Lowest uptime first · unique 30-second intervals"
            >
              <div className="uptime-list">
                {data.uptime.map((item) => (
                  <Link
                    className={`uptime-row uptime-${item.status}`}
                    key={item.tank_id}
                    to={`/admin/tanks?tank_id=${item.tank_id}`}
                  >
                    <span className="uptime-value-row">
                      <strong>{item.tank_name}</strong>
                      <small>{item.uptime}%</small>
                    </span>
                    <span
                      className="progress-track"
                      role="progressbar"
                      aria-label={`${item.tank_name} reporting uptime`}
                      aria-valuemin={0}
                      aria-valuemax={100}
                      aria-valuenow={item.uptime}
                    >
                      <i style={{ width: `${item.uptime}%` }} />
                    </span>
                    <span className="uptime-detail">
                      <b>{item.status.replace('_', ' ')}</b>
                      {item.reported_intervals.toLocaleString()} of{' '}
                      {item.expected_intervals.toLocaleString()} intervals
                    </span>
                  </Link>
                ))}
              </div>
            </Panel>
          </div>
        </>
      ) : null}
    </section>
  );
}
