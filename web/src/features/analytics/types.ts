export type AnalyticsRange = '24h' | '7d' | '30d';

export type AnalyticsPoint = {
  timestamp: string;
  temperature: number;
  ph: number;
  turbidity: number;
  dissolved_oxygen: number;
  tds: number;
  ammonia: number;
};

export type TankUptime = {
  tank_id: number;
  tank_name: string;
  uptime: number;
  previous_uptime: number;
  reported_intervals: number;
  previous_reported_intervals: number;
  expected_intervals: number;
};

export type AnalyticsResponse = {
  range: AnalyticsRange;
  series: AnalyticsPoint[];
  alert_counts: { warning: number; critical: number; };
  alert_series: Array<{ timestamp: string; warning: number; critical: number; }>;
  uptime: TankUptime[];
  uptime_comparison: {
    current: number;
    previous: number;
    change: number;
  };
};

export const metricOptions = [
  { key: 'temperature', label: 'Temperature', unit: '°C', color: '#0e9f97' },
  { key: 'ph', label: 'pH', unit: 'pH', color: '#4169a1' },
  { key: 'turbidity', label: 'Turbidity', unit: 'NTU', color: '#8a6a3d' },
  { key: 'dissolved_oxygen', label: 'Dissolved oxygen', unit: 'mg/L', color: '#2877a5' },
  { key: 'tds', label: 'TDS', unit: 'ppm', color: '#7659a5' },
  { key: 'ammonia', label: 'Ammonia', unit: 'ppm', color: '#dc5664' },
] as const;

export type MetricKey = (typeof metricOptions)[number]['key'];
