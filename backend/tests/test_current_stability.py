from datetime import timedelta
from functools import partial

import pytest
from sqlalchemy import event, func, select

from app.models import Alert, MonitoringIncident, PushNotificationEvent
from app.services import current_insights as ci
from tests.test_current_insights import NOW, add_reading, devices, result, tank


END = ci.bucket_start(NOW)
CURRENT = END - 48 * 1800
BASELINE = CURRENT - 7 * 86400


def buckets(*, current=.2, baseline=.1, current_count=48, days=7, drift=False):
    points = {}
    for key in range(BASELINE, END, 1800):
        if key < CURRENT and key >= BASELINE + days * 86400:
            continue
        if key >= CURRENT and key >= CURRENT + current_count * 1800:
            continue
        spread = baseline if key < CURRENT else current
        index = (key - BASELINE) // 1800
        value = 25 + index * .01 if drift else 25 + (index % 2) * spread
        points[key] = ([value] * 3, {key, key + 30, key + 60})
    return points


@pytest.mark.parametrize('change,status,ratio', [(.2, 'more_variable', 2),
                                               (.1, 'typical', 1), (.05, 'steadier', .5)])
def test_stability_labels_and_inclusive_boundaries(change, status, ratio):
    value = ci.build_stability('temperature', buckets(current=change), {(None, True)}, END)
    assert value['status'] == status
    assert value['ratio'] == pytest.approx(ratio)
    assert value['current_spread'] == pytest.approx(change)
    assert value['baseline_spread'] == pytest.approx(.1)
    assert value['current_buckets'] == 48
    assert value['baseline_days_covered'] == 8  # Two half UTC dates each meet the 24-bucket gate.
    assert value['reason'] is None


@pytest.mark.parametrize('current,baseline,status', [(.1875, .125, 'more_variable'),
                                                    (.67, 1., 'steadier')])
def test_exact_ratio_boundaries(current, baseline, status):
    points = buckets(current=current, baseline=baseline)
    # Avoid decimal subtraction at a large level moving a nominal boundary.
    for key, (_, times) in points.items():
        change = current if key >= CURRENT else baseline
        points[key] = ([((key - BASELINE) // 1800 % 2) * change] * 3, times)
    assert ci.build_stability('temperature', points, {(None, True)}, END)['status'] == status


def test_slow_drift_is_not_more_variable():
    value = ci.build_stability('temperature', buckets(drift=True), {(None, True)}, END)
    assert value['current_spread'] == pytest.approx(.01)
    assert value['baseline_spread'] == pytest.approx(.01)
    assert value['status'] == 'steadier'  # Floor prevents over-interpreting tiny changes.


@pytest.mark.parametrize('parameter,floor', ci.SPREAD_FLOOR.items())
def test_spread_floor_with_zero_baseline(parameter, floor):
    value = ci.build_stability(parameter, buckets(current=2 * floor, baseline=0), {(None, True)}, END)
    assert value['status'] == 'more_variable'
    assert value['baseline_spread'] == 0
    assert value['ratio'] == pytest.approx(2)


def test_current_and_baseline_coverage_gates_report_counts():
    value = ci.build_stability('temperature', buckets(current_count=35), {(None, True)}, END)
    assert value['status'] == 'insufficient_data'
    assert value['reason'] == 'too_few_buckets'
    assert value['current_buckets'] == 35
    assert value['ratio'] is None
    value = ci.build_stability('temperature', buckets(days=3), {(None, True)}, END)
    assert value['status'] == 'insufficient_baseline'
    assert value['reason'] == 'too_few_days'
    # Window begins at noon: partial UTC dates qualify at exactly 24 buckets.
    assert value['baseline_days_covered'] == 4  # Three rolling days touch four UTC dates.


def test_baseline_exactly_five_utc_days_is_enough():
    points = buckets(days=4)
    value = ci.build_stability('temperature', points, {(None, True)}, END)
    assert value['status'] == 'more_variable'
    assert value['baseline_days_covered'] == 5


def test_minimum_current_coverage_and_23_bucket_days():
    value = ci.build_stability('temperature', buckets(current_count=36), {(None, True)}, END)
    assert value['status'] == 'more_variable'
    assert value['current_buckets'] == 36
    points = buckets()
    days = {}
    for key in list(points):
        if key < CURRENT:
            day = ci.stamp(key).date()
            days[day] = days.get(day, 0) + 1
            if days[day] > 23:
                del points[key]
    value = ci.build_stability('temperature', points, {(None, True)}, END)
    assert value['status'] == 'insufficient_baseline'
    assert value['baseline_days_covered'] == 0


def test_only_exactly_adjacent_pairs_contribute_and_no_cross_window_pair():
    points = buckets()
    # One isolated large baseline point must not become a change across a gap.
    isolated = BASELINE + 60 * 1800
    for key in (isolated - 1800, isolated + 1800):
        del points[key]
    points[isolated] = ([1000] * 3, {1, 2, 3})
    # Moving the entire current level adds no spread at the baseline/current seam.
    for key, (values, times) in list(points.items()):
        if key >= CURRENT:
            points[key] = ([v + 100 for v in values], times)
    value = ci.build_stability('temperature', points, {(None, True)}, END)
    assert value['baseline_spread'] == pytest.approx(.1)
    assert value['current_spread'] == pytest.approx(.2)
    assert value['status'] == 'more_variable'


def test_days_need_24_qualifying_buckets_and_no_adjacency_is_explicit():
    points = buckets()
    for key in list(points):
        if key < CURRENT and (key - BASELINE) // 1800 % 2 == 0:
            del points[key]
    value = ci.build_stability('temperature', points, {(None, True)}, END)
    assert value['baseline_days_covered'] >= 5
    assert value['status'] == 'insufficient_baseline'
    assert value['reason'] == 'no_adjacent_buckets'
    assert value['baseline_spread'] is None


def test_distinct_timestamps_and_mixed_sources_have_priority():
    points = buckets()
    for key in list(points):
        if key >= CURRENT:
            points[key] = ([25] * 60, {key, key + 30})
    value = ci.build_stability('temperature', points, {(None, True), ('a', True)}, END)
    assert value['current_buckets'] == 0
    assert value['reason'] == 'mixed_source'
    value = ci.build_stability('temperature', points, {(None, True)}, END)
    assert value['reason'] == 'too_few_buckets'


def test_stability_mock_filter_is_tank_wide_and_spans_both_windows(db_session, tank):
    for key, (values, times) in buckets().items():
        for timestamp in times:
            add_reading(db_session, tank, values[0], ci.stamp(timestamp), mock=True)
    db_session.commit()
    assert result(db_session, tank)['stability']['status'] == 'more_variable'
    # A single invalid real parameter still suppresses mocks tank-wide over all eight days.
    add_reading(db_session, tank, float('inf'), NOW - timedelta(days=7), mock=False)
    db_session.commit()
    value = result(db_session, tank)['stability']
    assert value['current_buckets'] == 0
    assert value['reason'] == 'too_few_buckets'


def test_source_change_between_current_and_baseline_suppresses_stability(db_session, tank):
    devices(db_session, tank)
    for key, (values, times) in buckets().items():
        for timestamp in times:
            add_reading(db_session, tank, values[0], ci.stamp(timestamp),
                        device='a' if key < CURRENT else 'b')
    db_session.commit()
    value = result(db_session, tank)['stability']
    assert value['current_buckets'] == 48
    assert value['reason'] == 'mixed_source'


def test_aligned_start_and_partial_end_with_delayed_receipt(db_session, tank):
    now = NOW + timedelta(minutes=17)
    for key, (values, times) in buckets().items():
        for timestamp in times:
            add_reading(db_session, tank, values[0], ci.stamp(timestamp), received=now)
    # Receipt time must not move this partial bucket into the complete window.
    for seconds in (0, 30, 60):
        add_reading(db_session, tank, 100, NOW + timedelta(seconds=seconds), received=now)
    db_session.commit()
    value = result(db_session, tank, now=now)['stability']
    assert value['current_buckets'] == 48
    assert value['baseline_days_covered'] == 8
    assert value['ratio'] == pytest.approx(2)


def test_more_variable_attention_endpoint_is_read_only(db_session, tank, client, auth_headers, monkeypatch):
    from app.routes import dashboard
    for key, (values, times) in buckets().items():
        for timestamp in times:
            add_reading(db_session, tank, values[0], ci.stamp(timestamp), mock=True)
    db_session.commit()
    monkeypatch.setattr(dashboard, 'build_current_insights', partial(ci.build_current_insights, now=NOW))
    models = (Alert, PushNotificationEvent, MonitoringIncident)
    before = [db_session.scalar(select(func.count()).select_from(model)) for model in models]
    statements = []

    def track(conn, cursor, statement, parameters, context, executemany):
        statements.append(statement.lstrip().split()[0].upper())

    event.listen(db_session.bind, 'before_cursor_execute', track)
    try:
        response = client.get('/analytics/current-insights', headers=auth_headers)
    finally:
        event.remove(db_session.bind, 'before_cursor_execute', track)
    assert response.status_code == 200
    assert any(item['type'] == 'more_variable' for item in response.json()['attention'])
    assert set(statements) == {'SELECT'}
    assert [db_session.scalar(select(func.count()).select_from(model)) for model in models] == before
