import { Area, CartesianGrid, ComposedChart, Line, ReferenceArea, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import type { CurrentParameterInsights } from '../types';
import { metricOptions } from '../types';
import { formatAnalyticsDate } from '../utils';
import { formatNumber, projectionCopy, trendCopy } from './CopyFormatter';

export type RecentTrendRow = {
  timestamp: number; observed?: number; trend?: number;
  projectedLow?: number; projectedMid?: number; projectedHigh?: number;
  projectionRange?: [number, number];
};
export function recentTrendRows(parameter: CurrentParameterInsights): RecentTrendRow[] {
  const rows = new Map<number, RecentTrendRow>();
  const rowAt = (t: string) => {
    const timestamp = new Date(t).getTime();
    if (!rows.has(timestamp)) rows.set(timestamp, { timestamp });
    return rows.get(timestamp)!;
  };
  parameter.trend.fit_points.forEach((point) => { rowAt(point.t).observed = point.value; });
  [parameter.trend.fitted_start, parameter.trend.fitted_end].forEach((point) => {
    if (point) rowAt(point.t).trend = point.value;
  });
  if (parameter.parameter !== 'turbidity') parameter.projection.band.forEach((point) => {
    Object.assign(rowAt(point.t), { projectedLow: point.low, projectedMid: point.mid, projectedHigh: point.high, projectionRange: [point.low, point.high] });
  });
  return [...rows.values()].sort((a, b) => a.timestamp - b.timestamp);
}
export function RecentTrendTooltip({ active, payload, label, unit }: {
  active?: boolean; payload?: Array<{ payload: RecentTrendRow }>; label?: number; unit: string;
}) {
  const row = payload?.[0]?.payload;
  if (!active || !row || label == null) return null;
  const fields = [['Observed', row.observed], ['Trend', row.trend], ['Projected low', row.projectedLow], ['Projected mid', row.projectedMid], ['Projected high', row.projectedHigh]] as const;
  return <div className="analytics-tooltip"><strong>{formatAnalyticsDate(label)}</strong>
    {fields.map(([name, value]) => value == null ? null : <p key={name}>{name}: {formatNumber(value)} {unit}</p>)}
  </div>;
}
export function RecentTrendChart({ parameter, evaluatedAt }: { parameter: CurrentParameterInsights; evaluatedAt: string }) {
  const rows = recentTrendRows(parameter);
  const projected = parameter.parameter !== 'turbidity' && parameter.projection.band.length > 0;
  const species = parameter.species_range;
  const speciesBand = species.status === 'ok' && (species.min != null || species.max != null);
  const name = metricOptions.find((option) => option.key === parameter.parameter)!.label;
  const values = rows.flatMap((row) => [row.observed, row.trend, row.projectedLow, row.projectedHigh])
    .concat([parameter.warning_bounds?.min ?? undefined, parameter.warning_bounds?.max ?? undefined,
      species.status === 'ok' ? species.min ?? undefined : undefined, species.status === 'ok' ? species.max ?? undefined : undefined])
    .filter((value): value is number => value != null && Number.isFinite(value));
  const min = values.length ? Math.min(...values) : 0;
  const max = values.length ? Math.max(...values) : 1;
  const padding = Math.max((max - min) * .1, .1);
  const domain = [min - padding, max + padding];
  const now = new Date(evaluatedAt).getTime();
  const first = rows[0]?.timestamp ?? now;
  const last = Math.max(rows[rows.length - 1]?.timestamp ?? now, now);
  return <div className="tank-insights-chart" role="figure" aria-label={`${name}: ${trendCopy(parameter.trend, parameter.unit)}`}>
    <h3>{name} recent trend</h3>
    <ul className="tank-insights-legend" aria-label="Chart legend">
      <li>Observed (30-min median)</li><li>Trend (last 6 h)</li>
      {projected && <li>Projection if trend continues</li>}
      {speciesBand && <li>Species range</li>}
    </ul>
    {rows.length ? <ResponsiveContainer width="100%" height={300}>
      <ComposedChart data={rows} margin={{ top: 20, right: 25, bottom: 20, left: 10 }} accessibilityLayer>
        <CartesianGrid stroke="var(--border)" />
        <XAxis type="number" dataKey="timestamp" scale="time" domain={[first, last]} tickFormatter={(t: number) => formatAnalyticsDate(t)} />
        <YAxis domain={domain} unit={parameter.unit} />
        <Tooltip content={<RecentTrendTooltip unit={parameter.unit} />} />
        {speciesBand && <ReferenceArea y1={species.min ?? domain[0]} y2={species.max ?? domain[1]} fill="var(--surface-soft)" stroke="var(--border)" label="Species range" />}
        {(['min', 'max'] as const).map((side) => parameter.warning_bounds?.[side] == null ? null :
          <ReferenceLine key={side} y={parameter.warning_bounds[side]!} stroke="var(--warning)" strokeDasharray="4 4" label={`${side === 'min' ? 'Lower' : 'Upper'} warning bound`} />)}
        <ReferenceLine x={now} label="Now" stroke="var(--muted)" />
        <Line dataKey="observed" name="Observed (30-min median)" stroke="var(--text)" dot isAnimationActive={false} connectNulls />
        <Line dataKey="trend" name="Trend (last 6 h)" stroke="var(--muted)" strokeDasharray="6 4" dot={false} connectNulls isAnimationActive={false} />
        {projected && <Area dataKey="projectionRange" name="Projected low/high" fill="var(--border)" stroke="none" isAnimationActive={false} />}
        {projected && <Line dataKey="projectedMid" name="Projection if trend continues" stroke="var(--text)" strokeDasharray="2 4" dot={false} isAnimationActive={false} />}
      </ComposedChart>
    </ResponsiveContainer> : <p>No recent half-hour medians available</p>}
    {!projected && <p>{projectionCopy(parameter.projection, parameter.unit)}</p>}
  </div>;
}
