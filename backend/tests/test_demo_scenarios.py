from collections import Counter
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import func, select

from app.models import RegisteredDevice, SensorReading, Tank, ThresholdRevision
from app.services.current_insights import (build_current_insights, DEPARTURE_SIGMAS,
                                          DEPARTURE_NOTABLE_FRACTION)
from app.services import current_insights as ci
from app.services.decision_engine import ensure_default_thresholds
from app.services.demo_sensor import write_demo_cycle
from seed import seed_dashboard_demo as demo
from app.services.demo_scenarios import (PARAMETERS, SCENARIOS, VARIABILITY_EPOCH, scenario_value,
    WARMING_CYCLE_SECONDS, WARMING_RISE_SECONDS, WARMING_RESET_SECONDS, WARMING_PHASE_SECONDS)
from seed.seed_fish import seed_fish_species
from seed.seed_tanks import seed_tanks


LIMITS = {'temperature': (22, 31, .2), 'ph': (6.4, 8.2, .1),
          'tds': (80, 450, 1), 'turbidity': (0, 25, 2)}


@pytest.mark.parametrize('code', SCENARIOS)
def test_curves_are_deterministic_plausible_and_continuous(code):
    # Every 30 s over two days, plus long-cycle transitions and a 14-day sweep.
    times = [VARIABILITY_EPOCH + timedelta(seconds=i * 30) for i in range(5760)]
    times += [VARIABILITY_EPOCH + timedelta(minutes=i * 30) for i in range(-14 * 48, 14 * 48)]
    times += [VARIABILITY_EPOCH + timedelta(days=d, seconds=s)
              for d in (-2, -1, 2, 3, 26) for s in (-30, -1, 0, 1, 30)]
    for parameter, (low, high, max_step) in LIMITS.items():
        for t in times:
            value = scenario_value(code, parameter, t)
            assert scenario_value(code, parameter, t) == value
            assert low <= value <= high
            assert abs(scenario_value(code, parameter, t + timedelta(seconds=30)) - value) <= max_step
    assert scenario_value(code, 'temperature', VARIABILITY_EPOCH.timestamp()) == scenario_value(
        code, 'temperature', VARIABILITY_EPOCH)


def test_warming_curves_have_third_cycle_phase_offsets_and_continuous_resets():
    assert WARMING_CYCLE_SECONDS == 34200
    assert WARMING_RISE_SECONDS == 32400
    assert WARMING_RESET_SECONDS == 1800
    assert set(WARMING_PHASE_SECONDS) == {code for code, role in SCENARIOS.items() if role == 'warming'}
    assert 'SHOW-BREED' not in SCENARIOS
    for code, offset in WARMING_PHASE_SECONDS.items():
        for hour in range(48):
            t = VARIABILITY_EPOCH + timedelta(hours=hour)
            assert scenario_value('SHOW-WARM-A', 'temperature', t + timedelta(seconds=offset)) == scenario_value(code, 'temperature', t)
        # Sweep every second on both sides of every rise/reset seam over two
        # days: transitions must meet the same 30-second plausibility limit.
        for cycle in range(6):
            origin = VARIABILITY_EPOCH + timedelta(seconds=cycle * WARMING_CYCLE_SECONDS - offset)
            assert scenario_value(code, 'temperature', origin) == pytest.approx(24.8)
            peak = origin + timedelta(seconds=WARMING_RISE_SECONDS)
            assert scenario_value(code, 'temperature', peak) == pytest.approx(28)
            assert scenario_value(code, 'temperature', origin + timedelta(seconds=WARMING_CYCLE_SECONDS)) == pytest.approx(24.8)
            for seam in (origin, peak):
                for second in range(-30, 31):
                    t = seam + timedelta(seconds=second)
                    assert abs(scenario_value(code, 'temperature', t + timedelta(seconds=30)) - scenario_value(code, 'temperature', t)) <= .2


def test_scenario_rejects_unknown_tanks_and_parameters():
    with pytest.raises(KeyError):
        scenario_value('HARDWARE-01', 'temperature', VARIABILITY_EPOCH)
    with pytest.raises(ValueError):
        scenario_value('SHOW-STABLE', 'oxygen', VARIABILITY_EPOCH)


@pytest.mark.parametrize('code', WARMING_PHASE_SECONDS)
def test_warming_crossings_follow_latest_observation_within_departure_tolerance(code):
    # Sweep all curve phases through the actual trend/projection functions,
    # including reset windows and evaluations between half-hour boundaries.
    statuses = Counter()
    for minute in range(0, 48 * 60, 15):
        now = VARIABILITY_EPOCH + timedelta(minutes=minute)
        end = ci.bucket_start(now)
        buckets = {}
        for start in range(end - ci.FIT_BUCKETS * ci.BUCKET_SECONDS, end, ci.BUCKET_SECONDS):
            timestamps = [ci.stamp(t) for t in range(start, start + ci.BUCKET_SECONDS, 30)]
            buckets[start] = ([scenario_value(code, 'temperature', t) for t in timestamps], set(timestamps))
        trend, fit = ci.build_trend('temperature', buckets, {(None, True)}, end)
        observed = scenario_value(code, 'temperature', now)
        projected = ci.projection('temperature', {'is_current': True}, observed,
                                  {'min': 24., 'max': 28.}, trend, fit, now)
        statuses[projected['status']] += 1
        statuses[projected['reason']] += 1
        if projected['status'] == 'crossing_projected':
            tolerance = max(DEPARTURE_SIGMAS * trend['sigma'],
                            DEPARTURE_NOTABLE_FRACTION * trend['notable_change'])
            assert abs(observed - trend['fitted_end']['value']) <= tolerance
    # The guard must be exercised as well as honest crossings, not pass vacuously.
    assert statuses['crossing_projected'] > 0
    assert statuses['recent_departure'] > 0


def test_demo_cycle_never_writes_active_device_unmapped_offline_or_retired_tanks(db_session):
    tanks = [Tank(name=name, location='Synthetic', tank_code=code, retired_at=retired)
             for name, code, retired in [('Real hardware', 'SHOW-STABLE', None),
                 ('Unmapped', 'REAL-01', None), ('Offline', 'SHOW-OFFLINE', None),
                 ('Retired', 'SHOW-WARM-A', VARIABILITY_EPOCH), ('Allowed', 'SHOW-PH', None)]]
    db_session.add_all(tanks)
    db_session.flush()
    db_session.add_all([RegisteredDevice(id='active', tank_id=tanks[0].id, key_hash='a' * 64),
                        RegisteredDevice(id='inactive', tank_id=tanks[4].id, key_hash='b' * 64, is_active=False)])
    db_session.commit()
    ensure_default_thresholds(db_session)
    assert write_demo_cycle(db_session, now=VARIABILITY_EPOCH) == 1
    readings = list(db_session.scalars(select(SensorReading)))
    assert len(readings) == 1
    reading = readings[0]
    assert reading.tank_id == tanks[4].id
    assert reading.is_mock is True
    assert reading.device_id is None
    for parameter in PARAMETERS:
        assert getattr(reading, parameter) == scenario_value('SHOW-PH', parameter, VARIABILITY_EPOCH)


def test_demo_cycle_rechecks_device_after_candidate_selection(db_session, monkeypatch):
    from app.services import demo_sensor
    tank = Tank(name='New device', location='Synthetic', tank_code='SHOW-STABLE')
    db_session.add(tank)
    db_session.commit()
    original = demo_sensor.lock_tank_for_mutation

    def provision_before_lock(db, tank_id):
        db.add(RegisteredDevice(id='new', tank_id=tank_id, key_hash='c' * 64))
        db.commit()
        return original(db, tank_id)

    monkeypatch.setattr(demo_sensor, 'lock_tank_for_mutation', provision_before_lock)
    assert write_demo_cycle(db_session, now=VARIABILITY_EPOCH) == 0
    assert db_session.scalar(select(func.count(SensorReading.id))) == 0


def test_seed_does_not_fill_unmapped_or_active_device_tanks(db_session):
    seed_tanks(db_session)
    seed_fish_species(db_session)
    db_session.flush()
    hardware = db_session.scalar(select(Tank).where(Tank.tank_code == 'SHOW-STABLE'))
    unmapped = Tank(name='Customer', location='Synthetic', tank_code='CUSTOM-01')
    db_session.add(unmapped)
    db_session.add(RegisteredDevice(id='real', tank_id=hardware.id, key_hash='d' * 64))
    db_session.commit()
    demo.seed_dashboard_demo(db_session, history_days=1, interval_seconds=43200)
    for tank in (hardware, unmapped):
        assert db_session.scalar(select(func.count(SensorReading.id)).where(SensorReading.tank_id == tank.id)) == 0


def test_seed_and_live_curve_join_exactly(db_session, monkeypatch):
    seed_tanks(db_session)
    seed_fish_species(db_session)
    ensure_default_thresholds(db_session)
    monkeypatch.setattr(demo, '_rounded_now', lambda: VARIABILITY_EPOCH)
    demo.seed_dashboard_demo(db_session, history_days=1, interval_seconds=300)
    next_time = VARIABILITY_EPOCH + timedelta(seconds=30)
    assert write_demo_cycle(db_session, now=next_time) == 6
    for tank in db_session.scalars(select(Tank)):
        if SCENARIOS[tank.tank_code] == 'offline':
            continue
        readings = list(db_session.scalars(select(SensorReading).where(SensorReading.tank_id == tank.id)
                            .order_by(SensorReading.timestamp.desc()).limit(2)))
        for parameter in PARAMETERS:
            assert getattr(readings[0], parameter) == scenario_value(tank.tank_code, parameter, next_time)
            assert getattr(readings[1], parameter) == scenario_value(tank.tank_code, parameter, VARIABILITY_EPOCH)


@pytest.mark.parametrize('seed_kind', ['local', 'exhibit'])
def test_seeded_roles_at_24_evenly_spaced_times_across_day(db_session, monkeypatch, seed_kind):
    from app.cli.exhibit_demo import seed as seed_exhibit
    if seed_kind == 'local':
        seed_tanks(db_session)
        seed_fish_species(db_session)
    ensure_default_thresholds(db_session)
    for revision in db_session.scalars(select(ThresholdRevision)):
        revision.effective_from = VARIABILITY_EPOCH - timedelta(days=20)
    db_session.commit()
    # Both complete exhibit days have eight days of prior coverage. Use the
    # actual 30-second cadence: local reporting-gap offsets are sample-based,
    # so a reduced cadence would distort their duration and measured coverage.
    end = VARIABILITY_EPOCH + timedelta(days=2)
    if seed_kind == 'local':
        monkeypatch.setattr(demo, '_rounded_now', lambda: end)
        demo.seed_dashboard_demo(db_session, history_days=10, interval_seconds=30)
    else:
        seed_exhibit(db_session, days=10, now=end)
    ids = {tank.tank_code: tank.id for tank in db_session.scalars(select(Tank))}
    coverage = [Counter(), Counter()]
    for hour in range(48):
        now = VARIABILITY_EPOCH + timedelta(hours=hour)
        day_coverage = coverage[hour // 24]
        response = build_current_insights(db_session, now=now)
        tanks = {tank['tank_id']: {p['parameter']: p for p in tank['parameters']} for tank in response['tanks']}
        crossings = []
        for code in WARMING_PHASE_SECONDS:
            parameter = tanks[ids[code]]['temperature']
            crossing = parameter['projection']['status'] == 'crossing_projected'
            if crossing:
                trend = parameter['trend']
                tolerance = max(DEPARTURE_SIGMAS * trend['sigma'],
                                DEPARTURE_NOTABLE_FRACTION * trend['notable_change'])
                assert abs(parameter['observed']['value'] - trend['fitted_end']['value']) <= tolerance
            day_coverage[code] += crossing
            crossings.append(crossing)
        day_coverage['combined'] += any(crossings)
        unstable = tanks[ids['SHOW-PH']]['ph']['stability']
        day_coverage['unstable_ph'] += unstable['status'] == 'more_variable'
        assert unstable['ratio'] == pytest.approx(2.5, abs=.02)
        stable = tanks[ids['SHOW-STABLE']]['temperature']
        assert stable['trend']['status'] == 'steady'
        assert stable['stability']['status'] == 'typical'
        assert stable['species_range']['status'] == 'ok'
        assert tanks[ids['SHOW-SPECIES']]['temperature']['species_range']['conflict'] == dict(
            min_species='Discus', min=28., max_species='Corydoras Catfish', max=27.)
        for parameter in ('temperature', 'ph', 'tds'):
            species = tanks[ids['SHOW-WARM-C']][parameter]['species_range']
            assert species['status'] == 'ok'
            assert species['compliance_percent_24h'] == 100
        assert any(item['type'] == 'more_variable' and item['tank_id'] == ids['SHOW-PH']
                   for item in response['attention'])
    for day, day_coverage in enumerate(coverage):
        print(f'{seed_kind} {(VARIABILITY_EPOCH + timedelta(days=day)).date()} scenario coverage:', dict(day_coverage))
        assert day_coverage['combined'] / 24 >= .8
        assert day_coverage['unstable_ph'] / 24 >= .8
