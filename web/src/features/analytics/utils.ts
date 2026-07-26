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
  const alertBuckets = new Map(
    data.alert_series.map((bucket) => [new Date(bucket.timestamp).getTime(), bucket]),
  );

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
