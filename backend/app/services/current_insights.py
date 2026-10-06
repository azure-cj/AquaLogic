"""Read-only, bounded advisory insights; observations never become forecasts.

Observation time defines inference windows. Receipt time defines freshness.
No ingestion, alert, push or incident service is called from this module.
"""
from collections import OrderedDict, defaultdict
from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from math import ceil, floor, isfinite, sqrt
from statistics import median
from threading import Lock
from time import monotonic
from weakref import WeakKeyDictionary

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.models import SensorReading, Tank
from app.services.analytics_insights import PARAMETERS, UNITS, aware, notable_change
from app.services.reading_freshness import is_reading_current
from app.services.thresholds import resolve_effective_thresholds

METHOD_VERSION = "ci-v1"
BUCKET_SECONDS = 1800
MIN_BUCKET_READINGS = 3
FIT_BUCKETS = 12
MIN_FIT_BUCKETS = 10
MAX_GAP_SECONDS = 3600
SLOPE_CI_Z = 1.645
BAND_Z = 1.645
HORIZON_HOURS = 3.0
PROJECTION_STEP_HOURS = 0.25
PROJECTED_PARAMETERS = ("temperature", "ph", "tds")
STABILITY_CURRENT_BUCKETS = 48
STABILITY_MIN_CURRENT_BUCKETS = 36
BASELINE_DAYS = 7
BASELINE_MIN_DAYS = 5
MORE_VARIABLE_RATIO = 1.5
STEADIER_RATIO = 0.67
SPREAD_FLOOR = {"temperature": 0.02, "ph": 0.01, "tds": 1.0, "turbidity": 0.1}
SPECIES_COMPLIANCE_MIN_READINGS = 30
INSIGHTS_CACHE_TTL_SECONDS = 20
INSIGHTS_CACHE_MAX_ENTRIES = 32
# Separate database binds cannot share responses. Each bind's bounded LRU is
# keyed only by the sorted active tank-id tuple. No DB writes or background work.
_cache_by_bind = WeakKeyDictionary()
_cache_lock = Lock()


def clear_current_insights_cache():
    with _cache_lock:
        _cache_by_bind.clear()


def _cached(bind, key):
    with _cache_lock:
        entries = _cache_by_bind.get(bind)
        if entries is None or key not in entries:
            return None
        expires, value = entries[key]
        if monotonic() >= expires:
            del entries[key]
            return None
        entries.move_to_end(key)
        return deepcopy(value)


def _remember(bind, key, value):
    with _cache_lock:
        entries = _cache_by_bind.setdefault(bind, OrderedDict())
        entries[key] = (monotonic() + INSIGHTS_CACHE_TTL_SECONDS, deepcopy(value))
        entries.move_to_end(key)
        while len(entries) > INSIGHTS_CACHE_MAX_ENTRIES:
            entries.popitem(last=False)


@dataclass(frozen=True)
class Fit:
    slope: float
    low: float
    high: float
    intercept: float
    sigma: float
    origin: datetime
    end: datetime


def sen_fit(points, origin, end):
    """Fit unrounded bucket-centre values, using Part A's exact rank indices."""
    xs = [(point[0] - origin).total_seconds() / 3600 for point in points]
    ys = [point[1] for point in points]
    slopes = sorted((ys[j] - ys[i]) / (xs[j] - xs[i])
                    for i in range(len(xs)) for j in range(i + 1, len(xs)))
    n, pairs = len(points), len(slopes)
    c = SLOPE_CI_Z * sqrt(n * (n - 1) * (2 * n + 5) / 18)
    low = slopes[max(0, floor((pairs - c) / 2))]
    high = slopes[min(pairs - 1, ceil((pairs + c) / 2))]
    slope = median(slopes)
    intercept = median(y - slope * x for x, y in zip(xs, ys))
    residuals = [y - (intercept + slope * x) for x, y in zip(xs, ys)]
    centre = median(residuals)
    sigma = 1.4826 * median(abs(residual - centre) for residual in residuals)
    return Fit(slope, low, high, intercept, sigma, origin, end)


def bucket_start(stamp):
    return floor(aware(stamp).timestamp() / BUCKET_SECONDS) * BUCKET_SECONDS


def stamp(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc)


def build_trend(parameter, buckets, sources, end):
    """Return the public trend and a private unrounded fit for projection."""
    start = end - FIT_BUCKETS * BUCKET_SECONDS
    qualifying = [(key, median(values), len(values)) for key, (values, times) in sorted(buckets.items())
                  if start <= key < end and len(times) >= MIN_BUCKET_READINGS]
    points = [(stamp(key + BUCKET_SECONDS / 2), value) for key, value, _ in qualifying]
    result = dict(status="insufficient_data", reason=None, rate_per_hour=None, rate_ci_low=None,
                  rate_ci_high=None, change_6h=None, notable_change=None,
                  qualifying_buckets=len(points), required_buckets=MIN_FIT_BUCKETS,
                  fit_points=[dict(t=t, value=value, count=count)
                              for (t, value), (_, _, count) in zip(points, qualifying)],
                  fitted_start=None, fitted_end=None, sigma=None)
    if len(sources) > 1:
        result['reason'] = 'mixed_source'
    elif len(points) < MIN_FIT_BUCKETS:
        result['reason'] = 'too_few_buckets'
    elif any(right[0] - left[0] > MAX_GAP_SECONDS for left, right in zip(qualifying, qualifying[1:])):
        result['reason'] = 'gap'
    elif qualifying[-1][0] != end - BUCKET_SECONDS:
        result['reason'] = 'not_recent'
    if result['reason']:
        return result, None
    fit = sen_fit(points, stamp(start), stamp(end))
    notable = notable_change(parameter, median(value for _, value in points))
    change = fit.slope * 6
    if abs(change) >= notable and (fit.low > 0 or fit.high < 0):
        status = 'rising' if fit.low > 0 else 'falling'
    elif abs(change) < notable and (fit.high - fit.low) * 6 < 2 * notable:
        status = 'steady'
    else:
        status = 'uncertain'
    result.update(status=status, rate_per_hour=fit.slope, rate_ci_low=fit.low, rate_ci_high=fit.high,
                  change_6h=change, notable_change=notable, sigma=fit.sigma,
                  fitted_start=dict(t=points[0][0], value=fit.intercept + fit.slope *
                                    (points[0][0] - fit.origin).total_seconds() / 3600),
                  fitted_end=dict(t=fit.end, value=fit.intercept + fit.slope *
                                  (fit.end - fit.origin).total_seconds() / 3600))
    return result, fit


def headroom(value, bounds, trend_status):
    if bounds is None:
        return None
    lower, upper = bounds['min'], bounds['max']
    if trend_status == 'rising':
        side = 'upper'
    elif trend_status == 'falling':
        side = 'lower'
    else:
        distances = [(abs(value - bound), side) for side, bound in (('upper', upper), ('lower', lower))
                     if bound is not None and value is not None]
        # Ties choose upper deterministically; a one-sided range chooses its configured bound.
        side = min(distances, key=lambda item: item[0])[1] if distances else ('lower' if upper is None and lower is not None else 'upper')
    bound = upper if side == 'upper' else lower
    reason = 'side_bound_missing' if bound is None else 'value_unavailable' if value is None else None
    distance = None if reason else (bound - value if side == 'upper' else value - bound)
    return dict(side=side, bound=bound, distance=distance,
                outside=None if distance is None else distance < 0, reason=reason)


def build_stability(parameter, buckets, sources, end):
    """Compare adjacent half-hour changes in rolling, complete-bucket windows."""
    current_start = end - STABILITY_CURRENT_BUCKETS * BUCKET_SECONDS
    baseline_start = current_start - BASELINE_DAYS * 86400
    points = [(key, median(values)) for key, (values, times) in sorted(buckets.items())
              if baseline_start <= key < end and len(times) >= MIN_BUCKET_READINGS]
    current = [(key, value) for key, value in points if key >= current_start]
    baseline = [(key, value) for key, value in points if key < current_start]
    days = defaultdict(int)
    for key, _ in baseline:
        days[stamp(key).date()] += 1
    covered = sum(count >= 24 for count in days.values())
    result = dict(status='insufficient_data', reason=None, current_spread=None,
                  baseline_spread=None, ratio=None, current_buckets=len(current),
                  baseline_days_covered=covered)
    if len(sources) > 1:
        result['reason'] = 'mixed_source'
        return result
    if len(current) < STABILITY_MIN_CURRENT_BUCKETS:
        result['reason'] = 'too_few_buckets'
        return result

    def spread(values):
        changes = [abs(right[1] - left[1]) for left, right in zip(values, values[1:])
                   if right[0] - left[0] == BUCKET_SECONDS]
        return median(changes) if changes else None

    result['current_spread'] = spread(current)
    if covered < BASELINE_MIN_DAYS:
        result.update(status='insufficient_baseline', reason='too_few_days')
        return result
    baseline_spread = spread(baseline)
    if baseline_spread is None:
        result.update(status='insufficient_baseline', reason='no_adjacent_buckets')
        return result
    ratio = result['current_spread'] / max(baseline_spread, SPREAD_FLOOR[parameter])
    result.update(status='more_variable' if ratio >= MORE_VARIABLE_RATIO else
                  'steadier' if ratio <= STEADIER_RATIO else 'typical',
                  baseline_spread=baseline_spread, ratio=ratio)
    return result


def species_range(species, parameter):
    result = dict(status='not_configured', min=None, max=None, species_count=len(species), conflict=None,
                  compliance_percent_24h=None, headroom=None, compliance_reason=None,
                  compliance_readings=0, required_readings=SPECIES_COMPLIANCE_MIN_READINGS)
    if parameter == 'turbidity':
        result['status'] = 'not_applicable'
        return result
    prefix = 'ideal_temp' if parameter == 'temperature' else f'ideal_{parameter}'
    ordered = sorted(species, key=lambda item: (item.common_name, item.id))
    mins = [(getattr(item, prefix + '_min'), item.common_name) for item in ordered
            if getattr(item, prefix + '_min') is not None]
    maxes = [(getattr(item, prefix + '_max'), item.common_name) for item in ordered
             if getattr(item, prefix + '_max') is not None]
    if not mins and not maxes:
        return result
    lo = max(mins, key=lambda item: item[0]) if mins else (None, None)
    hi = min(maxes, key=lambda item: item[0]) if maxes else (None, None)
    result.update(status='ok', min=lo[0], max=hi[0])
    if lo[0] is not None and hi[0] is not None and lo[0] > hi[0]:
        result.update(status='conflict', conflict=dict(min_species=lo[1], min=lo[0], max_species=hi[1], max=hi[0]))
    return result


class TankWindow:
    """Separate real/mock accumulators permit tank-wide filtering per window.

    Retains only per-parameter bucket values/timestamps for exact medians.
    Compliance is counted while streaming, including partial current buckets.
    """
    def __init__(self, species, now):
        self.now = now
        self.end = bucket_start(now)
        self.start = self.end - FIT_BUCKETS * BUCKET_SECONDS
        self.day_start = now - timedelta(hours=24)
        self.stability_start = self.end - (STABILITY_CURRENT_BUCKETS * BUCKET_SECONDS + BASELINE_DAYS * 86400)
        self.real_fit = self.real_day = False
        self.real_stability = False
        self.buckets = defaultdict(lambda: defaultdict(lambda: defaultdict(lambda: ([], set()))))
        self.stability_buckets = defaultdict(lambda: defaultdict(lambda: defaultdict(lambda: ([], set()))))
        self.stability_sources = defaultdict(lambda: defaultdict(set))
        self.fit_sources = defaultdict(lambda: defaultdict(set))
        self.day_sources = defaultdict(lambda: defaultdict(set))
        self.counts = defaultdict(lambda: defaultdict(lambda: [0, 0]))
        self.ranges = {parameter: species_range(species, parameter) for parameter in PARAMETERS}

    def add(self, row):
        observed = aware(row.timestamp)
        key = bucket_start(observed)
        in_fit = self.start <= key < self.end
        in_day = self.day_start <= observed <= self.now
        in_stability = self.stability_start <= key < self.end
        if not in_fit and not in_day and not in_stability:
            return
        mock = row.is_mock
        self.real_fit |= in_fit and not mock
        self.real_day |= in_day and not mock
        self.real_stability |= in_stability and not mock
        source = (row.device_id, mock)
        for parameter in PARAMETERS:
            value = getattr(row, parameter)
            if value is None or not isfinite(value):
                continue
            if in_fit:
                values, times = self.buckets[mock][parameter][key]
                values.append(value)
                if len(times) < MIN_BUCKET_READINGS:
                    times.add(observed)
                self.fit_sources[mock][parameter].add(source)
            if in_stability:
                values, times = self.stability_buckets[mock][parameter][key]
                values.append(value)
                if len(times) < MIN_BUCKET_READINGS:
                    times.add(observed)
                self.stability_sources[mock][parameter].add(source)
            if in_day:
                self.day_sources[mock][parameter].add(source)
                bounds = self.ranges[parameter]
                counts = self.counts[mock][parameter]
                counts[0] += 1
                counts[1] += ((bounds['min'] is None or value >= bounds['min']) and
                              (bounds['max'] is None or value <= bounds['max']))


def projection(parameter, latest, value, bounds, trend, fit, now):
    """Conditional extrapolation with ordered gates; never an observed value."""
    horizon = min(HORIZON_HOURS, FIT_BUCKETS * BUCKET_SECONDS / 3600 / 2)
    result = dict(status='not_applicable', reason=None, bound_side=None, bound=None,
                  crossing_hours_low=None, crossing_hours_high=None, horizon_hours=horizon, band=[])
    if parameter not in PROJECTED_PARAMETERS:
        return result
    if not latest['is_current']:
        result['status'] = 'stale'
        return result
    if trend['status'] == 'insufficient_data':
        result.update(status='insufficient_data', reason=trend['reason'])
        return result
    # Invalid or missing latest parameter values must not be invented from the fit.
    if value is None:
        result.update(status='insufficient_data', reason='value_unavailable')
        return result
    if bounds is not None and ((bounds['min'] is not None and value < bounds['min']) or
                               (bounds['max'] is not None and value > bounds['max'])):
        result['status'] = 'already_outside'
        return result
    if trend['status'] == 'uncertain':
        result['status'] = 'too_uncertain'
        return result
    side = 'upper' if trend['status'] == 'rising' else 'lower' if trend['status'] == 'falling' else None
    bound = bounds['max' if side == 'upper' else 'min'] if bounds is not None and side else None
    if trend['status'] != 'steady' and bound is None:
        result.update(status='no_bound', bound_side=side)
        return result
    level = fit.intercept + fit.slope * (fit.end - fit.origin).total_seconds() / 3600
    steps = [index * PROJECTION_STEP_HOURS for index in range(round(horizon / PROJECTION_STEP_HOURS) + 1)]
    result['band'] = [dict(t=fit.end + timedelta(hours=h),
                           low=level + fit.low * h - BAND_Z * fit.sigma,
                           mid=level + fit.slope * h,
                           high=level + fit.high * h + BAND_Z * fit.sigma) for h in steps]
    result.update(status='no_crossing_within_horizon', bound_side=side, bound=bound)
    if trend['status'] == 'steady':
        return result  # Still disclose the conditional band, even without a configured bound.

    def crossing(edge):
        return next((h for h, point in zip(steps, result['band'])
                     if (point[edge] >= bound if side == 'upper' else point[edge] <= bound)), None)

    if crossing('mid') is None:
        return result
    # Only the mid-line establishes a crossing. Edges then describe its range.
    early = crossing('high' if side == 'upper' else 'low')
    late = crossing('low' if side == 'upper' else 'high')
    elapsed = (now - fit.end).total_seconds() / 3600
    result.update(status='crossing_projected', crossing_hours_low=max(0., early - elapsed),
                  crossing_hours_high=max(0., late - elapsed) if late is not None else None)
    return result


def attention_items(tanks):
    """Rank advisory results independently of persisted alerts/offline status."""
    ranked = []
    for tank in tanks:
        for parameter in tank['parameters']:
            projection, stability, species = (parameter[key] for key in ('projection', 'stability', 'species_range'))
            base = dict(tank_id=tank['tank_id'], tank_name=tank['tank_name'], parameter=parameter['parameter'],
                        crossing_hours_low=None, crossing_hours_high=None, ratio=None)
            tie = (tank['tank_name'], tank['tank_id'], PARAMETERS.index(parameter['parameter']))
            if projection['status'] == 'crossing_projected':
                item = dict(base, kind='projected', type='crossing_projected',
                            crossing_hours_low=projection['crossing_hours_low'],
                            crossing_hours_high=projection['crossing_hours_high'])
                ranked.append(((0, projection['crossing_hours_low'], *tie), item))
            if stability['status'] == 'more_variable':
                item = dict(base, kind='derived', type='more_variable', ratio=stability['ratio'])
                ranked.append(((1, -stability['ratio'], *tie), item))
            if species['status'] == 'conflict':
                ranked.append(((2, 0, *tie), dict(base, kind='derived', type='species_conflict')))
    return [item for _, item in sorted(ranked, key=lambda pair: pair[0])[:10]]


def rounded(value):
    """Round only at the output boundary; fits and decisions retain full precision."""
    if isinstance(value, float):
        return round(value, 4)
    if isinstance(value, dict):
        return {key: rounded(item) for key, item in value.items()}
    if isinstance(value, list):
        return [rounded(item) for item in value]
    return value


def build_current_insights(db: Session, tank_ids=(), *, now=None, use_cache=True):
    cache_enabled = use_cache and now is None
    now = aware(now or datetime.now(timezone.utc))
    stmt = select(Tank).where(Tank.retired_at.is_(None)).options(selectinload(Tank.fish_species)).order_by(Tank.name, Tank.id)
    if tank_ids:
        stmt = stmt.where(Tank.id.in_(tank_ids))
    tanks = list(db.scalars(stmt))
    cache_key = tuple(sorted(tank.id for tank in tanks))
    bind = db.get_bind()
    if cache_enabled:
        cached = _cached(bind, cache_key)
        if cached is not None:
            return cached
    windows = {tank.id: TankWindow(tank.fish_species, now) for tank in tanks}
    ids = list(windows)
    columns = [SensorReading.id, SensorReading.tank_id, SensorReading.timestamp, SensorReading.received_at,
               SensorReading.device_id, SensorReading.is_mock, *(getattr(SensorReading, p) for p in PARAMETERS)]
    latest_by_tank = defaultdict(dict)
    # One column-only IN stream serves all tanks. Include at most two last-known
    # reports per tank outside the bounded history window, preserving stale context.
    if ids:
        ranked = select(SensorReading.id, func.row_number().over(
                    partition_by=(SensorReading.tank_id, SensorReading.is_mock),
                    order_by=(SensorReading.received_at.desc(), SensorReading.id.desc())).label('rank')).where(
                    SensorReading.tank_id.in_(ids), SensorReading.timestamp <= now,
                    SensorReading.received_at <= now).subquery()
        latest_ids = select(ranked.c.id).where(ranked.c.rank == 1)
        history = select(*columns).where(SensorReading.tank_id.in_(ids),
                    SensorReading.timestamp <= now, SensorReading.received_at <= now,
                    or_(SensorReading.timestamp >= stamp(bucket_start(now)) - timedelta(days=BASELINE_DAYS + 1),
                        SensorReading.id.in_(latest_ids))).execution_options(yield_per=1000)
        for row in db.execute(history):
            windows[row.tank_id].add(row)
            previous = latest_by_tank[row.tank_id].get(row.is_mock)
            if previous is None or (row.received_at, row.id) > (previous.received_at, previous.id):
                latest_by_tank[row.tank_id][row.is_mock] = row
    results = []
    for tank in tanks:
        window = windows[tank.id]
        candidates = latest_by_tank[tank.id]
        reading = candidates.get(False) if window.real_day else max(candidates.values(),
                    key=lambda row: (row.received_at, row.id), default=None)
        latest = dict(observed_at=aware(reading.timestamp) if reading else None,
                      received_at=aware(reading.received_at) if reading else None,
                      is_current=bool(reading and is_reading_current(reading.timestamp,
                                      received_at=reading.received_at, evaluated_at=now)))
        thresholds = resolve_effective_thresholds(db, tank.id, as_of=now)
        parameters = []
        for parameter in PARAMETERS:
            value = getattr(reading, parameter) if reading else None
            if value is not None and not isfinite(value):
                value = None
            threshold = thresholds.get(parameter)
            enabled = threshold is not None and threshold.enabled
            warning = dict(min=threshold.warning_min, max=threshold.warning_max) if enabled else None
            critical = dict(min=threshold.critical_min, max=threshold.critical_max) if enabled else None
            fit_mock, day_mock = not window.real_fit, not window.real_day
            trend, fit = build_trend(parameter, window.buckets[fit_mock][parameter],
                                    window.fit_sources[fit_mock][parameter], window.end)
            species = window.ranges[parameter].copy()
            count, inside = window.counts[day_mock][parameter]
            species['compliance_readings'] = count
            if species['status'] == 'ok':
                if len(window.day_sources[day_mock][parameter]) > 1:
                    species['compliance_reason'] = 'mixed_source'
                elif count < SPECIES_COMPLIANCE_MIN_READINGS:
                    species['compliance_reason'] = 'too_few_readings'
                else:
                    species['compliance_percent_24h'] = 100 * inside / count
                species['headroom'] = headroom(value, species, trend['status'])
            parameters.append(dict(parameter=parameter, unit=UNITS[parameter],
                observed=dict(value=value, observed_at=latest['observed_at']) if value is not None else None,
                warning_bounds=warning, critical_bounds=critical, trend=trend,
                headroom=headroom(value, warning, trend['status']), species_range=species,
                projection=projection(parameter, latest, value, warning, trend, fit, now),
                stability=build_stability(parameter, window.stability_buckets[not window.real_stability][parameter],
                                          window.stability_sources[not window.real_stability][parameter], window.end)))
        results.append(dict(tank_id=tank.id, tank_name=tank.name, latest=latest, parameters=parameters))
    response = rounded(dict(evaluated_at=now, method_version=METHOD_VERSION,
                        constants=dict(fit_hours=FIT_BUCKETS * BUCKET_SECONDS / 3600,
                                       horizon_hours=HORIZON_HOURS, baseline_days=BASELINE_DAYS,
                                       bucket_minutes=BUCKET_SECONDS / 60), tanks=results,
                        attention=attention_items(results)))
    if cache_enabled:
        _remember(bind, cache_key, response)
    return response
