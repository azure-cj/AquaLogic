from collections import Counter
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import func, select

from app.models import RegisteredDevice, SensorReading, Tank, ThresholdRevision
from app.services.current_insights import build_current_insights
from app.services.decision_engine import ensure_default_thresholds
from app.services.demo_sensor import write_demo_cycle
from seed import seed_dashboard_demo as demo
from seed.demo_scenarios import PARAMETERS, SCENARIOS, VARIABILITY_EPOCH, scenario_value
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


def test_warming_curves_have_half_cycle_phase_offset():
    for hour in range(24):
        t = VARIABILITY_EPOCH + timedelta(hours=hour)
        assert scenario_value('DISPLAY-02', 'temperature', t + timedelta(hours=4)) == scenario_value(
            'RACK-02', 'temperature', t)


def test_scenario_rejects_unknown_tanks_and_parameters():
    with pytest.raises(KeyError):
        scenario_value('HARDWARE-01', 'temperature', VARIABILITY_EPOCH)
    with pytest.raises(ValueError):
        scenario_value('DISPLAY-01', 'oxygen', VARIABILITY_EPOCH)


def test_demo_cycle_never_writes_active_device_unmapped_offline_or_retired_tanks(db_session):
    tanks = [Tank(name=name, location='Synthetic', tank_code=code, retired_at=retired)
             for name, code, retired in [('Real hardware', 'DISPLAY-01', None),
                 ('Unmapped', 'REAL-01', None), ('Offline', 'SERVICE-01', None),
                 ('Retired', 'DISPLAY-02', VARIABILITY_EPOCH), ('Allowed', 'BREED-02', None)]]
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
        assert getattr(reading, parameter) == scenario_value('BREED-02', parameter, VARIABILITY_EPOCH)


def test_demo_cycle_rechecks_device_after_candidate_selection(db_session, monkeypatch):
    from app.services import demo_sensor
    tank = Tank(name='New device', location='Synthetic', tank_code='DISPLAY-01')
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
    hardware = db_session.scalar(select(Tank).where(Tank.tank_code == 'DISPLAY-01'))
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


def test_seeded_roles_at_24_evenly_spaced_times_across_day(db_session, monkeypatch):
    seed_tanks(db_session)
    seed_fish_species(db_session)
    ensure_default_thresholds(db_session)
    for revision in db_session.scalars(select(ThresholdRevision)):
        revision.effective_from = VARIABILITY_EPOCH - timedelta(days=20)
    db_session.commit()
    # Nine days retain full current+baseline coverage at every sampled time.
    # Five-minute cadence gives six distinct readings per bucket and uses the
    # identical production scenario function and seed bulk-insert path.
    monkeypatch.setattr(demo, '_rounded_now', lambda: VARIABILITY_EPOCH + timedelta(days=1))
    demo.seed_dashboard_demo(db_session, history_days=9, interval_seconds=300)
    ids = {tank.tank_code: tank.id for tank in db_session.scalars(select(Tank))}
    coverage = Counter()
    for hour in range(24):
        now = VARIABILITY_EPOCH + timedelta(hours=hour)
        response = build_current_insights(db_session, now=now)
        tanks = {tank['tank_id']: {p['parameter']: p for p in tank['parameters']} for tank in response['tanks']}
        crossings = []
        for code in ('DISPLAY-02', 'RACK-02'):
            crossing = tanks[ids[code]]['temperature']['projection']['status'] == 'crossing_projected'
            coverage[code] += crossing
            crossings.append(crossing)
        coverage['combined'] += any(crossings)
        unstable = tanks[ids['BREED-02']]['ph']['stability']
        coverage['unstable_ph'] += unstable['status'] == 'more_variable'
        assert unstable['ratio'] == pytest.approx(2.5, abs=.02)
        stable = tanks[ids['DISPLAY-01']]['temperature']
        assert stable['trend']['status'] == 'steady'
        assert stable['stability']['status'] == 'typical'
        assert stable['species_range']['status'] == 'ok'
        assert tanks[ids['RACK-01']]['temperature']['species_range']['conflict'] == dict(
            min_species='Discus', min=28., max_species='Corydoras Catfish', max=27.)
        assert any(item['type'] == 'more_variable' and item['tank_id'] == ids['BREED-02']
                   for item in response['attention'])
    print('24-hour scenario coverage:', dict(coverage))
    assert coverage['combined'] / 24 >= .8
    assert coverage['unstable_ph'] / 24 >= .8
