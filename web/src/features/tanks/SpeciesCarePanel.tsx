import type {
  SpeciesSuitabilityCheck,
  SpeciesSuitabilityResponse,
  SpeciesSuitabilityStatus,
} from '@/shared/api/models';
import { EmptyState, ErrorState, LoadingState } from '@/shared/components/admin-ui';
import { formatDate, formatReading } from '@/shared/utils/formatting';
import { useState } from 'react';

function preferredRange(check: SpeciesSuitabilityCheck) {
  const value = (number: number) => formatReading(number, check.unit, 1);
  if (check.preferred_min != null && check.preferred_max != null) return `${value(check.preferred_min)}–${value(check.preferred_max)}`;
  if (check.preferred_min != null) return `At least ${value(check.preferred_min)}`;
  if (check.preferred_max != null) return `At most ${value(check.preferred_max)}`;
  return 'Not configured';
}

const labels: Record<SpeciesSuitabilityCheck['parameter'], string> = {
  temperature: 'Temperature', ph: 'pH', dissolved_oxygen: 'Dissolved oxygen', tds: 'TDS',
};
const directions: Partial<Record<SpeciesSuitabilityCheck['reason'], string>> = {
  below_preferred_minimum: 'Below preferred minimum',
  above_preferred_maximum: 'Above preferred maximum',
};
const rank: Record<SpeciesSuitabilityStatus, number> = { attention: 0, unavailable: 1, suitable: 2 };

export function CareStatusChip({ status }: { status: SpeciesSuitabilityStatus }) {
  return <span className={`care-status care-status-${status}`}>{status}</span>;
}

export function SpeciesCarePanel({ result, loading, error, retry }: {
  result?: SpeciesSuitabilityResponse; loading: boolean; error: boolean; retry: () => void;
}) {
  const [filter, setFilter] = useState<'all' | SpeciesSuitabilityStatus>('all');
  const entries = (result?.species ?? [])
    .filter((species) => filter === 'all' || species.status === filter)
    .sort((left, right) => rank[left.status] - rank[right.status] || left.common_name.localeCompare(right.common_name));
  return <section className="species-care" aria-labelledby="species-care-title">
    <div className="species-care-heading"><div><h2 id="species-care-title">Species Care</h2><p>Preferred species ranges are separate from operational tank thresholds.</p></div>{result && <CareStatusChip status={result.status} />}</div>
    {loading ? <LoadingState label="Checking species care…" /> : error ? <ErrorState message="Species care could not be loaded." retry={retry} /> : !result ? null : result.summary_reason === 'no_species_assigned' ? <p className="care-empty">Assign a species to start a care-range evaluation.</p> : <>
      <div className="segmented care-filter" aria-label="Species care filter">{(['all', 'attention', 'suitable', 'unavailable'] as const).map((value) => <button type="button" className={filter === value ? 'active' : ''} onClick={() => setFilter(value)} key={value}>{value === 'all' ? 'All' : value}</button>)}</div>
      <p className="care-reading">{result.reading ? `Latest reading: ${formatDate(result.reading.timestamp)}${result.reading.freshness === 'stale' ? ' (stale)' : ''}` : 'No current reading is available.'}</p>
      {entries.length ? <div className="care-species-list">{entries.map((species) => {
        const attention = species.checks.filter((check) => check.status === 'attention');
        const displayed = species.status === 'suitable' ? [] : attention.length ? attention : species.checks;
        const configuredCount = species.checks.filter((check) => check.configured).length;
        return <article className="care-species" key={species.fish_species_id}><div className="care-species-heading"><div><strong>{species.common_name}</strong><small>{species.scientific_name}</small></div><CareStatusChip status={species.status} /></div>
          {species.status === 'suitable' ? <p className="care-summary">Suitable across {configuredCount} configured {configuredCount === 1 ? 'check' : 'checks'}.</p> : <div className="care-check-list">{displayed.map((check) => <div className={`care-check care-check-${check.status}`} key={check.parameter}><div><strong>{labels[check.parameter]}</strong><span>{check.configured ? preferredRange(check) : 'Not configured'}</span></div><div><span>Current {formatReading(check.current_value, check.unit, 1)}</span><small>{directions[check.reason] ? `${directions[check.reason]}. ${check.message}` : check.message}</small></div></div>)}</div>}
        </article>;
      })}</div> : <EmptyState title="No species match this filter" message="Choose another Species Care status." />}
    </>}
  </section>;
}
