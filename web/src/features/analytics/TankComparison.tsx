import { Fragment, useEffect, useState } from 'react';
import { ArrowRight, ChevronDown, ChevronUp } from 'lucide-react';
import { Link } from 'react-router-dom';
import { Panel } from '@/shared/components/admin-ui';
import { FindingEvidence, availabilityLabel, findingSummary, formatPercent, metricLabel } from './DecisionSupportInsights';
import { formatAnalyticsDate } from './utils';
import type { AnalyticsResponse, DecisionSupportCard, MetricKey } from './types';

type ComparisonTab = 'observations' | 'reporting' | 'alerts';
const tabs: Array<{ key: ComparisonTab; label: string }> = [
  { key: 'observations', label: 'Water quality' },
  { key: 'reporting', label: 'Data availability' },
  { key: 'alerts', label: 'Alerts' },
];

export function TankComparison({ data, metric, selectedFinding, onGraph }: {
  data: AnalyticsResponse; metric: MetricKey; selectedFinding: DecisionSupportCard | null;
  onGraph: (tankId: number, parameter: MetricKey) => void;
}) {
  const [tab, setTab] = useState<ComparisonTab>('observations');
  const [expanded, setExpanded] = useState(false);
  const [openTank, setOpenTank] = useState<number | null>(null);
  const insights = data.decision_support_insights;
  const cards = insights?.cards.filter((card) => card.parameter === metric) ?? [];
  const limits = insights?.limitations.filter((item) => item.parameter === metric) ?? [];
  const ids = [...new Set([...cards.map((card) => card.tank_id), ...limits.map((item) => item.tank_id)])];
  const rows = ids.map((id) => {
    const findings = cards.filter((card) => card.tank_id === id);
    const within = findings.find((card) => card.rule === 'within_range');
    const pattern = findings.find((card) => ['increasing', 'decreasing', 'little_change'].includes(card.rule));
    const recurrence = findings.find((card) => card.rule === 'repeated_alerts');
    const limitations = limits.filter((item) => item.tank_id === id);
    return { id, findings, within, pattern, recurrence, limitations,
      name: findings[0]?.tank_name ?? limitations[0]?.tank_name ?? `Tank #${id}`,
      changed: findings.some((card) => card.qualifications.some((item) => item.includes('bounds changed'))),
      uptime: data.uptime.find((item) => item.tank_id === id),
    };
  }).sort((a, b) => Number(a.within?.evidence.percent ?? 101) - Number(b.within?.evidence.percent ?? 101) || a.name.localeCompare(b.name) || a.id - b.id);

  const selectedRowIndex = rows.findIndex((row) => row.id === selectedFinding?.tank_id);
  useEffect(() => { setExpanded(false); setOpenTank(null); }, [metric, data.window.start, data.window.end]);
  useEffect(() => {
    if (selectedFinding && selectedFinding.parameter === metric) {
      setTab('observations');
      setOpenTank(selectedFinding.tank_id);
      setExpanded(selectedRowIndex >= 8);
    }
  }, [selectedFinding, metric, selectedRowIndex]);
  const count = tab === 'observations' ? rows.length : tab === 'reporting' ? data.uptime.length : data.alert_events.length;
  const visibleCount = expanded ? count : 8;

  return <Panel className="tank-comparison-panel" title="Tank comparison" description={`${metricLabel(metric)} by tank · data availability and alerts across the fleet`}>
    <div className="comparison-tabs" role="tablist" aria-label="Tank comparison view">
      {tabs.map((item) => <button key={item.key} id={`comparison-tab-${item.key}`} role="tab" aria-selected={tab === item.key} aria-controls="comparison-content" tabIndex={tab === item.key ? 0 : -1} onClick={() => { setTab(item.key); setExpanded(false); }} onKeyDown={(event) => {
        if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
        event.preventDefault();
        const index = tabs.findIndex((entry) => entry.key === tab);
        const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
        setTab(tabs[next].key); setExpanded(false);
        document.getElementById(`comparison-tab-${tabs[next].key}`)?.focus();
      }}>{item.label}<span>{item.key === 'observations' ? rows.length : item.key === 'reporting' ? data.uptime.length : data.alert_events.length}</span></button>)}
    </div>
    <div id="comparison-content" role="tabpanel" aria-labelledby={`comparison-tab-${tab}`}>
      <div className="comparison-table-scroll">
        {tab === 'observations' ? <table className="comparison-table">
          <caption className="sr-only">Tank water-quality data for {metricLabel(metric)}</caption>
          <thead><tr><th>Tank</th><th>Trend</th><th>Readings in range</th><th>Readings analyzed</th><th>Details</th></tr></thead>
          <tbody>{rows.slice(0, visibleCount).map((row) => <Fragment key={row.id}>
            <tr className={openTank === row.id ? 'comparison-row-selected' : ''}>
              <th scope="row"><Link to={`/admin/tanks/${row.id}`}>{row.name}</Link><small>Tank #{row.id} · {metricLabel(metric)}</small></th>
              <td data-label="Trend"><span className="comparison-pattern">{row.pattern ? findingSummary(row.pattern) : row.recurrence ? `${row.recurrence.evidence.count} alert records created` : row.limitations.some((item) => item.rule === 'direction_or_little_change' && item.reason.toLowerCase().includes('coverage')) ? 'Limited data' : 'Not enough data to describe a trend'}</span>{row.changed && <small className="comparison-bounds-note">Range changed</small>}</td>
              <td data-label="Readings in range">{row.within ? <strong className={`comparison-percent${Number(row.within.evidence.percent) < 100 ? ' comparison-percent-review' : ''}`}>{formatPercent(row.within.evidence.percent)}%</strong> : <><span className="comparison-unavailable">Unavailable</span><small>{row.limitations.some((item) => item.rule === 'within_range') ? 'Needs 30 readings over 1 h checked against an active range' : 'No range comparison for this period'}</small></>}</td>
              <td data-label="Readings analyzed">{row.within ? <><strong>{row.within.evidence.evaluable}</strong></> : <><strong>{row.findings[0]?.samples ?? row.limitations[0]?.samples ?? 0}</strong><small>recorded readings · limited data</small></>}</td>

              <td data-label="Details"><button className="analytics-text-action" aria-expanded={openTank === row.id} aria-label={`${openTank === row.id ? 'Hide' : 'View'} details for ${row.name}`} onClick={() => setOpenTank(openTank === row.id ? null : row.id)}>{openTank === row.id ? 'Hide details' : 'View details'}{openTank === row.id ? <ChevronUp size={14} /> : <ChevronDown size={14} />}</button></td>
            </tr>
            {openTank === row.id && <tr className="comparison-evidence-row"><td colSpan={5}>
              {row.changed && <p className="comparison-disclosure">Configured range changed during this period. A wider range does not establish improvement.</p>}
              <div className="comparison-evidence-grid">{(row.within ?? row.pattern ?? row.recurrence) && <FindingEvidence card={(row.within ?? row.pattern ?? row.recurrence)!} onGraph={onGraph} omitBoundsNote={row.changed} />}</div>
              {!row.findings.length && <p>Recorded readings: {row.limitations[0]?.samples ?? 'Unavailable'}. Not enough data for a qualified result.</p>}
              <button className="analytics-text-action" onClick={() => { const entry = document.getElementById('analytics-methodology') as HTMLDetailsElement | null; const technical = document.getElementById('analytics-technical') as HTMLDetailsElement | null; if (entry) entry.open = true; if (technical) technical.open = true; entry?.scrollIntoView({ behavior: 'smooth', block: 'start' }); }}>View technical details</button>
            </td></tr>}
          </Fragment>)}</tbody>
        </table> : tab === 'reporting' ? <table className="comparison-table">
          <caption className="sr-only">Fleet data availability</caption>
          <thead><tr><th>Tank</th><th>Data availability</th><th>Reporting details</th><th>Details</th></tr></thead>
          <tbody>{data.uptime.slice(0, visibleCount).map((item) => <tr key={item.tank_id}><th scope="row"><Link to={`/admin/tanks/${item.tank_id}`}>{item.tank_name}</Link></th><td data-label="Data availability">{availabilityLabel(item.status)}</td><td data-label="Reporting details"><details><summary>View reporting details</summary><p>{formatPercent(item.uptime)}% · {item.reported_intervals.toLocaleString()} / {item.expected_intervals.toLocaleString()} expected receipt intervals</p><p>Previous period: {formatPercent(item.previous_uptime)}% · {item.previous_reported_intervals.toLocaleString()} reported intervals.</p><p>Unique 30-second intervals containing a received reading. Observation time is separate from receipt time.</p></details></td><td data-label="Details"><Link to={`/admin/tanks/${item.tank_id}`}>Review tank</Link></td></tr>)}</tbody>
        </table> : <table className="comparison-table">
          <caption className="sr-only">Fleet alert records created during the selected period</caption>
          <thead><tr><th>Tank</th><th>Parameter</th><th>Severity</th><th>Created</th><th>Record</th></tr></thead>
          <tbody>{data.alert_events.slice(0, visibleCount).map((item) => <tr key={item.id}><th scope="row">{item.tank_name}</th><td data-label="Parameter">{metricLabel(item.parameter)}</td><td data-label="Severity"><span className={`comparison-severity comparison-severity-${item.severity}`}>{item.severity}</span></td><td data-label="Created">{formatAnalyticsDate(item.timestamp)}</td><td data-label="Record"><Link className="analytics-text-action" to={`/admin/alerts?${new URLSearchParams({ tank_id: String(item.tank_id), parameter: item.parameter, created_after: data.window.start, created_before: data.window.end, alert_id: String(item.id) })}`}>Alert #{item.id}<ArrowRight size={13} /></Link></td></tr>)}</tbody>
        </table>}
      </div>
      {!count && <p className="comparison-empty">{tab === 'observations' ? insights ? 'Not enough water-quality data for this parameter and period.' : 'Water-quality findings are unavailable. Data availability and alerts remain available.' : tab === 'reporting' ? 'No reporting data available.' : 'No alert records created in this period.'}</p>}
      <div className="comparison-footer">
        {count > 8 && <button className="analytics-text-action" aria-expanded={expanded} onClick={() => setExpanded(!expanded)}>{expanded ? 'Show fewer rows' : `Show ${count - 8} more rows`}</button>}
        <p className="analytics-context-note">{tab === 'observations' ? 'Percentages describe recorded readings, not time in range or aquarium health.' : tab === 'reporting' ? 'All tanks · missing reports can leave gaps in the picture. A recently received reading may have been observed earlier.' : 'Fleet scope · created alert records, not independent episodes or proof of recovery.'}</p>
      </div>
    </div>
  </Panel>;
}

export function AnalyticsResultsNotes({ data, metric }: { data: AnalyticsResponse; metric: MetricKey }) {
  const insights = data.decision_support_insights;
  return <details id="analytics-methodology" className="comparison-method"><summary>About these results</summary>
    <ul>
      <li>Trends describe recorded readings, not aquarium health or recovery.</li>
      <li>Missing or late reports can leave gaps in the picture.</li>
      <li>Readings use the configured range active when they were observed. A range change does not establish improvement.</li>
      <li>Water-quality history and data availability use different clocks.</li>
    </ul>
    <details id="analytics-technical"><summary>View technical details</summary>
      <p>Selected period: {formatAnalyticsDate(data.window.start)} – {formatAnalyticsDate(data.window.end)}. Alert/reporting chart interval: {data.window.bucket_seconds / 60} minutes.</p>
      <p>Water-quality history uses observation time in fixed 30-minute buckets aligned to :00 and :30. Edge buckets may be partial. Data availability uses receipt time: unique 30-second receipt intervals divided by expected intervals. Recent receipt does not establish observation freshness.</p>
      <p>Fleet availability: {data.uptime_comparison.current}% · Previous: {data.uptime_comparison.previous}% · Change: {data.uptime_comparison.change} percentage points. Contiguous receipt gaps: {data.insights.reporting_gap_count}.</p>
      <p>Alert counts describe created records, not independent episodes or recovery.</p>
      {insights && <><p>{insights.advisory}</p>
        {[metric, ...new Set(insights.cards.map((card) => card.parameter).concat(insights.limitations.map((item) => item.parameter as MetricKey)))].filter((item, index, all) => all.indexOf(item) === index).map((parameter) => <details key={parameter}><summary>{metricLabel(parameter)} technical evidence</summary>
          {insights.cards.filter((card) => card.parameter === parameter).map((card) => <article key={card.id}><h4>{card.tank_name} · {card.title}</h4><p>{card.explanation}</p><p>Observed: {card.observation_start ?? 'Unavailable'} – {card.observation_end ?? 'Unavailable'} · {card.samples} recorded readings</p><dl>{Object.entries(card.evidence).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd>{value}</dd></div>)}</dl>{card.qualifications.map((item) => <p key={item}>{item}</p>)}{!!card.checks.length && <ul>{card.checks.map((item) => <li key={item}>{item}</li>)}</ul>}{card.related_alert_ids.map((id) => <a key={id} href={`/admin/alerts?${new URLSearchParams({ tank_id: String(card.tank_id), parameter: card.parameter, created_after: card.window_start, created_before: card.window_end, alert_id: String(id) })}`}>Open alert #{id} </a>)}</article>)}
          {insights.limitations.filter((item) => item.parameter === parameter).map((item, index) => <p key={index}><strong>{item.tank_name}</strong>: {item.reason} · {item.samples} readings{item.excluded != null ? ` · ${item.excluded} excluded` : ''}{item.interval_coverage != null ? ` · ${item.interval_coverage}% completed interval coverage` : ''}</p>)}
        </details>)}
      </>}
    </details>
  </details>;
}
