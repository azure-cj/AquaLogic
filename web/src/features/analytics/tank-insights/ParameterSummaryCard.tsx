import type { CurrentLatest, CurrentParameterInsights } from '../types';
import { metricOptions } from '../types';
import { formatAnalyticsDate } from '../utils';
import { formatNumber, headroomCopy, projectionCopy, speciesCopy, stabilityCopy, trendCopy } from './CopyFormatter';

export function ParameterSummaryCard({ parameter, latest, selected, onSelect }: {
  parameter: CurrentParameterInsights; latest: CurrentLatest; selected: boolean; onSelect: () => void;
}) {
  const name = metricOptions.find((option) => option.key === parameter.parameter)!.label;
  return <article className="tank-insights-card" onClick={onSelect}>
    <h3><button type="button" className="button button-secondary" aria-pressed={selected}>{name}</button></h3>
    <div><span className="status-badge">Observed</span>
      {parameter.observed ? <p>{formatNumber(parameter.observed.value)} {parameter.unit}<br />
        <time dateTime={parameter.observed.observed_at}>{formatAnalyticsDate(parameter.observed.observed_at)}</time>
        {!latest.is_current && <><br /><span>not current</span></>}
      </p> : <p>No readings available</p>}
    </div>
    <div><span className="status-badge">Derived</span>
      <p>{trendCopy(parameter.trend, parameter.unit)}</p>
      <p>{headroomCopy(parameter.headroom, parameter.unit)}</p>
      <p>{stabilityCopy(parameter.stability)}</p>
      <p>{speciesCopy(parameter.species_range, parameter.unit)}</p>
    </div>
    <div><span className="status-badge">Projected</span><p>{projectionCopy(parameter.projection, parameter.unit)}</p></div>
  </article>;
}
