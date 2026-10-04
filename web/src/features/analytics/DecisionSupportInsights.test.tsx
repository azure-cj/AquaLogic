import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { expect, it, vi } from 'vitest';
import { DecisionSupportInsights, FindingEvidence, findingSummary, trendOverview } from './DecisionSupportInsights';
import type { AnalyticsResponse, DecisionSupportCard } from './types';

const card: DecisionSupportCard = { id: '2.temperature.repeated_alerts.v1', rule: 'repeated_alerts', parameter: 'temperature', scope: 'tank', tank_id: 2, tank_name: 'Fictional Tank', title: '3 temperature alert records were created.', explanation: 'Records, not independent episodes.', window_start: '2026-10-01T00:00:00Z', window_end: '2026-10-02T00:00:00Z', observation_start: '2026-10-01T01:00:00Z', observation_end: '2026-10-01T23:00:00Z', samples: 40, unit: '°C', evidence: { count: 3 }, qualifications: ['Historical evidence, not a forecast.'], checks: ['Confirm the measurement.'], related_alert_ids: [1, 2, 3] };
const insights: NonNullable<AnalyticsResponse['decision_support_insights']> = { cards: [card], limitations: [{ tank_id: 3, tank_name: 'Sparse tank', parameter: 'ph', rule: 'direction_or_little_change', reason: 'Insufficient coverage', samples: 2 }], advisory: 'Engineering heuristics, not safety limits.' };

it('preserves graph navigation, evidence qualifications and alert creation filters', () => {
  const graph = vi.fn();
  render(<MemoryRouter><FindingEvidence card={card} onGraph={graph} /></MemoryRouter>);
  expect(screen.getByText('Readings analyzed')).toBeVisible();
  expect(screen.getByText('40')).toBeVisible();
  fireEvent.click(screen.getByRole('button', { name: 'View temperature graph for Fictional Tank' }));
  expect(graph).toHaveBeenCalledWith(2, 'temperature');
  const href = screen.getByRole('link', { name: 'View related alert records' }).getAttribute('href')!;
  const params = new URL(href, 'http://localhost').searchParams;
  expect(params.get('tank_id')).toBe('2'); expect(params.get('parameter')).toBe('temperature');
  expect(params.get('created_after')).toBe(card.window_start); expect(params.get('created_before')).toBe(card.window_end);
  expect(screen.getByRole('link', { name: 'Open alert #1' })).toHaveAttribute('href', expect.stringContaining('alert_id=1'));
});

it('shows up to three distinct tank highlights for the selected parameter and opens exact evidence', () => {
  const evidence = vi.fn();
  const cards = [card, { ...card, id: 'same-tank' }, ...Array.from({ length: 4 }, (_, i) => ({ ...card, id: String(i), tank_id: i + 5, tank_name: `Tank ${i + 5}` })), { ...card, id: 'ph', parameter: 'ph' as const, tank_name: 'Other parameter' }];
  render(<MemoryRouter><DecisionSupportInsights insights={{ ...insights, cards }} metric="temperature" onEvidence={evidence} /></MemoryRouter>);
  expect(screen.getAllByRole('article')).toHaveLength(1);
  expect(screen.getByRole('heading', { name: 'Repeated Temperature alerts in 5 tanks' })).toBeVisible();
  expect(screen.queryByText('Other parameter')).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: 'Review Fictional Tank' }));
  expect(evidence).toHaveBeenCalledWith(card);
});

it('keeps older responses readable and states lack of supported findings', () => {
  const view = render(<MemoryRouter><DecisionSupportInsights insights={undefined} metric="temperature" onEvidence={() => {}} /></MemoryRouter>);
  expect(screen.queryByText('Key findings')).not.toBeInTheDocument();
  view.rerender(<MemoryRouter><DecisionSupportInsights insights={{ ...insights, cards: [] }} metric="temperature" onEvidence={() => {}} /></MemoryRouter>);
  expect(screen.getByText(/No qualified findings/)).toBeInTheDocument();
});

it('prioritizes outside-range evidence and keeps bounds-change disclosure visible', () => {
  const routine = { ...card, id: 'routine', rule: 'within_range' as const, evidence: { percent: 100 }, related_alert_ids: [] };
  const outside = { ...routine, id: 'outside', tank_id: 4, tank_name: 'Outside-range tank', evidence: { percent: 51.22 }, qualifications: ['Operating bounds changed during this period.'] };
  render(<MemoryRouter><DecisionSupportInsights insights={{ ...insights, cards: [routine, outside] }} metric="temperature" onEvidence={() => {}} /></MemoryRouter>);
  expect(screen.getByText('Temperature needs attention in 1 tank')).toBeVisible();
  expect(screen.queryByText(/51.2%/)).not.toBeInTheDocument();
  expect(screen.getByText('Range changed')).toBeVisible();
  expect(screen.getAllByRole('article')).toHaveLength(1);
  expect(screen.queryByText('Fictional Tank')).not.toBeInTheDocument();
});

it('keeps unsupported trends uncertain and pluralizes recorded alerts', () => {
  expect(trendOverview(undefined, 'ph')).toBe('Not enough data to describe a reliable trend.');
  expect(trendOverview({ ...insights, cards: [{ ...card, rule: 'within_range', parameter: 'ph', evidence: { percent: 100, outside: 0 } }] }, 'ph')).not.toMatch(/stable|sustained change/);
  expect(findingSummary({ ...card, parameter: 'ph', evidence: { count: 1 } })).toBe('1 pH alert recorded');
  expect(findingSummary(card)).toBe('3 Temperature alerts recorded');
});

it('discloses precise calculations while keeping counts, exclusions and range changes visible', () => {
  const rangeCard = { ...card, rule: 'within_range' as const, parameter: 'ph' as const, evidence: { within: 29, outside: 12, evaluable: 41, percent: 70.73, excluded: 1 }, qualifications: ['Operating bounds changed during this period.'], related_alert_ids: [] };
  render(<MemoryRouter><FindingEvidence card={rangeCard} onGraph={() => {}} /></MemoryRouter>);
  expect(screen.getByRole('heading', { name: 'pH · tank evidence' })).toBeVisible();
  expect(screen.getByText('Readings analyzed')).toBeVisible();
  expect(screen.getByText('29')).toBeVisible();
  expect(screen.getByText('12')).toBeVisible();
  expect(screen.getByText('Excluded')).toBeVisible();
  expect(screen.getByText('1')).toBeVisible();
  expect(screen.queryByText('How this is calculated')).not.toBeInTheDocument();
  expect(screen.queryByText(/70.7/)).not.toBeInTheDocument();
});

it('consolidates similar outside-range tanks and caps distinct finding groups at three', () => {
  const cards = [1, 2, 3].map((tank_id) => ({ ...card, id: `outside-${tank_id}`, tank_id, tank_name: `Tank ${tank_id}`, rule: 'within_range' as const, evidence: { percent: 0, within: 0, outside: 41, evaluable: 41 } }));
  render(<MemoryRouter><DecisionSupportInsights metric="temperature" onEvidence={() => {}} insights={{ ...insights, cards: [...cards, { ...card, id: 'up', rule: 'increasing' }, { ...card, id: 'down', rule: 'decreasing' }, card] }} /></MemoryRouter>);
  expect(screen.getAllByRole('article')).toHaveLength(3);
  expect(screen.getByRole('heading', { name: 'Temperature needs attention in 3 tanks' })).toBeVisible();
  expect(screen.queryByText(/41 outside|0%|0 of 41/)).not.toBeInTheDocument();
});
