"""Deterministic historical evidence, using bounded half-hour accumulators.

These engineering heuristics are neither safety limits nor live forecasts.
"""
from bisect import bisect_right
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from math import ceil, floor, isfinite
from statistics import median

from app.services.operator_guidance import CATALOGUE

PARAMETERS = ("temperature", "ph", "turbidity", "tds")
UNITS = {"temperature": "°C", "ph": "pH", "turbidity": "NTU", "tds": "ppm"}
HALF_HOUR = 1800


def aware(value):
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def percentile(values, proportion):
    values = sorted(values)
    position = (len(values) - 1) * proportion
    left = floor(position)
    return values[left] + (values[ceil(position)] - values[left]) * (position - left)


def fitted_change(points):
    xs = [(stamp - points[0][0]) / HALF_HOUR for stamp, _ in points]
    ys = [value for _, value in points]
    mean_x, mean_y = sum(xs) / len(xs), sum(ys) / len(ys)
    denominator = sum((x - mean_x) ** 2 for x in xs)
    slope = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / denominator if denominator else 0
    residuals = [y - (mean_y + slope * (x - mean_x)) for x, y in zip(xs, ys)]
    return slope * (xs[-1] - xs[0]), percentile(residuals, .9) - percentile(residuals, .1)


def contrast(points):
    third = max(1, len(points) // 3)
    early = median([value for _, value in points[:third]])
    late = median([value for _, value in points[-third:]])
    return early, late, late - early


class AnalyticsInsightAccumulator:
    def __init__(self, start, end, tanks, selected_ids, histories, *, evaluated_at=None):
        self.start, self.end = aware(start), aware(end)
        self.completed_end = min(self.end, aware(evaluated_at or datetime.now(timezone.utc)))
        self.tanks = {tank.id: tank.name for tank in tanks if not selected_ids or tank.id in selected_ids}
        self.expected = max(0, floor(self.completed_end.timestamp() / HALF_HOUR) - ceil(self.start.timestamp() / HALF_HOUR))
        self.histories = {}
        self.changed_bounds = set()
        for tank_id, segments in histories.items():
            for parameter in PARAMETERS:
                items = [item for item in segments if item['parameter'] == parameter]
                self.histories[tank_id, parameter] = ([aware(item['start']) for item in items], items)
                if len({(item['enabled'], item['warning_min'], item['warning_max'], item['source']) for item in items}) > 1:
                    self.changed_bounds.add((tank_id, parameter))
        self.data = defaultdict(lambda: dict(count=0, first=None, last=None, within=0, outside=0, excluded=0,
            evaluable_first=None, evaluable_last=None, delayed=0, intervals={}, sources=set(), threshold_states=set()))

    def add(self, tank_id, observed, received, values, source):
        if tank_id not in self.tanks or not self.start <= observed < self.end:
            return
        for parameter in PARAMETERS:
            value = values.get(parameter)
            data = self.data[tank_id, parameter]
            data['count'] += 1
            data['first'] = observed if data['first'] is None else min(data['first'], observed)
            data['last'] = observed if data['last'] is None else max(data['last'], observed)
            data['delayed'] += (received - observed).total_seconds() > 90
            if value is None or not isfinite(value):
                data['excluded'] += 1
                continue
            starts, segments = self.histories.get((tank_id, parameter), ([], []))
            index = bisect_right(starts, observed) - 1
            segment = segments[index] if index >= 0 and observed < aware(segments[index]['end']) else None
            bounds = (segment['warning_min'], segment['warning_max']) if segment else (None, None)
            valid = (segment is not None and segment['enabled'] and any(bound is not None for bound in bounds)
                and all(bound is None or isfinite(bound) for bound in bounds)
                and not (all(bound is not None for bound in bounds) and bounds[0] > bounds[1]))
            if valid:
                inside = (bounds[0] is None or value >= bounds[0]) and (bounds[1] is None or value <= bounds[1])
                data['within' if inside else 'outside'] += 1
                data['evaluable_first'] = observed if data['evaluable_first'] is None else min(data['evaluable_first'], observed)
                data['evaluable_last'] = observed if data['evaluable_last'] is None else max(data['evaluable_last'], observed)
            else:
                data['excluded'] += 1
            data['threshold_states'].add(None if not segment else (segment['enabled'], *bounds, segment['source']))
            bucket = floor(observed.timestamp() / HALF_HOUR) * HALF_HOUR
            if bucket < self.start.timestamp() or bucket + HALF_HOUR > self.completed_end.timestamp():
                continue  # Partial intervals stay in the graph, never inference.
            interval = data['intervals'].setdefault(bucket, dict(total=0, count=0, stamps=set(), first=observed, last=observed))
            interval['total'] += value
            interval['count'] += 1
            # Only need three distinct timestamps, so storage does not grow with samples.
            if len(interval['stamps']) < 3:
                interval['stamps'].add(observed)
            interval['first'], interval['last'] = min(interval['first'], observed), max(interval['last'], observed)
            data['sources'].add(source)

    def finish(self, alerts):
        cards, limitations = [], []
        repeated = defaultdict(list)
        for event in alerts:
            if event['tank_id'] in self.tanks and event['parameter'] in PARAMETERS:
                repeated[event['tank_id'], event['parameter']].append(event['id'])
        for tank_id, tank_name in sorted(self.tanks.items()):
            for parameter in PARAMETERS:
                data = self.data[tank_id, parameter]
                label = 'pH' if parameter == 'ph' else parameter
                base = dict(parameter=parameter, scope='tank', tank_id=tank_id, tank_name=tank_name,
                    observation_start=data['first'], observation_end=data['last'], window_start=self.start, window_end=self.end,
                    samples=data['count'], unit=UNITS[parameter], qualifications=[], checks=[], related_alert_ids=[], evidence={})
                if data['delayed']:
                    base['qualifications'].append(f"{data['delayed']} delayed observations provide historical evidence, not a live forecast.")
                if len(data['threshold_states']) > 1 or (tank_id, parameter) in self.changed_bounds:
                    base['qualifications'].append('Operating bounds changed during this period. Expanded bounds do not establish improvement.')
                def card(rule, title, explanation, evidence, checks=None, refs=None):
                    return {**base, 'id': f'{tank_id}.{parameter}.{rule}.v1', 'rule': rule, 'title': title,
                        'explanation': explanation, 'evidence': evidence, 'checks': checks or [], 'related_alert_ids': refs or []}
                evaluable = data['within'] + data['outside']
                if evaluable >= 30 and (data['evaluable_last'] - data['evaluable_first']).total_seconds() >= 3600:
                    percent = round(100 * data['within'] / evaluable, 2)
                    cards.append(card('within_range', f'{percent:g}% of {label} observations within range',
                        'Compared with tank warning operating bounds effective at observation time, including inclusive endpoints. This is a proportion of observations, not time or health.',
                        dict(within=data['within'], outside=data['outside'], excluded=data['excluded'], evaluable=evaluable, percent=percent)))
                else:
                    limitations.append(dict(tank_id=tank_id, tank_name=tank_name, parameter=parameter, rule='within_range', reason='At least 30 evaluable observations spanning one hour are required.', samples=data['count'], excluded=data['excluded']))
                refs = sorted(set(repeated[tank_id, parameter]))
                if len(refs) >= 3:
                    cards.append(card('repeated_alerts', f'{len(refs)} {label} alert records were created.',
                        'Records were created in the selected window. Handling and continued abnormal readings can create further records; these are not independent physical episodes.', dict(count=len(refs)), refs=refs))
                qualifying = {stamp: item for stamp, item in data['intervals'].items() if len(item['stamps']) >= 3}
                points = sorted((stamp, item['total'] / item['count']) for stamp, item in qualifying.items())
                usable = sum(item['count'] for item in qualifying.values())
                span = ((max(item['last'] for item in qualifying.values()) - min(item['first'] for item in qualifying.values())).total_seconds() if qualifying else 0)
                coverage = len(points) / self.expected if self.expected else 0
                reason = None
                if usable < 30 or span < 10800 or len(points) < 7 or coverage < .8:
                    reason = 'Insufficient completed interval coverage: require 30 observations, three hours, seven intervals with three distinct timestamps each, and 80% coverage.'
                elif any(right[0] - left[0] > 3600 for left, right in zip(points, points[1:])):
                    reason = 'A substantial gap exceeds 60 minutes between qualifying interval starts.'
                elif len(data['sources']) > 1:
                    reason = 'Observation source changed during completed intervals.'
                if reason:
                    limitations.append(dict(tank_id=tank_id, tank_name=tank_name, parameter=parameter, rule='direction_or_little_change', reason=reason, samples=usable, interval_coverage=round(coverage * 100, 2)))
                    continue
                values = [value for _, value in points]
                period_median = median(values)
                notable = {'temperature': .5, 'ph': .15, 'turbidity': max(2, .15 * abs(period_median)), 'tds': max(20, .1 * abs(period_median))}[parameter]
                early, late, change = contrast(points)
                fitted, residual_spread = fitted_change(points)
                spread = percentile(values, .9) - percentile(values, .1)
                sign = 1 if change > 0 else -1
                survives = all(contrast(trim)[2] * sign > 0 and fitted_change(trim)[0] * sign > 0 for trim in (points[1:], points[:-1]))
                evidence = dict(early=round(early, 4), late=round(late, 4), change=round(change, 4), fitted_change=round(fitted, 4), notable_change=round(notable, 4), interval_spread=round(spread, 4), residual_spread=round(residual_spread, 4), qualifying_intervals=len(points), expected_intervals=self.expected, interval_coverage=round(coverage * 100, 2), usable_observations=usable,
                    inference_start=datetime.fromtimestamp(points[0][0], timezone.utc), inference_end=datetime.fromtimestamp(points[-1][0] + HALF_HOUR, timezone.utc))
                epsilon = 1e-9  # Avoid promoting a floating-point rounding artifact at E.
                if abs(change) > notable + epsilon and fitted * sign > notable + epsilon and survives and residual_spread <= 2 * notable + epsilon:
                    rule = 'increasing' if sign > 0 else 'decreasing'
                    cards.append(card(rule, f'{label.capitalize() if parameter != "ph" else label} observations {rule}',
                        f'Early interval median {early:.2f} to late median {late:.2f} {UNITS[parameter]} ({change:+.2f} {UNITS[parameter]}). Fitted direction agrees and survives removing either endpoint interval. Historical observations do not predict future values.', evidence,
                        CATALOGUE.get((parameter, 'above' if sign > 0 else 'below'), [])))
                elif abs(change) < notable - epsilon and abs(fitted) < notable - epsilon and spread <= 2 * notable + epsilon:
                    cards.append(card('little_change', f'Little sustained change in {label}',
                        f'Early interval median {early:.2f} to late median {late:.2f} {UNITS[parameter]} ({change:+.2f} {UNITS[parameter]}). This describes limited historical change; review within-range proportion separately.', evidence))
                else:
                    limitations.append(dict(tank_id=tank_id, tank_name=tank_name, parameter=parameter, rule='direction_or_little_change', reason='No consistent direction or little-change finding: interval evidence is noisy, oscillating, or inconsistent.', samples=usable, interval_coverage=round(coverage * 100, 2)))
        order = {'within_range': 0, 'repeated_alerts': 1, 'increasing': 2, 'decreasing': 2, 'little_change': 3}
        cards.sort(key=lambda item: (order[item['rule']], item['evidence'].get('percent', 100) if item['rule'] == 'within_range' else -item['evidence'].get('count', 0), item['tank_name'], item['tank_id'], PARAMETERS.index(item['parameter']), item['rule']))
        return dict(cards=cards, limitations=limitations,
                    advisory='Engineering heuristics describe historical observations, not safety limits, health, recovery, or forecasts. Fleet totals retain their existing scope; these findings name individual tanks.')
