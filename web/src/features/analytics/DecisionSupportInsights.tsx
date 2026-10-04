import { ArrowRight } from 'lucide-react';
import { Link } from 'react-router-dom';
import { Panel } from '@/shared/components/admin-ui';
import { formatAnalyticsDate } from './utils';
import { metricOptions, type AnalyticsResponse, type DecisionSupportCard, type MetricKey } from './types';

export const metricLabel = (parameter: MetricKey) => metricOptions.find((item) => item.key === parameter)?.label ?? parameter;
export const formatPercent = (value: number | string) => new Intl.NumberFormat('en', { maximumFractionDigits: 1 }).format(Number(value));

// Presentation only: use API-qualified findings, never infer stability from chart averages.
export function findingSummary(card: DecisionSupportCard) {
  const label = metricLabel(card.parameter);
  if (card.rule === 'within_range' && card.evidence.percent == null && card.evidence.outside == null) return `${label} range comparison unavailable`;
  if (card.rule === 'within_range') return Number(card.evidence.outside ?? (100 - Number(card.evidence.percent))) > 0
    ? `Some ${label === 'Temperature' || label === 'Turbidity' ? label.toLowerCase() : label} readings were outside the configured range`
    : `${label} readings were within the configured range`;
  if (card.rule === 'increasing') return `${label} increased`;
  if (card.rule === 'decreasing') return `${label} decreased`;
  if (card.rule === 'little_change') return `${label} showed little sustained change`;
  const count = Number(card.evidence.count);
  return `${count} ${label} alert${count === 1 ? '' : 's'} recorded`;
}
export function trendOverview(insights: AnalyticsResponse['decision_support_insights'], metric: MetricKey) {
  const cards = insights?.cards.filter((card) => card.parameter === metric) ?? [];
  const patterns = cards.filter((card) => ['increasing', 'decreasing', 'little_change'].includes(card.rule));
  return patterns.length ? 'Recorded readings support tank-level trends. See Key findings.' : 'Not enough data to describe a reliable trend.';
}

export function availabilityLabel(status: string) {
  return ({ healthy: 'Good data availability', degraded: 'Limited data', critical: 'Very limited data', no_data: 'No data' } as Record<string, string>)[status] ?? 'Unavailable';
}

export function FindingEvidence({ card, onGraph, omitBoundsNote = false }: { card: DecisionSupportCard; onGraph: (tankId: number, parameter: MetricKey) => void; omitBoundsNote?: boolean }) {
  const filters = new URLSearchParams({ tank_id: String(card.tank_id), parameter: card.parameter, created_after: card.window_start, created_before: card.window_end });
  return <article className="comparison-evidence-card">
    <h4>{metricLabel(card.parameter)} · tank evidence</h4>
    <dl className="tank-essential-evidence">
      <div><dt>Readings analyzed</dt><dd>{card.evidence.evaluable ?? card.evidence.usable_observations ?? card.samples}</dd></div>
      {card.rule === 'within_range' && <><div><dt>In range</dt><dd>{card.evidence.within}</dd></div><div><dt>Outside range</dt><dd>{card.evidence.outside}</dd></div></>}
      {Number(card.evidence.excluded ?? 0) > 0 && <div><dt>Excluded</dt><dd>{card.evidence.excluded}</dd></div>}
      <div><dt>Observed period</dt><dd>{card.observation_start && card.observation_end ? `${formatAnalyticsDate(card.observation_start)} – ${formatAnalyticsDate(card.observation_end)}` : 'Unavailable'}</dd></div>
    </dl>
    {!omitBoundsNote && card.qualifications.some((item) => item.includes('bounds changed')) && <p>Configured range changed during this period. A wider range does not establish improvement.</p>}
    {card.qualifications.some((item) => item.includes('delayed observations')) && <p>Some readings arrived late; these describe historical conditions.</p>}
    {!!card.checks.length && <details><summary>Suggested checks</summary><ul>{card.checks.map((item) => <li key={item}>{item}</li>)}</ul><p className="analytics-context-note">Confirm measurements and review the tank before acting.</p></details>}
    <div className="comparison-evidence-actions">
      <button className="button button-secondary" aria-label={`View ${card.parameter === 'ph' ? 'pH' : card.parameter} graph for ${card.tank_name}`} onClick={() => onGraph(card.tank_id, card.parameter)}>View graph</button>
      {!!card.related_alert_ids.length && <Link className="button button-secondary" to={`/admin/alerts?${filters}`}>View related alert records</Link>}
    </div>
    {!!card.related_alert_ids.length && <details><summary>Individual alert records</summary><div className="comparison-alert-links">{card.related_alert_ids.map((id) => <Link key={id} to={`/admin/alerts?${filters}&alert_id=${id}`}>Open alert #{id}</Link>)}</div></details>}
  </article>;
}

export function DecisionSupportInsights({ insights, metric, onEvidence }: {
  insights: AnalyticsResponse['decision_support_insights']; metric: MetricKey;
  onEvidence: (card: DecisionSupportCard) => void;
}) {
  if (!insights) return null;
  const relevant = insights.cards.filter((card) => card.parameter === metric);
  const groupKey = (card: DecisionSupportCard) => card.rule === 'within_range' ? Number(card.evidence.percent) < 100 ? 'outside' : 'within' : card.rule;
  const order = ['outside', 'increasing', 'decreasing', 'repeated_alerts', 'little_change', 'within'];
  const groups = order.map((key) => ({ key, cards: relevant.filter((card) => groupKey(card) === key).filter((card, index, cards) => cards.findIndex((other) => other.tank_id === card.tank_id) === index) })).filter((group, index, all) => group.cards.length && (group.key !== 'within' || !all.some((other) => other.key !== 'within' && other.cards.length))).slice(0, 3);
  const label = metricLabel(metric);
  return <Panel className="period-findings-panel" title="Key findings" description={`${label} · what stood out`}>
    <div className="period-findings-body">
      {!groups.length && <p className="analytics-context-note">No qualified findings for this period. Review the available readings below.</p>}
      {groups.map((group) => <article className="period-finding" key={group.key}>
        <h3>{group.key === 'outside' ? `${label} needs attention in ${group.cards.length} tank${group.cards.length === 1 ? '' : 's'}` : group.key === 'within' ? `${label} readings were in range in ${group.cards.length} tank${group.cards.length === 1 ? '' : 's'}` : group.key === 'repeated_alerts' ? `Repeated ${label} alerts in ${group.cards.length} tank${group.cards.length === 1 ? '' : 's'}` : `${label} ${group.key === 'little_change' ? 'showed little sustained change' : group.key === 'increasing' ? 'increased' : 'decreased'} in ${group.cards.length} tank${group.cards.length === 1 ? '' : 's'}`}</h3>
        <ul className="finding-tank-list">{group.cards.slice(0, 3).map((card) => <li key={card.id}><button className="analytics-text-action" onClick={() => onEvidence(card)} aria-label={`Review ${card.tank_name}`}>{card.tank_name}<ArrowRight size={13} aria-hidden="true" /></button>{card.qualifications.some((item) => item.includes('bounds changed')) && <small>Range changed</small>}</li>)}
          {group.cards.length > 3 && <li><details><summary>{group.cards.length - 3} more tanks</summary><ul>{group.cards.slice(3).map((card) => <li key={card.id}><button className="analytics-text-action" onClick={() => onEvidence(card)} aria-label={`Review ${card.tank_name}`}>{card.tank_name}</button>{card.qualifications.some((item) => item.includes('bounds changed')) && <small>Range changed</small>}</li>)}</ul></details></li>}
        </ul>
      </article>)}
      <button className="analytics-text-action period-all-findings" onClick={() => document.querySelector('.tank-comparison-panel')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}>Compare tanks <ArrowRight size={13} aria-hidden="true" /></button>
    </div>
  </Panel>;
}
