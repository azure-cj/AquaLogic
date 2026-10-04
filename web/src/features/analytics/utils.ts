import type {
  AnalyticsPoint,
  AnalyticsResponse,
  MetricKey,
  ThresholdSegment,
} from './types';
import { metricOptions } from './types';

export const MANILA_TIMEZONE = 'Asia/Manila';

export function formatAnalyticsDate(value: string | number) {
  return new Intl.DateTimeFormat('en-PH', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: MANILA_TIMEZONE,
  }).format(new Date(value));
}

export function formatAnalyticsBucketRange(
  value: string | number,
  bucketSeconds: number,
  timezone = MANILA_TIMEZONE,
) {
  const start = new Date(value);
  const end = new Date(start.getTime() + bucketSeconds * 1_000);
  const dateKey = (date: Date) => new Intl.DateTimeFormat('en', {
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    timeZone: timezone,
  }).format(date);
  const startLabel = new Intl.DateTimeFormat('en-PH', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: timezone,
  }).format(start);
  const endLabel = new Intl.DateTimeFormat('en-PH', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: timezone,
  }).format(end);
  const endTime = new Intl.DateTimeFormat('en-PH', {
    timeStyle: 'short',
    timeZone: timezone,
  }).format(end);

  return `${startLabel} – ${dateKey(start) === dateKey(end) ? endTime : endLabel}`;
}

export function activeThreshold(
  segments: ThresholdSegment[],
  metric: MetricKey,
  timestamp: string,
) {
  const value = new Date(timestamp).getTime();
  return segments.find(
    (segment) =>
      segment.parameter === metric &&
      value >= new Date(segment.start).getTime() &&
      value < new Date(segment.end).getTime(),
  );
}

export type ThresholdZone = {
  tone: 'warning' | 'critical';
  y1: number;
  y2: number;
};

export function thresholdZones(
  segment: ThresholdSegment,
  domain: [number, number],
): ThresholdZone[] {
  if (!segment.enabled) return [];
  const zones: ThresholdZone[] = [];
  if (segment.critical_min != null) {
    zones.push({ tone: 'critical', y1: domain[0], y2: segment.critical_min });
  }
  if (segment.warning_min != null) {
    zones.push({
      tone: 'warning',
      y1: segment.critical_min ?? domain[0],
      y2: segment.warning_min,
    });
  }
  if (segment.warning_max != null) {
    zones.push({
      tone: 'warning',
      y1: segment.warning_max,
      y2: segment.critical_max ?? domain[1],
    });
  }
  if (segment.critical_max != null) {
    zones.push({ tone: 'critical', y1: segment.critical_max, y2: domain[1] });
  }
  return zones.filter((zone) => zone.y1 < zone.y2);
}

const escapeCsv = (value: unknown) => {
  const string = value == null ? '' : String(value);
  return /[",\r\n]/.test(string) ? `"${string.replaceAll('"', '""')}"` : string;
};

export function analyticsCsv(
  data: AnalyticsResponse,
  metrics: MetricKey[],
) {
  const columns = [
    'timestamp_utc',
    'timezone',
    'scope',
    'threshold_scope',
    'threshold_tank_id',
    'tank_id',
    'tank_name',
    'metric',
    'unit',
    'value',
    'sample_count',
    'contributor_count',
    'warning_min',
    'warning_max',
    'critical_min',
    'critical_max',
    'warning_alerts',
    'critical_alerts',
  ];
  const rows: unknown[][] = [columns];
  const alertBuckets = new Map<number, { warning: number; critical: number }>();
  const bucketMilliseconds = data.window.water_quality_bucket_seconds * 1_000;
  data.alert_events.forEach((event) => {
    const eventTime = new Date(event.timestamp).getTime();
    const bucketTime = Math.floor(eventTime / bucketMilliseconds) * bucketMilliseconds;
    const bucket = alertBuckets.get(bucketTime) ?? { warning: 0, critical: 0 };
    bucket[event.severity] += 1;
    alertBuckets.set(bucketTime, bucket);
  });

  const addSeries = (
    scope: string,
    tankId: number | '',
    tankName: string,
    series: AnalyticsPoint[],
  ) => {
    series.forEach((point) => {
      const alert = alertBuckets.get(new Date(point.timestamp).getTime());
      metrics.forEach((metric) => {
        const option = metricOptions.find((item) => item.key === metric)!;
        const threshold = activeThreshold(data.threshold_segments, metric, point.timestamp);
        rows.push([
          point.timestamp,
          data.window.timezone,
          scope,
          data.threshold_scope ?? 'shared',
          data.threshold_tank_id ?? '',
          tankId,
          tankName,
          metric,
          option.unit,
          point.values[metric],
          point.sample_count,
          point.contributor_count,
          threshold?.warning_min,
          threshold?.warning_max,
          threshold?.critical_min,
          threshold?.critical_max,
          alert?.warning ?? 0,
          alert?.critical ?? 0,
        ]);
      });
    });
  };

  addSeries('fleet', '', 'Fleet average', data.fleet_series);
  data.tank_series.forEach((tank) =>
    addSeries('tank', tank.tank_id, tank.tank_name, tank.series),
  );
  return rows.map((row) => row.map(escapeCsv).join(',')).join('\r\n');
}
