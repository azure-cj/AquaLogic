from datetime import datetime, timedelta, timezone
from functools import partial
from math import ceil, floor, sqrt
from statistics import median

import pytest
from sqlalchemy import event

from app.models import (Alert, FishSpecies, MonitoringIncident, PushNotificationEvent,
                        RegisteredDevice, SensorReading, Tank, TankFish,
                        TankThresholdOverride, TankThresholdRevision, ThresholdRevision)
from app.services import current_insights as ci
from app.services.decision_engine import ensure_default_thresholds

NOW = datetime(2026, 10, 6, 12, tzinfo=timezone.utc)
START = NOW - timedelta(hours=6)


@pytest.fixture
def tank(db_session):
    tank = Tank(name='Insight test', location='Synthetic')
    db_session.add(tank)
    db_session.flush()
    ensure_default_thresholds(db_session)
    for row in db_session.query(ThresholdRevision):
        row.effective_from = NOW - timedelta(days=20)
    db_session.commit()
    return tank


def add_reading(db, tank, value, observed, *, received=None, mock=False, device=None, parameter='temperature'):
    values = dict(temperature=25., ph=7., turbidity=2., tds=100.)
    values[parameter] = value
    db.add(SensorReading(tank_id=tank.id, timestamp=observed, received_at=received or observed,
                         is_mock=mock, device_id=device, **values))


def series(db, tank, values=None, *, skip=(), mock=False, device=None, per_bucket=3,
           duplicate=False, latest=True, parameter='temperature', received=None):
    values = values if values is not None else [24 + i * .1 for i in range(12)]
    for i, value in enumerate(values):
        if i in skip:
            continue
        for j in range(per_bucket):
            observed = START + timedelta(minutes=30 * i + (0 if duplicate else j * 5))
            add_reading(db, tank, value, observed, received=received, mock=mock,
                        device=device, parameter=parameter)
    if latest:
        add_reading(db, tank, values[-1], NOW - timedelta(seconds=10), received=received,
                    mock=mock, device=device, parameter=parameter)
    db.commit()


def result(db, tank, parameter='temperature', *, now=NOW):
    response = ci.build_current_insights(db, [tank.id], now=now)
    return next(item for item in response['tanks'][0]['parameters'] if item['parameter'] == parameter)


def devices(db, tank):
    for name in ('a', 'b'):
        db.add(RegisteredDevice(id=name, tank_id=tank.id, key_hash=name * 64))
    db.commit()


def assign(db, tank, name='Warm fish', **ranges):
    fish = FishSpecies(common_name=name, scientific_name=name, **ranges)
    db.add(fish)
    db.flush()
    db.add(TankFish(tank_id=tank.id, fish_species_id=fish.id))
    db.commit()
    db.expire(tank, ['fish_species'])
    return fish


def override(db, tank, *, lower=23., upper=26., enabled=True):
    values = dict(parameter='temperature', unit='°C', warning_min=lower, warning_max=upper,
                  critical_min=None, critical_max=None, enabled=enabled)
    db.add(TankThresholdOverride(tank_id=tank.id, **values))
    db.add(TankThresholdRevision(tank_id=tank.id, is_override=True,
                                effective_from=NOW - timedelta(days=1), **values))
    db.commit()


@pytest.mark.parametrize('parameter,base,step', [('temperature',24,.1), ('ph',7,.025),
                                               ('tds',100,3), ('turbidity',2,.3)])
@pytest.mark.parametrize('direction', [1, -1])
def test_clean_linear_slope_and_direction(db_session, tank, parameter, base, step, direction):
    series(db_session, tank, [base + direction * step * i for i in range(12)], parameter=parameter)
    trend = result(db_session, tank, parameter)['trend']
    assert trend['status'] == ('rising' if direction == 1 else 'falling')
    assert trend['rate_per_hour'] == pytest.approx(direction * step * 2)
    assert trend['rate_ci_low'] == trend['rate_ci_high'] == trend['rate_per_hour']
    assert trend['sigma'] == 0
    assert trend['fitted_start']['t'] == START + timedelta(minutes=15)
    assert trend['fitted_end']['t'] == NOW
    assert trend['fitted_end']['value'] == pytest.approx(base + direction * step * 11.5)


@pytest.mark.parametrize('n', [10, 12])
def test_sen_interval_uses_exact_rank_formula(n):
    ys = [24 + i * .1 + (i % 3) * .07 for i in range(n)]
    points = [(START + timedelta(minutes=i * 30 + 15), y) for i, y in enumerate(ys)]
    fit = ci.sen_fit(points, START, NOW)
    slopes = sorted((ys[j] - ys[i]) / ((j - i) * .5) for i in range(n) for j in range(i + 1, n))
    pairs = n * (n - 1) // 2
    c = 1.645 * sqrt(n * (n - 1) * (2 * n + 5) / 18)
    assert fit.low == slopes[max(0, floor((pairs - c) / 2))]
    assert fit.high == slopes[min(pairs - 1, ceil((pairs + c) / 2))]
    assert fit.slope == median(slopes)
    intercepts = [y - fit.slope * (i * .5 + .25) for i, y in enumerate(ys)]
    assert fit.intercept == median(intercepts)
    residuals = [value - fit.intercept for value in intercepts]
    assert fit.sigma == pytest.approx(1.4826 * median(abs(r - median(residuals)) for r in residuals))


def test_single_extreme_sample_and_bucket_do_not_flip_trend(db_session, tank):
    values = [24 + i * .1 for i in range(12)]
    values[5] = 1000  # One entire anomalous median still cannot reverse robust direction.
    series(db_session, tank, values)
    add_reading(db_session, tank, -1000, START + timedelta(minutes=32))
    db_session.commit()
    trend = result(db_session, tank)['trend']
    assert trend['status'] == 'rising'
    assert trend['rate_per_hour'] == .2
    assert trend['fit_points'][1]['value'] == 24.1


@pytest.mark.parametrize('values,status', [([25] * 12, 'steady'),
    ([24,28,23,27,22,28,23,29,24,28,22,29], 'uncertain')])
def test_steady_and_oscillating(db_session, tank, values, status):
    series(db_session, tank, values)
    assert result(db_session, tank)['trend']['status'] == status


@pytest.mark.parametrize('skip,reason,count', [((1,2,3), 'too_few_buckets', 9),
                                             ((4,5), 'gap', 10), ((11,), 'not_recent', 11)])
def test_insufficient_coverage_reasons(db_session, tank, skip, reason, count):
    series(db_session, tank, skip=skip)
    trend = result(db_session, tank)['trend']
    assert trend['status'] == 'insufficient_data'
    assert trend['reason'] == reason
    assert trend['qualifying_buckets'] == count
    assert trend['required_buckets'] == 10
    assert trend['rate_per_hour'] is None and trend['sigma'] is None


def test_exact_ten_buckets_fit_when_gap_and_recent_gates_pass(db_session, tank):
    series(db_session, tank, skip=(2, 8))
    assert result(db_session, tank)['trend']['status'] == 'rising'


def test_mixed_source_even_in_unqualified_bucket(db_session, tank):
    devices(db_session, tank)
    series(db_session, tank, device='a')
    add_reading(db_session, tank, 25, START, device='b')
    db_session.commit()
    trend = result(db_session, tank)['trend']
    assert trend['status'] == 'insufficient_data' and trend['reason'] == 'mixed_source'


@pytest.mark.parametrize('real', [False, True])
def test_mock_fallback_and_real_preference(db_session, tank, real):
    series(db_session, tank, [27 - i * .1 for i in range(12)], mock=True)
    if real:
        series(db_session, tank)
    response = result(db_session, tank)
    assert response['trend']['status'] == ('rising' if real else 'falling')
    assert response['trend']['fit_points'][0]['value'] == (24 if real else 27)
    assert response['trend']['fit_points'][0]['count'] == 3
    assert response['observed']['value'] == (25.1 if real else 25.9)


def test_any_real_reading_filters_mock_at_tank_window_level(db_session, tank):
    series(db_session, tank, mock=True)
    # Infinity is not usable for temperature but still establishes a real tank source.
    add_reading(db_session, tank, float('inf'), START)
    db_session.commit()
    trend = result(db_session, tank)['trend']
    assert trend['reason'] == 'too_few_buckets'
    assert trend['qualifying_buckets'] == 0


@pytest.mark.parametrize('duplicate,per_bucket', [(True, 5), (False, 2)])
def test_requires_three_distinct_timestamps(db_session, tank, duplicate, per_bucket):
    series(db_session, tank, duplicate=duplicate, per_bucket=per_bucket, latest=False)
    assert result(db_session, tank)['trend']['qualifying_buckets'] == 0


def test_partial_bucket_excluded_and_observation_time_used(db_session, tank):
    series(db_session, tank, received=NOW - timedelta(seconds=10))
    for seconds in (20, 30, 40):
        add_reading(db_session, tank, 100, NOW + timedelta(minutes=5, seconds=seconds))
    db_session.commit()
    response = result(db_session, tank, now=NOW + timedelta(minutes=10))
    trend = response['trend']
    assert trend['qualifying_buckets'] == 12
    assert trend['rate_per_hour'] == .2
    assert all(point['t'] < NOW for point in trend['fit_points'])
    assert response['observed']['value'] == 100


@pytest.mark.parametrize('values,side,bound,distance,outside', [
    ([24 + i * .1 for i in range(12)], 'upper', 28, 2.9, False),
    ([24 - i * .1 for i in range(12)], 'lower', 20, 2.9, False),
    ([27] * 12, 'upper', 28, 1, False), ([21] * 12, 'lower', 20, 1, False),
    ([29] * 12, 'upper', 28, -1, True)])
def test_headroom_trend_nearest_and_outside(db_session, tank, values, side, bound, distance, outside):
    series(db_session, tank, values)
    assert result(db_session, tank)['headroom'] == dict(side=side, bound=bound, distance=distance,
                                                      outside=outside, reason=None)


def test_disabled_thresholds(db_session, tank):
    override(db_session, tank, enabled=False)
    series(db_session, tank)
    response = result(db_session, tank)
    assert response['headroom'] is None
    assert response['warning_bounds'] is None and response['critical_bounds'] is None


def test_override_and_missing_side(db_session, tank):
    override(db_session, tank, lower=23, upper=None)
    series(db_session, tank)
    response = result(db_session, tank)
    assert response['warning_bounds'] == dict(min=23, max=None)
    assert response['headroom']['reason'] == 'side_bound_missing'
    assert response['headroom']['distance'] is None


def test_thresholds_resolved_at_injected_now(db_session, tank):
    override(db_session, tank, upper=26)
    future = db_session.query(TankThresholdRevision).one()
    future.effective_from = NOW + timedelta(hours=1)
    db_session.commit()
    series(db_session, tank)
    assert result(db_session, tank)['warning_bounds']['max'] == 28


def test_species_overlap_compliance_inclusive_and_mock_selection(db_session, tank):
    assign(db_session, tank, 'First', ideal_temp_min=24, ideal_temp_max=26)
    assign(db_session, tank, 'Second', ideal_temp_min=25, ideal_temp_max=27)
    series(db_session, tank, [24] * 6 + [25] * 6)
    series(db_session, tank, [100] * 12, mock=True)
    species = result(db_session, tank)['species_range']
    assert species['status'] == 'ok'
    assert species['min'] == 25 and species['max'] == 26
    assert species['species_count'] == 2
    assert species['compliance_readings'] == 37
    assert species['compliance_percent_24h'] == round(100 * 19 / 37, 4)
    assert species['compliance_reason'] is None
    assert species['headroom']['distance'] == 0


def test_species_conflict_names(db_session, tank):
    assign(db_session, tank, 'Discus', ideal_temp_min=28, ideal_temp_max=31)
    assign(db_session, tank, 'Corydoras', ideal_temp_min=22, ideal_temp_max=26)
    species = result(db_session, tank)['species_range']
    assert species['status'] == 'conflict'
    assert species['conflict'] == dict(min_species='Discus', min=28, max_species='Corydoras', max=26)
    assert species['compliance_percent_24h'] is None


def test_species_not_configured_and_turbidity(db_session, tank):
    assert result(db_session, tank)['species_range']['status'] == 'not_configured'
    assign(db_session, tank)
    assert result(db_session, tank)['species_range']['status'] == 'not_configured'
    assert result(db_session, tank, 'turbidity')['species_range']['status'] == 'not_applicable'


@pytest.mark.parametrize('parameter,ranges,value', [('ph', dict(ideal_ph_min=7), 7),
                                                  ('tds', dict(ideal_tds_max=100), 100)])
def test_species_one_sided_ranges_and_low_coverage(db_session, tank, parameter, ranges, value):
    assign(db_session, tank, **ranges)
    series(db_session, tank, [value] * 12, per_bucket=2, parameter=parameter)
    species = result(db_session, tank, parameter)['species_range']
    assert species['status'] == 'ok'
    assert species['compliance_percent_24h'] is None
    assert species['compliance_reason'] == 'too_few_readings'
    assert species['compliance_readings'] == 25 and species['required_readings'] == 30


def test_species_compliance_mixed_source_and_24h_boundary(db_session, tank):
    assign(db_session, tank, ideal_temp_min=24, ideal_temp_max=26)
    devices(db_session, tank)
    series(db_session, tank, device='a')
    add_reading(db_session, tank, 25, NOW - timedelta(hours=24), device='b')
    add_reading(db_session, tank, 100, NOW - timedelta(hours=24, seconds=1), device='a')
    db_session.commit()
    species = result(db_session, tank)['species_range']
    assert species['compliance_readings'] == 38
    assert species['compliance_percent_24h'] is None and species['compliance_reason'] == 'mixed_source'


def test_no_readings_and_last_known_older_than_window(db_session, tank):
    assert result(db_session, tank)['observed'] is None
    assert result(db_session, tank)['headroom']['reason'] == 'value_unavailable'
    add_reading(db_session, tank, 23, NOW - timedelta(days=10))
    db_session.commit()
    response = ci.build_current_insights(db_session, [tank.id], now=NOW)
    assert response['tanks'][0]['latest']['is_current'] is False
    assert response['tanks'][0]['parameters'][0]['observed']['value'] == 23


def test_reading_queries_stream_columns_not_orm(db_session, tank):
    series(db_session, tank)
    extra = Tank(name='Second tank', location='Synthetic')
    db_session.add(extra)
    db_session.commit()
    series(db_session, extra)
    statements, loaded_readings = [], []
    def track_sql(conn, cursor, statement, parameters, context, executemany):
        if 'sensor_readings' in statement.lower():
            statements.append((statement, context.execution_options))
    def track_load(session, instance):
        if isinstance(instance, SensorReading):
            loaded_readings.append(instance)
    event.listen(db_session.bind, 'before_cursor_execute', track_sql)
    event.listen(db_session, 'loaded_as_persistent', track_load)
    try:
        ci.build_current_insights(db_session, now=NOW)
    finally:
        event.remove(db_session.bind, 'before_cursor_execute', track_sql)
        event.remove(db_session, 'loaded_as_persistent', track_load)
    assert len(statements) == 1
    assert all(options.get('yield_per') == 1000 for _, options in statements)
    assert not loaded_readings
    assert all('sample_id' not in statement and 'ammonia' not in statement for statement, _ in statements)


def test_endpoint_auth_scope_validation_and_stability_coverage(db_session, client, test_user, auth_headers, tank, monkeypatch):
    from app.routes import dashboard
    monkeypatch.setattr(dashboard, 'build_current_insights', partial(ci.build_current_insights, now=NOW))
    series(db_session, tank)
    retired = Tank(name='Retired', location='Synthetic', retired_at=NOW)
    db_session.add(retired)
    db_session.commit()
    assert client.get('/analytics/current-insights').status_code == 401
    for role in ('admin', 'staff'):
        test_user.role = role
        db_session.commit()
        response = client.get('/analytics/current-insights', headers=auth_headers)
        assert response.status_code == 200
        data = response.json()
        assert [t['tank_id'] for t in data['tanks']] == [tank.id]
        assert data['method_version'] == 'ci-v1'
        assert data['constants'] == dict(fit_hours=6, horizon_hours=3, baseline_days=7, bucket_minutes=30)
        assert len(data['tanks'][0]['parameters']) == 4
        assert data['attention'] == []
        for parameter in data['tanks'][0]['parameters']:
            assert parameter['stability']['status'] == 'insufficient_data'
            assert parameter['stability']['reason'] == 'too_few_buckets'
            assert parameter['stability']['current_buckets'] == 12
            assert parameter['stability']['baseline_days_covered'] == 0
            assert parameter['projection']['status'] == ('not_applicable' if parameter['parameter'] == 'turbidity' else 'no_crossing_within_horizon')
    for ident in (retired.id, 999999):
        assert client.get(f'/analytics/current-insights?tank_id={ident}', headers=auth_headers).status_code == 404
    assert client.get('/analytics/current-insights', params=[('tank_id', tank.id)] * 21,
                      headers=auth_headers).status_code == 422
    assert client.get(f'/analytics/current-insights?tank_id={tank.id}', headers=auth_headers).status_code == 200


@pytest.mark.parametrize('parameter', ['temperature', 'ph', 'tds'])
def test_steady_has_thirteen_band_points(db_session, tank, parameter):
    series(db_session, tank, [25 if parameter == 'temperature' else 7 if parameter == 'ph' else 100] * 12,
           parameter=parameter)
    projected = result(db_session, tank, parameter)['projection']
    assert projected['status'] == 'no_crossing_within_horizon'
    assert len(projected['band']) == 13
    assert [point['t'] for point in projected['band']] == [NOW + timedelta(minutes=i * 15) for i in range(13)]
    assert all(point['low'] == point['mid'] == point['high'] for point in projected['band'])
    assert projected['bound_side'] is None and projected['crossing_hours_low'] is None


@pytest.mark.parametrize('case,status,reason', [
    ('turbidity', 'not_applicable', None), ('stale', 'stale', None),
    ('insufficient', 'insufficient_data', 'too_few_buckets'),
    ('outside', 'already_outside', None), ('uncertain', 'too_uncertain', None),
    ('no_bound', 'no_bound', None)])
def test_projection_precondition_statuses(db_session, tank, case, status, reason):
    if case == 'turbidity':
        # No observations: not_applicable wins even over stale/insufficient.
        parameter = 'turbidity'
    else:
        parameter = 'temperature'
        values = ([29] * 12 if case == 'outside' else
                  [24,28,23,27,22,28,23,27,24,27,22,27] if case == 'uncertain' else None)
        series(db_session, tank, values, skip=(1,2,3) if case == 'insufficient' else (),
               received=NOW - timedelta(seconds=91) if case == 'stale' else None)
        if case == 'no_bound':
            override(db_session, tank, upper=None)
    projected = result(db_session, tank, parameter)['projection']
    assert projected['status'] == status and projected['reason'] == reason
    assert projected['band'] == []
    assert projected['crossing_hours_low'] is None


def test_stale_wins_over_insufficient_and_outside(db_session, tank):
    series(db_session, tank, [29] * 12, skip=(1,2,3), received=NOW - timedelta(seconds=91))
    response = result(db_session, tank)
    assert response['trend']['status'] == 'insufficient_data'
    assert response['projection']['status'] == 'stale'


def test_insufficient_wins_over_outside_and_copies_mixed_reason(db_session, tank):
    devices(db_session, tank)
    series(db_session, tank, [29] * 12, device='a')
    add_reading(db_session, tank, 29, START, device='b')
    db_session.commit()
    projected = result(db_session, tank)['projection']
    assert projected['status'] == 'insufficient_data' and projected['reason'] == 'mixed_source'


def test_outside_wins_over_uncertain_and_bound_is_inclusive(db_session, tank):
    values = [24,28,23,27,22,28,23,29,24,28,22,29]
    series(db_session, tank, values)
    response = result(db_session, tank)
    assert response['trend']['status'] == 'uncertain'
    assert response['projection']['status'] == 'already_outside'
    # The boundary itself is inside: strict comparison, as in the specified warning range.
    newest = db_session.query(SensorReading).order_by(SensorReading.received_at.desc()).first()
    newest.temperature = 28
    db_session.commit()
    assert result(db_session, tank)['projection']['status'] == 'too_uncertain'


def test_steady_wins_over_no_bound_and_uncertain_wins_over_no_bound(db_session, tank):
    override(db_session, tank, lower=None, upper=None)
    series(db_session, tank, [25] * 12)
    projected = result(db_session, tank)['projection']
    assert projected['status'] == 'no_crossing_within_horizon' and len(projected['band']) == 13
    db_session.query(SensorReading).delete()
    db_session.commit()
    series(db_session, tank, [24,28,23,27,22,28,23,27,24,27,22,27])
    assert result(db_session, tank)['projection']['status'] == 'too_uncertain'


@pytest.mark.parametrize('direction', [1, -1])
def test_projection_crossing_mirrors_upper_and_lower(db_session, tank, direction):
    base = 27.1 if direction == 1 else 20.9
    values = [base + direction * i * .06 + (i % 3 - 1) * .015 for i in range(12)]
    series(db_session, tank, values)
    response = result(db_session, tank)
    projected = response['projection']
    assert projected['status'] == 'crossing_projected'
    assert projected['bound_side'] == ('upper' if direction == 1 else 'lower')
    assert projected['bound'] == (28 if direction == 1 else 20)
    mid = next((point['t'] - NOW).total_seconds() / 3600 for point in projected['band']
               if (point['mid'] >= projected['bound'] if direction == 1 else point['mid'] <= projected['bound']))
    assert 0 <= projected['crossing_hours_low'] <= mid <= projected['crossing_hours_high'] <= 3
    band = projected['band']
    assert len(band) == 13
    assert all(point['low'] <= point['mid'] <= point['high'] for point in band)
    widths = [point['high'] - point['low'] for point in band]
    assert all(right >= left - .0001 for left, right in zip(widths, widths[1:]))
    assert widths[-1] > widths[0]


def test_rising_far_from_bound_still_returns_band(db_session, tank):
    series(db_session, tank)
    response = result(db_session, tank)
    assert response['trend']['status'] == 'rising'
    projected = response['projection']
    assert projected['status'] == 'no_crossing_within_horizon'
    assert len(projected['band']) == 13 and projected['bound'] == 28
    assert projected['crossing_hours_low'] is None and projected['crossing_hours_high'] is None


@pytest.mark.parametrize('direction', [1, -1])
def test_crossing_null_high_and_no_edge_only_crossing(direction):
    level = 27.6 if direction == 1 else 20.4
    fit = ci.Fit(.2 * direction, .08 if direction == 1 else -.4,
                 .4 if direction == 1 else -.08, level, .01, NOW, NOW)
    trend = dict(status='rising' if direction == 1 else 'falling', reason=None)
    projected = ci.projection('temperature', dict(is_current=True), level, dict(min=20, max=28), trend, fit, NOW)
    assert projected['status'] == 'crossing_projected'
    assert projected['crossing_hours_low'] == 1
    assert projected['crossing_hours_high'] is None
    far_level = 27 if direction == 1 else 21
    far_fit = ci.Fit(fit.slope, fit.low, fit.high, far_level, .01, NOW, NOW)
    projected = ci.projection('temperature', dict(is_current=True), far_level,
                              dict(min=20, max=28), trend, far_fit, NOW)
    assert projected['status'] == 'no_crossing_within_horizon'
    assert projected['crossing_hours_low'] is None
    assert any((point['high'] >= 28 if direction == 1 else point['low'] <= 20) for point in projected['band'])


def test_crossing_band_formulas_origin_and_hours_from_now():
    fit = ci.Fit(.2, .1, .3, 26.7, .02, START, NOW)
    evaluated = NOW + timedelta(minutes=10)
    projected = ci.projection('temperature', dict(is_current=True), 27.9,
                              dict(min=20, max=28), dict(status='rising'), fit, evaluated)
    assert projected['status'] == 'crossing_projected'
    assert projected['band'][0]['t'] == NOW
    for i, point in enumerate(projected['band']):
        h = i * .25
        assert point['mid'] == pytest.approx(27.9 + .2 * h)
        assert point['low'] == pytest.approx(27.9 + .1 * h - 1.645 * .02)
        assert point['high'] == pytest.approx(27.9 + .3 * h + 1.645 * .02)
    assert projected['crossing_hours_low'] == pytest.approx(.25 - 1/6)
    assert projected['crossing_hours_high'] == pytest.approx(1.5 - 1/6)
    # All crossings before evaluation are explicitly floored at zero.
    later = ci.projection('temperature', dict(is_current=True), 27.9,
                          dict(min=20, max=28), dict(status='rising'), fit, NOW + timedelta(hours=2))
    assert later['crossing_hours_low'] == later['crossing_hours_high'] == 0


@pytest.mark.parametrize('age,status', [(90, 'crossing_projected'), (91, 'stale')])
def test_perfect_trend_projection_requires_receipt_freshness(db_session, tank, age, status):
    series(db_session, tank, [27.1 + i * .06 for i in range(12)], received=NOW - timedelta(seconds=age))
    response = result(db_session, tank)
    assert response['trend']['status'] == 'rising'
    assert response['projection']['status'] == status


def test_recent_receipt_with_delayed_observation_uses_shared_freshness(db_session, tank):
    series(db_session, tank, [27.1 + i * .06 for i in range(12)], latest=False,
           received=NOW - timedelta(seconds=10))
    response = ci.build_current_insights(db_session, [tank.id], now=NOW)
    assert response['tanks'][0]['latest']['is_current'] is True
    assert response['tanks'][0]['parameters'][0]['projection']['status'] == 'crossing_projected'


def test_missing_latest_value_cannot_be_invented_from_fit(db_session, tank):
    series(db_session, tank)
    latest = db_session.query(SensorReading).order_by(SensorReading.received_at.desc()).first()
    latest.temperature = float('inf')
    db_session.commit()
    response = result(db_session, tank)
    assert response['trend']['status'] == 'rising'
    assert response['observed'] is None
    assert response['projection']['status'] == 'insufficient_data'
    assert response['projection']['reason'] == 'value_unavailable'


def test_endpoint_is_advisory_only_and_projects_attention(db_session, client, auth_headers, tank, monkeypatch):
    from app.routes import dashboard
    monkeypatch.setattr(dashboard, 'build_current_insights', partial(ci.build_current_insights, now=NOW))
    assign(db_session, tank, 'Warm', ideal_temp_min=28)
    assign(db_session, tank, 'Cool', ideal_temp_max=26)
    series(db_session, tank, [27.1 + i * .06 for i in range(12)])
    models = (Alert, PushNotificationEvent, MonitoringIncident)
    before = [db_session.query(model).count() for model in models]
    statements = []
    def record(conn, cursor, statement, parameters, context, executemany):
        statements.append(statement.strip().split()[0].upper())
    event.listen(db_session.bind, 'before_cursor_execute', record)
    try:
        for _ in range(2):
            response = client.get('/analytics/current-insights', headers=auth_headers)
            assert response.status_code == 200
            data = response.json()
            assert [item['type'] for item in data['attention']] == ['crossing_projected', 'species_conflict']
            assert all(item['tank_id'] == tank.id for item in data['attention'])
            assert data['tanks'][0]['parameters'][0]['projection']['status'] == 'crossing_projected'
    finally:
        event.remove(db_session.bind, 'before_cursor_execute', record)
    assert [db_session.query(model).count() for model in models] == before
    assert set(statements) == {'SELECT'}


def test_attention_ordering_ties_and_cap():
    def tank_insights(ident, low=None, ratio=None, conflict=False):
        return dict(tank_id=ident, tank_name=f'Tank {ident:02}', parameters=[dict(parameter='temperature',
            projection=dict(status='crossing_projected' if low is not None else 'stale',
                            crossing_hours_low=low, crossing_hours_high=None),
            stability=dict(status='more_variable' if ratio else 'insufficient_data', ratio=ratio),
            species_range=dict(status='conflict' if conflict else 'ok'))])
    tanks = [tank_insights(1, 2, 1.5, True), tank_insights(2, 1, 3, True), tank_insights(3, 1, 2)]
    attention = ci.attention_items(tanks[::-1])
    assert [(item['type'], item['tank_id']) for item in attention] == [
        ('crossing_projected', 2), ('crossing_projected', 3), ('crossing_projected', 1),
        ('more_variable', 2), ('more_variable', 3), ('more_variable', 1),
        ('species_conflict', 1), ('species_conflict', 2)]
    assert all(item['kind'] == ('projected' if item['type'] == 'crossing_projected' else 'derived')
               for item in attention)
    assert ci.attention_items([]) == []
    assert len(ci.attention_items([tank_insights(i, 1, 2, True) for i in range(11)])) == 10
    assert all(item['type'] == 'crossing_projected' for item in
               ci.attention_items([tank_insights(i, 1, 2, True) for i in range(11)]))


def test_attention_endpoint_ranks_crossings_before_species_conflicts(db_session, tank):
    other = Tank(name='Earlier', location='Synthetic')
    db_session.add(other)
    db_session.commit()
    series(db_session, tank, [27.1 + i * .06 for i in range(12)])
    series(db_session, other, [27.2 + i * .06 for i in range(12)])
    assign(db_session, other, 'Warm', ideal_temp_min=28)
    assign(db_session, other, 'Cool', ideal_temp_max=26)
    response = ci.build_current_insights(db_session, now=NOW)
    assert [(item['tank_id'], item['type']) for item in response['attention']] == [
        (other.id, 'crossing_projected'), (tank.id, 'crossing_projected'), (other.id, 'species_conflict')]
    assert not any(item['type'] == 'more_variable' for item in response['attention'])
    # Attention is built from evaluated scope only.
    response = ci.build_current_insights(db_session, [tank.id], now=NOW)
    assert all(item['tank_id'] == tank.id for item in response['attention'])
