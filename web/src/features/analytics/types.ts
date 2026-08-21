export type AnalyticsRange = '24h' | '7d' | '30d' | 'custom';
export type AnalyticsBucket = 'auto' | '15m' | '1h' | '6h' | '1d';

export type MetricKey =
  | 'temperature'
  | 'ph'
  | 'turbidity'
  | 'dissolved_oxygen'
  | 'tds'
  | 'ammonia';

// Ammonia and dissolved oxygen remain in the API/data contract, but are
// intentionally excluded from the current web release because their scope is
// deferred.
export const metricOptions = [
  { key: 'temperature', label: 'Temperature', unit: '°C', color: '#0e9f97' },
  { key: 'ph', label: 'pH', unit: 'pH', color: '#4169a1' },
  { key: 'turbidity', label: 'Turbidity', unit: 'NTU', color: '#8a6a3d' },
  { key: 'tds', label: 'TDS', unit: 'ppm', color: '#7659a5' },
] as const satisfies ReadonlyArray<{ key: MetricKey; label: string; unit: string; color: string }>;
export type MetricValues = Record<MetricKey, number | null>;

export type AnalyticsPoint = {
  timestamp: string;
  values: MetricValues;
  sample_count: number;
  contributor_count: number;
};

export type TankSeries = {
  tank_id: number;
  tank_name: string;
  series: AnalyticsPoint[];
};

export type MetricStats = {
  average: number | null;
  minimum: number | null;
  maximum: number | null;
  previous_average: number | null;
  absolute_change: number | null;
  percent_change: number | null;
};

export type AnalyticsAlert = {
  id: number;
  tank_id: number;
  tank_name: string;
  reading_id: number | null;
  parameter: MetricKey;
  severity: 'warning' | 'critical';
  message: string;
  timestamp: string;
  value: number | null;
};

export type ThresholdSegment = {
  parameter: MetricKey;
  unit: string;
  start: string;
  end: string;
  warning_min: number | null;
  warning_max: number | null;
  critical_min: number | null;
  critical_max: number | null;
  enabled: boolean;
};

export type TankUptime = {
  tank_id: number;
  tank_name: string;
  uptime: number;
  previous_uptime: number;
  reported_intervals: number;
  previous_reported_intervals: number;
  expected_intervals: number;
  status: 'healthy' | 'degraded' | 'critical' | 'no_data';
};

export type AnalyticsResponse = {
  window: {
    range: AnalyticsRange;
    start: string;
    end: string;
    bucket_seconds: number;
    timezone: string;
  };
  tanks: Array<{ id: number; name: string; }>;
  fleet_series: AnalyticsPoint[];
  previous_fleet_series: AnalyticsPoint[];
  tank_series: TankSeries[];
  stats: Record<MetricKey, MetricStats>;
  alert_counts: { warning: number; critical: number; };
  alert_series: Array<{ timestamp: string; warning: number; critical: number; }>;
  alert_events: AnalyticsAlert[];
  threshold_segments: ThresholdSegment[];
  uptime: TankUptime[];
  uptime_comparison: {
    current: number;
    previous: number;
    change: number;
  };
  uptime_thresholds: { healthy: number; degraded: number; };
  insights: {
    alert_count: number;
    reporting_gap_count: number;
    lowest_uptime_tank_id: number | null;
    primary_driver_by_metric: Record<MetricKey, number | null>;
  };
};
