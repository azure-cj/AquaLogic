import type { CSSProperties } from 'react';
import { Area, CartesianGrid, ComposedChart, Line, ReferenceArea, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import type { CurrentParameterInsights } from '../types';
import { metricOptions } from '../types';
import { formatAnalyticsDate } from '../utils';
import { CategoryGlyph } from './CategoryLabel';
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
    {fields.map(([name, value]) => value == null ? null : <p key={name} className={name.startsWith('Projected') ? 'recent-trend-tooltip-projected' : undefined}>{name}: {formatNumber(value)} {unit}</p>)}
  </div>;
}

const timeTick = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });

// Round, evenly spaced value ticks (1/2/5 steps) instead of arbitrary padded bounds.
export function niceAxis(low: number, high: number) {
  const raw = (high - low) / 4;
  const magnitude = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 5, 10].map((factor) => factor * magnitude).find((candidate) => candidate >= raw)!;
  const start = Math.floor(low / step) * step;
  const end = Math.ceil(high / step) * step;
  const ticks = Array.from({ length: Math.round((end - start) / step) + 1 }, (_, index) => Number((start + index * step).toFixed(6)));
  return { domain: [start, end] as [number, number], ticks };
}

export function RecentTrendChart({ parameter, evaluatedAt }: { parameter: CurrentParameterInsights; evaluatedAt: string }) {
  const rows = recentTrendRows(parameter);
  const projected = parameter.parameter !== 'turbidity' && parameter.projection.band.length > 0;
  const species = parameter.species_range;
  const speciesBand = species.status === 'ok' && (species.min != null || species.max != null);
  const option = metricOptions.find((item) => item.key === parameter.parameter)!;
  const color = option.color;
  const values = rows.flatMap((row) => [row.observed, row.trend, row.projectedLow, row.projectedHigh])
    .concat([parameter.warning_bounds?.min ?? undefined, parameter.warning_bounds?.max ?? undefined,
      species.status === 'ok' ? species.min ?? undefined : undefined, species.status === 'ok' ? species.max ?? undefined : undefined])
    .filter((value): value is number => value != null && Number.isFinite(value));
  const min = values.length ? Math.min(...values) : 0;
  const max = values.length ? Math.max(...values) : 1;
  const padding = Math.max((max - min) * .1, .1);
  const { domain, ticks } = niceAxis(min - padding, max + padding);
  const now = new Date(evaluatedAt).getTime();
  const first = rows[0]?.timestamp ?? now;
  const last = Math.max(rows[rows.length - 1]?.timestamp ?? now, now);
  return <div className="tank-insights-chart" role="figure" aria-label={`${option.label}: ${trendCopy(parameter.trend, parameter.unit)}`}
    style={{ '--metric-color': color } as CSSProperties}>
    <header className="tank-insights-chart-header">
      <div>
        <h3>{option.label} · last 6 h and next 3 h</h3>
        <p>30-minute medians, the fitted trend, and a conditional projection. Hover for values.</p>
      </div>
      <ul className="tank-insights-legend" aria-label="Chart legend">
        <li><CategoryGlyph kind="observed" />Observed (30-min median)</li>
        <li><CategoryGlyph kind="derived" />Trend (last 6 h)</li>
        {projected && <li className="legend-projected"><span className="legend-band" aria-hidden="true" /><CategoryGlyph kind="projected" />Projection if trend continues</li>}
        {speciesBand && <li className="legend-species"><span className="legend-swatch" aria-hidden="true" />Species range</li>}
        {parameter.warning_bounds && <li className="legend-warning"><CategoryGlyph kind="derived" />Warning bound</li>}
      </ul>
    </header>
    {rows.length ? <ResponsiveContainer width="100%" height={300}>
      <ComposedChart data={rows} margin={{ top: 16, right: 24, bottom: 4, left: 4 }} accessibilityLayer>
        <CartesianGrid stroke="var(--border)" strokeDasharray="3 3" vertical={false} />
        <XAxis type="number" dataKey="timestamp" scale="time" domain={[first, last]} tickFormatter={(t: number) => timeTick.format(t)}
          tick={{ fill: 'var(--muted)', fontSize: 11 }} tickLine={false} axisLine={{ stroke: 'var(--border)' }} minTickGap={36} />
        <YAxis domain={domain} ticks={ticks} tickFormatter={(v: number) => formatNumber(v)} width={56} unit={` ${parameter.unit}`}
          tick={{ fill: 'var(--muted)', fontSize: 11 }} tickLine={false} axisLine={false} />
        <Tooltip content={<RecentTrendTooltip unit={parameter.unit} />} />
        {speciesBand && <ReferenceArea y1={species.min ?? domain[0]} y2={species.max ?? domain[1]} fill="var(--normal)" fillOpacity={0.07} stroke="none" ifOverflow="extendDomain" />}
        {projected && <ReferenceArea x1={now} x2={last} fill="var(--metric-color)" fillOpacity={0.04} stroke="none" />}
        {(['min', 'max'] as const).map((side) => parameter.warning_bounds?.[side] == null ? null :
          <ReferenceLine key={side} y={parameter.warning_bounds[side]!} stroke="var(--warning)" strokeDasharray="5 4" strokeWidth={1.5}
            label={{ value: `${side === 'min' ? 'Lower' : 'Upper'} warning ${formatNumber(parameter.warning_bounds[side]!)}`, position: 'insideTopLeft', fill: 'var(--warning)', fontSize: 11 }} />)}
        <ReferenceLine x={now} stroke="var(--muted)" strokeWidth={1}
          label={{ value: 'Now', position: 'top', fill: 'var(--muted)', fontSize: 11, fontWeight: 700 }} />
        {projected && <Area dataKey="projectionRange" name="Projected low/high" fill="var(--metric-color)" fillOpacity={0.16} stroke="var(--metric-color)" strokeOpacity={0.35} strokeWidth={1} isAnimationActive={false} />}
        <Line dataKey="trend" name="Trend (last 6 h)" stroke="var(--muted)" strokeWidth={1.5} strokeDasharray="5 3" dot={false} connectNulls isAnimationActive={false} />
        {projected && <Line dataKey="projectedMid" name="Projection if trend continues" stroke="var(--metric-color)" strokeWidth={2} strokeDasharray="1.5 4" strokeLinecap="round" dot={false} isAnimationActive={false} />}
        <Line dataKey="observed" name="Observed (30-min median)" stroke="var(--metric-color)" strokeWidth={2.25}
          dot={{ r: 2.5, fill: 'var(--surface)', strokeWidth: 1.5 }} activeDot={{ r: 4 }} isAnimationActive={false} connectNulls />
      </ComposedChart>
    </ResponsiveContainer> : <p className="tank-insights-chart-empty">No recent half-hour medians available</p>}
    <p className="tank-insights-chart-note" data-projected={projected}>
      {projected ? 'The shaded band is a projection, not a measurement. ' : ''}{projectionCopy(parameter.projection, parameter.unit)}
    </p>
  </div>;
}
