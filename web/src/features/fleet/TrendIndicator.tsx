import type { CurrentParameterInsights } from '@/features/analytics/types';
import { formatRate, trendCopy } from '@/features/analytics/tank-insights/CopyFormatter';

export function TrendIndicator({ parameter }: { parameter?: CurrentParameterInsights }) {
  if (!parameter || !['rising', 'falling'].includes(parameter.trend.status) || parameter.trend.rate_per_hour == null) return null;
  if (!['temperature', 'ph'].includes(parameter.parameter)) return null;
  return <small className="needs-attention-trend" aria-label={`Derived: ${trendCopy(parameter.trend, parameter.unit)}`}>
    <span aria-hidden="true">{parameter.trend.status === 'rising' ? '↑' : '↓'}</span> {formatRate(parameter.trend.rate_per_hour)} {parameter.unit}/h
  </small>;
}
