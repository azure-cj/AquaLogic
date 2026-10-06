import { ChevronRight } from 'lucide-react';
import { Link } from 'react-router-dom';
import type { CurrentInsightsResponse } from '@/features/analytics/types';
import { metricOptions } from '@/features/analytics/types';
import { CategoryLabel } from '@/features/analytics/tank-insights/CategoryLabel';
import { crossingTimeCopy, speciesCopy, stabilityCopy } from '@/features/analytics/tank-insights/CopyFormatter';
import type { FleetTank } from '@/shared/api/models';
import { EmptyState, LoadingState, Panel } from '@/shared/components/admin-ui';

export type AttentionRow = { key: string; tankId: number; category: 'Observed' | 'Projected' | 'Derived'; copy: string;
  tone: 'critical' | 'offline' | 'projected' | 'derived' };
export function attentionRows(tanks: FleetTank[], insights?: CurrentInsightsResponse): AttentionRow[] {
  const rows: AttentionRow[] = [];
  for (const status of ['critical', 'offline'] as const) {
    tanks.filter((tank) => tank.status === status).forEach((tank) => {
      const alerts = tank.active_critical_count + tank.active_warning_count;
      rows.push({ key: `observed-${tank.id}`, tankId: tank.id, category: 'Observed', tone: status,
        copy: `${tank.name} · ${status === 'critical' ? 'Critical' : 'Offline'}${alerts ? ` · ${alerts} open alert${alerts === 1 ? '' : 's'}` : ''}` });
    });
  }
  const items = insights?.attention ?? [];
  const projected = items.filter((item) => item.kind === 'projected' && item.type === 'crossing_projected')
    .sort((a, b) => (a.crossing_hours_low ?? Infinity) - (b.crossing_hours_low ?? Infinity));
  const variable = items.filter((item) => item.kind === 'derived' && item.type === 'more_variable')
    .sort((a, b) => (b.ratio ?? 0) - (a.ratio ?? 0));
  const conflicts = items.filter((item) => item.kind === 'derived' && item.type === 'species_conflict');
  for (const item of [...projected, ...variable, ...conflicts]) {
    const parameterName = metricOptions.find((option) => option.key === item.parameter)!.label;
    const parameter = insights?.tanks.find((tank) => tank.tank_id === item.tank_id)?.parameters.find((p) => p.parameter === item.parameter);
    const detail = item.type === 'crossing_projected'
      ? `may reach warning bound ${crossingTimeCopy(item.crossing_hours_low, item.crossing_hours_high)} if trend continues`
      : item.type === 'more_variable'
        ? parameter ? stabilityCopy(parameter.stability) : 'More variable than usual'
        : parameter ? speciesCopy(parameter.species_range, parameter.unit) : "Assigned species' ranges do not overlap";
    rows.push({ key: `${item.type}-${item.tank_id}-${item.parameter}`, tankId: item.tank_id,
      category: item.kind === 'projected' ? 'Projected' : 'Derived', tone: item.kind === 'projected' ? 'projected' : 'derived', copy: `${item.tank_name} · ${parameterName}: ${detail}` });
  }
  return rows.slice(0, 3);
}
export function NeedsAttentionPanel({ tanks, insights, insightsError, insightsPending, fleetPending, fleetError }: {
  tanks: FleetTank[]; insights?: CurrentInsightsResponse; insightsError: boolean; insightsPending: boolean;
  fleetPending: boolean; fleetError: boolean;
}) {
  // A failed refresh cannot leave stale advisory rows/indicators on the dashboard.
  const usableInsights = insightsError ? undefined : insights;
  const rows = attentionRows(tanks, usableInsights);
  const insufficient = usableInsights?.tanks.filter((tank) => tank.parameters.some((p) => p.trend.status === 'insufficient_data')).length ?? 0;
  const pending = fleetPending || insightsPending;
  return <Panel title="Needs attention" className="needs-attention-panel"
    description="The few things worth checking first. Projections and derived insights are advisory.">
    {rows.length > 0 && <ul className="needs-attention-list">
      {rows.map((row) => {
        const split = row.copy.indexOf(' · ');
        return <li key={row.key}><Link className="needs-attention-row" data-tone={row.tone} to={`/admin/analytics?insights_tank=${row.tankId}`}>
          <CategoryLabel kind={row.category.toLowerCase() as 'observed' | 'derived' | 'projected'} />
          <span className="needs-attention-copy">{split > 0 ? <><strong>{row.copy.slice(0, split)}</strong>{row.copy.slice(split)}</> : row.copy}</span>
          <ChevronRight size={16} aria-hidden="true" className="needs-attention-chevron" />
        </Link></li>;
      })}
    </ul>}
    {insightsError && <p role="status" className="needs-attention-note">Insights unavailable</p>}
    {fleetError && <p role="status" className="needs-attention-note">Fleet status unavailable</p>}
    {pending && <LoadingState label="Checking attention…" />}
    {!rows.length && !pending && !insightsError && !fleetError && <EmptyState title="No tanks need attention right now." message="" />}
    {!rows.length && insufficient > 0 && <p className="needs-attention-note">{insufficient} tanks have too little recent data to assess.</p>}
  </Panel>;
}
