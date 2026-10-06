import type { CSSProperties } from 'react';
import { Activity, CircleHelp, Fish, Gauge, MoveRight, TrendingDown, TrendingUp, type LucideIcon } from 'lucide-react';
import type { CurrentLatest, CurrentParameterInsights } from '../types';
import { metricOptions } from '../types';
import { formatAnalyticsDate } from '../utils';
import { CategoryLabel } from './CategoryLabel';
import { formatNumber, headroomCopy, projectionCopy, speciesCopy, stabilityCopy, trendCopy } from './CopyFormatter';

type Tone = 'calm' | 'attention' | 'unknown';

const trendIcon: Record<CurrentParameterInsights['trend']['status'], LucideIcon> = {
  rising: TrendingUp, falling: TrendingDown, steady: MoveRight, uncertain: CircleHelp, insufficient_data: CircleHelp,
};

// Presentation only: tones restate API statuses and never add new judgments.
export function parameterTone(parameter: CurrentParameterInsights): Tone {
  const { projection, headroom, stability, species_range: species, trend } = parameter;
  if (projection.status === 'crossing_projected' || projection.status === 'already_outside' || headroom?.outside
    || stability.status === 'more_variable' || species.status === 'conflict') return 'attention';
  return trend.status === 'insufficient_data' ? 'unknown' : 'calm';
}

function DerivedRow({ icon: Icon, tone = 'calm', label, children }: { icon: LucideIcon; tone?: Tone; label: string; children: string }) {
  return <li className="insight-derived-row" data-tone={tone}>
    <Icon size={15} aria-hidden="true" />
    <span><span className="sr-only">{label}: </span>{children}</span>
  </li>;
}

export function ParameterSummaryCard({ parameter, latest, selected, onSelect }: {
  parameter: CurrentParameterInsights; latest: CurrentLatest; selected: boolean; onSelect: () => void;
}) {
  const option = metricOptions.find((item) => item.key === parameter.parameter)!;
  const { trend, headroom, stability, species_range: species, projection } = parameter;
  const projectionTone: Tone = projection.status === 'crossing_projected' || projection.status === 'already_outside' ? 'attention'
    : ['stale', 'insufficient_data', 'too_uncertain'].includes(projection.status) ? 'unknown' : 'calm';
  return <article className="tank-insights-card" data-tone={parameterTone(parameter)} data-selected={selected}
    style={{ '--metric-color': option.color } as CSSProperties} onClick={onSelect}>
    <h3><button type="button" className="tank-insights-card-title" aria-pressed={selected}>
      <span className="tank-insights-card-swatch" aria-hidden="true" />{option.label}
    </button></h3>

    <section className="insight-tier insight-tier-observed" aria-label="Observed">
      <CategoryLabel kind="observed" />
      {parameter.observed ? <>
        <p className="insight-observed-value">
          <strong>{formatNumber(parameter.observed.value)}</strong> <span>{parameter.unit}</span>
        </p>
        <p className="insight-observed-meta">
          <time dateTime={parameter.observed.observed_at}>{formatAnalyticsDate(parameter.observed.observed_at)}</time>
          {!latest.is_current && <span className="insight-not-current">not current</span>}
        </p>
      </> : <p className="insight-observed-meta">No readings available</p>}
    </section>

    <section className="insight-tier insight-tier-derived" aria-label="Derived">
      <CategoryLabel kind="derived" />
      <ul>
        <DerivedRow icon={trendIcon[trend.status]} label="Trend"
          tone={trend.status === 'insufficient_data' || trend.status === 'uncertain' ? 'unknown' : 'calm'}>{trendCopy(trend, parameter.unit)}</DerivedRow>
        <DerivedRow icon={Gauge} label="Headroom" tone={headroom?.outside ? 'attention' : 'calm'}>{headroomCopy(headroom, parameter.unit)}</DerivedRow>
        <DerivedRow icon={Activity} label="Stability"
          tone={stability.status === 'more_variable' ? 'attention' : stability.status.startsWith('insufficient') ? 'unknown' : 'calm'}>{stabilityCopy(stability)}</DerivedRow>
        <DerivedRow icon={Fish} label="Species range"
          tone={species.status === 'conflict' ? 'attention' : species.status === 'ok' ? 'calm' : 'unknown'}>{speciesCopy(species, parameter.unit)}</DerivedRow>
      </ul>
    </section>

    <section className="insight-tier insight-tier-projected" data-tone={projectionTone} aria-label="Projected">
      <CategoryLabel kind="projected" />
      <p>{projectionCopy(projection, parameter.unit)}</p>
    </section>
  </article>;
}
