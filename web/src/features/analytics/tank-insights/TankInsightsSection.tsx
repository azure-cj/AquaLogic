import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { EmptyState, ErrorState, LoadingState, Panel } from '@/shared/components/admin-ui';
import type { CurrentParameter } from '../types';
import { metricOptions } from '../types';
import { useCurrentInsights } from '../useCurrentInsights';
import { MethodDisclosure } from './MethodDisclosure';
import { ParameterSummaryCard } from './ParameterSummaryCard';
import { RecentTrendChart } from './RecentTrendChart';
import { formatAnalyticsDate } from '../utils';

export function TankInsightsSection() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [parameterKey, setParameterKey] = useState<CurrentParameter>('temperature');
  const overview = useCurrentInsights();
  const tanks = overview.data?.tanks ?? [];
  const requested = Number(searchParams.get('insights_tank'));
  const selectedId = tanks.find((tank) => tank.tank_id === requested)?.tank_id
    ?? tanks.find((tank) => tank.tank_id === overview.data?.attention[0]?.tank_id)?.tank_id
    ?? tanks[0]?.tank_id;
  const selected = useCurrentInsights(selectedId ?? null);
  const tank = selected.data?.tanks.find((item) => item.tank_id === selectedId);
  const parameter = tank?.parameters.find((item) => item.parameter === parameterKey);
  const tankPicker = <label className="field tank-insights-picker"><span>Insights tank</span>
    <select value={selectedId ?? ''} disabled={!tanks.length} onChange={(event) => {
      setSearchParams((current) => {
        const next = new URLSearchParams(current);
        next.set('insights_tank', event.target.value);
        return next;
      }, { replace: true });
    }}>
      {!tanks.length && <option value="">{overview.isPending ? 'Loading tanks…' : 'No active tanks'}</option>}
      {tanks.map((item) => <option value={item.tank_id} key={item.tank_id}>{item.tank_name}</option>)}
    </select>
  </label>;
  const evaluated = selected.data?.evaluated_at;
  return <Panel title="Tank insights" className="tank-insights-section" action={tankPicker}
    description={`What the readings say right now: observed values, derived trends, and short conditional projections.${evaluated ? ` Evaluated ${formatAnalyticsDate(evaluated)}.` : ''}`}>
    {overview.isError && <ErrorState message="Tank insights could not be loaded." retry={() => overview.refetch()} />}
    {overview.isPending ? <LoadingState label="Loading tank insights…" /> : !overview.isError && !tanks.length ?
      <EmptyState title="No active tanks" message="Add an active tank to see current insights." /> : null}
    {selectedId != null && (selected.isError ? <ErrorState message="Tank insights could not be loaded." retry={() => selected.refetch()} /> :
      selected.isPending ? <LoadingState label="Loading selected tank insights…" /> : tank ? <>
        <div className="tank-insights-grid">
          {metricOptions.map((option) => {
            const value = tank.parameters.find((item) => item.parameter === option.key);
            return value && <ParameterSummaryCard key={option.key} parameter={value} latest={tank.latest}
              selected={parameterKey === option.key} onSelect={() => setParameterKey(option.key)} />;
          })}
        </div>
        {parameter && <RecentTrendChart parameter={parameter} evaluatedAt={selected.data!.evaluated_at} />}
      </> : <p className="tank-insights-unavailable">Selected tank insights are unavailable.</p>)}
    <MethodDisclosure />
  </Panel>;
}
