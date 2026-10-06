import { describe, expect, it } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { insightsFixture, parameterFixture, tankFixture } from '@/features/analytics/tank-insights/currentInsights.fixture';
import type { CurrentAttentionItem } from '@/features/analytics/types';
import type { FleetTank } from '@/shared/api/models';
import { NeedsAttentionPanel, attentionRows } from './NeedsAttentionPanel';
import { TrendIndicator } from './TrendIndicator';

const tank = (id: number, status: FleetTank['status']): FleetTank => ({
  id, status, name: `Tank ${id}`, public_id: `tank-${id}`, customer: null, location: '', latest_reading: null,
  last_reading_at: null, reporting_age_seconds: null, active_critical_count: status === 'critical' ? 2 : 0,
  active_warning_count: 0, active_monitoring_incident_count: 0,
});
function item(type: CurrentAttentionItem['type'], id = 1, low = 1, ratio = 2): CurrentAttentionItem {
  return { type, kind: type === 'crossing_projected' ? 'projected' : 'derived', tank_id: id, tank_name: `Tank ${id}`,
    parameter: 'temperature', crossing_hours_low: low, crossing_hours_high: 2, ratio };
}
const defaults = { tanks: [], insightsError: false, insightsPending: false, fleetPending: false, fleetError: false };
describe('needs attention ranking and structure', () => {
  it('ranks critical before offline before earliest projected with max three rows', () => {
    const data = insightsFixture(); data.attention = [item('species_conflict'), item('more_variable'), item('crossing_projected', 2, 2), item('crossing_projected', 1, .5)];
    const rows = attentionRows([tank(3, 'normal'), tank(2, 'offline'), tank(1, 'critical')], data);
    expect(rows.map((row) => row.category)).toEqual(['Observed', 'Observed', 'Projected']);
    expect(rows.map((row) => row.tankId)).toEqual([1, 2, 1]);
    expect(rows[0].copy).toBe('Tank 1 · Critical · 2 open alerts');
    expect(rows[2].copy).toBe('Tank 1 · Temperature: may reach warning bound in about 0.5–2 h if trend continues');
  });
  it('ranks variable before conflicts and sorts variability by ratio', () => {
    const data = insightsFixture(); data.attention = [item('species_conflict', 3), item('more_variable', 1, 1, 2), item('more_variable', 2, 1, 3)];
    data.tanks.push(tankFixture(3));
    for (const value of data.tanks) {
      value.parameters[0].stability.status = 'more_variable'; value.parameters[0].stability.ratio = value.tank_id === 2 ? 3 : 2;
    }
    data.tanks[2].parameters[0].species_range.status = 'conflict';
    data.tanks[2].parameters[0].species_range.conflict = { min_species: 'Discus', min: 28, max_species: 'Corydoras', max: 27 };
    const rows = attentionRows([], data);
    expect(rows.map((row) => row.tankId)).toEqual([2, 1, 3]);
    expect(rows.map((row) => row.category)).toEqual(['Derived', 'Derived', 'Derived']);
    expect(rows[0].copy).toContain('More variable than usual (3.0× its 7-day baseline)');
    expect(rows[2].copy).toContain("Assigned species' ranges do not overlap: Discus needs at least 28, Corydoras needs at most 27");
  });
  it('caps observed-only rows at three and excludes warnings from the specified observed ranking', () => {
    const rows = attentionRows([tank(1, 'offline'), tank(2, 'critical'), tank(3, 'critical'), tank(4, 'critical'), tank(5, 'warning')]);
    expect(rows.map((row) => row.tankId)).toEqual([2, 3, 4]);
  });
  it('reuses rounded crossing phrasing for equal, soon, within and open-ended times', () => {
    const data = insightsFixture();
    for (const [low, high, expected] of [[.4, .6, 'in about 0.5 h'], [.1, .6, 'within about 0.5 h'], [.1, .2, 'soon; the latest readings are close to the bound'], [1.9, null, 'in about 2 h or later']] as const) {
      data.attention = [{ ...item('crossing_projected'), crossing_hours_low: low, crossing_hours_high: high }];
      expect(attentionRows([], data)[0].copy).toContain(expected);
      expect(attentionRows([], data)[0].copy).toContain('if trend continues');
    }
  });
  it('renders text badges and links carrying insights_tank', () => {
    render(<MemoryRouter><NeedsAttentionPanel {...defaults} tanks={[tank(1, 'critical')]} insights={insightsFixture()} /></MemoryRouter>);
    expect(screen.getByRole('heading', { name: 'Needs attention' })).toBeInTheDocument();
    const links = screen.getAllByRole('link');
    expect(links[0]).toHaveAttribute('href', '/admin/analytics?insights_tank=1');
    expect(within(links[0]).getByText('Observed')).toBeInTheDocument();
    expect(within(links[1]).getByText('Projected')).toBeInTheDocument();
  });
  it('counts insufficient tanks once each across multiple parameters in the empty state', () => {
    const data = insightsFixture(); data.attention = [];
    data.tanks[0].parameters[0].trend.status = 'insufficient_data'; data.tanks[0].parameters[1].trend.status = 'insufficient_data';
    data.tanks[1].parameters[1].trend.status = 'insufficient_data';
    render(<MemoryRouter><NeedsAttentionPanel {...defaults} tanks={[tank(1, 'normal'), tank(2, 'warning')]} insights={data} /></MemoryRouter>);
    expect(screen.getByText('No tanks need attention right now.')).toBeInTheDocument();
    expect(screen.getByText('2 tanks have too little recent data to assess.')).toBeInTheDocument();
  });
  it('keeps observed rows on insights error and suppresses stale cached advisory rows', () => {
    render(<MemoryRouter><NeedsAttentionPanel {...defaults} tanks={[tank(1, 'offline')]} insights={insightsFixture()} insightsError /></MemoryRouter>);
    expect(screen.getByText('Insights unavailable')).toBeInTheDocument();
    expect(screen.getByRole('link')).toHaveTextContent('ObservedTank 1 · Offline');
    expect(screen.queryByText('Projected')).not.toBeInTheDocument();
    expect(screen.queryByText('No tanks need attention right now.')).not.toBeInTheDocument();
  });
  it('does not say all clear before responses or after an insights failure', () => {
    const view = render(<MemoryRouter><NeedsAttentionPanel {...defaults} insightsPending /></MemoryRouter>);
    expect(screen.getByText('Checking attention…')).toBeInTheDocument();
    expect(screen.queryByText('No tanks need attention right now.')).not.toBeInTheDocument();
    view.rerender(<MemoryRouter><NeedsAttentionPanel {...defaults} insightsError /></MemoryRouter>);
    expect(screen.getByText('Insights unavailable')).toBeInTheDocument();
    expect(screen.queryByText('No tanks need attention right now.')).not.toBeInTheDocument();
  });
});
describe('tank card trend indicators', () => {
  it.each(['rising', 'falling'] as const)('shows direction, rate, unit and Derived accessible copy for %s', (status) => {
    const p = parameterFixture(); p.trend.status = status; p.trend.rate_per_hour = status === 'rising' ? .184 : -.184;
    render(<TrendIndicator parameter={p} />);
    expect(screen.getByLabelText(`Derived: ${status === 'rising' ? 'Rising' : 'Falling'} 0.18 °C/h over the last 6 h`)).toHaveTextContent(`${status === 'rising' ? '↑' : '↓'} 0.18 °C/h`);
  });
  it.each(['steady', 'uncertain', 'insufficient_data'] as const)('shows nothing for %s', (status) => {
    const p = parameterFixture(); p.trend.status = status;
    const { container } = render(<TrendIndicator parameter={p} />); expect(container).toBeEmptyDOMElement();
  });
  it('shows nothing without a rate or for parameters other than temperature/pH', () => {
    const p = parameterFixture(); p.trend.rate_per_hour = null;
    const view = render(<TrendIndicator parameter={p} />); expect(view.container).toBeEmptyDOMElement();
    view.rerender(<TrendIndicator />); expect(view.container).toBeEmptyDOMElement();
    view.rerender(<TrendIndicator parameter={parameterFixture('tds')} />); expect(view.container).toBeEmptyDOMElement();
    view.rerender(<TrendIndicator parameter={parameterFixture('turbidity')} />); expect(view.container).toBeEmptyDOMElement();
    view.rerender(<TrendIndicator parameter={parameterFixture('ph')} />); expect(view.container).toHaveTextContent('↑ 0.18 pH/h');
  });
});
