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
  temperature: 'Temperature', ph: 'pH', tds: 'TDS',
};
const directions: Partial<Record<SpeciesSuitabilityCheck['reason'], string>> = {
  below_preferred_minimum: 'Below preferred minimum',
  above_preferred_maximum: 'Above preferred maximum',
};
const rank: Record<SpeciesSuitabilityStatus, number> = { attention: 0, unavailable: 1, suitable: 2 };
const statusLabels: Record<SpeciesSuitabilityStatus, string> = {
  suitable: 'Suitable',
  attention: 'Needs attention',
  unavailable: 'Insufficient data',
};
const statusDescriptions: Record<SpeciesSuitabilityStatus, string> = {
  suitable: 'Supported readings are within the configured species preferences.',
  attention: 'One or more supported readings are outside the preferred range.',
  unavailable: 'A fresh reading or species preference is missing for a complete comparison.',
};

function visibleSpeciesStatus(species: SpeciesSuitabilityResponse['species'][number]): SpeciesSuitabilityStatus {
  const configuredChecks = species.checks.filter((check) => check.configured);
  if (configuredChecks.some((check) => check.status === 'attention')) return 'attention';
  if (configuredChecks.some((check) => check.status === 'unavailable')) return 'unavailable';
  return configuredChecks.length ? 'suitable' : 'unavailable';
}

export function CareStatusChip({ status }: { status: SpeciesSuitabilityStatus }) {
  return <span className={`care-status care-status-${status}`}>{statusLabels[status]}</span>;
}

export function SpeciesCarePanel({ result, loading, error, retry }: {
  result?: SpeciesSuitabilityResponse; loading: boolean; error: boolean; retry: () => void;
}) {
  const [filter, setFilter] = useState<'all' | SpeciesSuitabilityStatus>('all');
  const evaluatedSpecies = (result?.species ?? []).map((species) => ({
    species,
    status: visibleSpeciesStatus(species),
  }));
  const visibleOverallStatus = evaluatedSpecies.some((item) => item.status === 'attention')
    ? 'attention'
    : evaluatedSpecies.some((item) => item.status === 'unavailable')
      ? 'unavailable'
      : evaluatedSpecies.length
        ? 'suitable'
        : 'unavailable';
  const entries = evaluatedSpecies
    .filter((item) => filter === 'all' || item.status === filter)
    .sort((left, right) => rank[left.status] - rank[right.status] || left.species.common_name.localeCompare(right.species.common_name));
  return <section className="species-care" aria-labelledby="species-care-title">
    <div className="species-care-heading"><div><h2 id="species-care-title">Species Care</h2><p>Compare assigned species preferences with the tank’s latest supported readings.</p></div>{result && <div className="species-care-status"><CareStatusChip status={visibleOverallStatus} /><small>{statusDescriptions[visibleOverallStatus]}</small></div>}</div>
    {loading ? <LoadingState label="Checking species care…" /> : error ? <ErrorState message="Species care could not be loaded." retry={retry} /> : !result ? null : result.summary_reason === 'no_species_assigned' ? <p className="care-empty">Assign a species to start a care-range evaluation.</p> : <>
      <div className="segmented care-filter" aria-label="Species care filter">{(['all', 'attention', 'suitable', 'unavailable'] as const).map((value) => <button type="button" className={filter === value ? 'active' : ''} onClick={() => setFilter(value)} key={value}>{value === 'all' ? 'All' : value}</button>)}</div>
      <p className="care-reading">{result.reading ? `Comparison reading: ${formatDate(result.reading.timestamp)}${result.reading.freshness === 'stale' ? ' — stale; results may be outdated' : ' — current'}` : 'No current reading is available.'}</p>
      {entries.length ? <div className="care-species-list">{entries.map(({ species, status }) => {
        const checks = species.checks;
        const attention = checks.filter((check) => check.status === 'attention');
        const displayed = status === 'suitable' ? [] : attention.length ? attention : checks;
        const configuredCount = checks.filter((check) => check.configured).length;
        return <article className="care-species" key={species.fish_species_id}><div className="care-species-heading"><div><strong>{species.common_name}</strong><small>{species.scientific_name}</small></div><CareStatusChip status={status} /></div>
          {status === 'suitable' ? <p className="care-summary">Suitable across {configuredCount} configured {configuredCount === 1 ? 'check' : 'checks'}.</p> : <div className="care-check-list">{displayed.map((check) => <div className={`care-check care-check-${check.status}`} key={check.parameter}><div><strong>{labels[check.parameter]}</strong><span>{check.configured ? preferredRange(check) : 'Not configured'}</span></div><div><span>Current {formatReading(check.current_value, check.unit, 1)}</span><small>{directions[check.reason] ? `${directions[check.reason]}. ${check.message}` : check.message}</small></div></div>)}</div>}
        </article>;
      })}</div> : <EmptyState title="No species match this filter" message="Choose another Species Care status." />}
    </>}
  </section>;
}
