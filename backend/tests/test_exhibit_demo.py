from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from contextlib import contextmanager
import importlib

import pytest
from sqlalchemy import func, select

from app import config
from app.cli import exhibit_demo as cli
from app.models import (Alert, AlertSeverity, FishSpecies, MonitoringIncident, PushNotificationEvent,
                        RegisteredDevice, SensorReading, Tank, ThresholdConfig, User)
from app.services import demo_sensor, demo_scenarios, current_insights as ci

NOW = datetime(2026, 10, 13, 12, tzinfo=timezone.utc)


def count(db, model):
    return db.scalar(select(func.count()).select_from(model))


def reading(db, tank, *, mock=False, device_id=None):
    row = SensorReading(tank_id=tank.id, timestamp=NOW, received_at=NOW,
                        temperature=25, ph=7, tds=120, turbidity=2, is_mock=mock, device_id=device_id)
    db.add(row)
    db.flush()
    return row


def test_scoped_seed_preserves_real_tanks_species_devices_and_other_tables(db_session):
    real = Tank(name='Real aquarium', tank_code='REAL-01', location='Store')
    db_session.add(real)
    db_session.flush()
    device = RegisteredDevice(id='hardware', tank_id=real.id, key_hash='a' * 64)
    db_session.add(device)
    original = reading(db_session, real, device_id=device.id)
    fish = FishSpecies(common_name='Guppy', scientific_name='Existing values', ideal_temp_min=19)
    db_session.add(fish)
    db_session.commit()
    original_id = original.id
    inserted = cli.seed(db_session, days=1, now=NOW)
    assert inserted == 7 * 2881 - 20
    tanks = list(db_session.scalars(select(Tank).where(Tank.id != real.id)))
    assert {tank.tank_code for tank in tanks} == set(demo_scenarios.SCENARIOS)
    assert all(t.tank_code.startswith('SHOW-') and not t.is_public and t.name.startswith('Showcase · ') for t in tanks)
    assert all(row.is_mock and row.device_id is None for row in db_session.scalars(
        select(SensorReading).where(SensorReading.tank_id != real.id)))
    for tank in tanks:
        rows = list(db_session.scalars(select(SensorReading).where(SensorReading.tank_id == tank.id)
                                     .order_by(SensorReading.timestamp).limit(2)))
        assert rows[1].timestamp - rows[0].timestamp == timedelta(seconds=30)
        assert rows[0].timestamp.replace(tzinfo=timezone.utc) == NOW - timedelta(days=1)
        latest = db_session.scalar(select(func.max(SensorReading.timestamp)).where(SensorReading.tank_id == tank.id))
        assert latest.replace(tzinfo=timezone.utc) == NOW - (timedelta(minutes=10) if tank.tank_code == 'SHOW-OFFLINE' else timedelta(0))
        for row in rows:
            for parameter in demo_scenarios.PARAMETERS:
                assert getattr(row, parameter) == demo_scenarios.scenario_value(tank.tank_code, parameter, row.timestamp)
    assert db_session.get(SensorReading, original_id).device_id == 'hardware'
    assert count(db_session, RegisteredDevice) == 1
    assert db_session.get(FishSpecies, fish.id).ideal_temp_min == 19
    for model in (User, ThresholdConfig, Alert, PushNotificationEvent, MonitoringIncident):
        assert count(db_session, model) == 0


def test_seed_refuses_rerun_and_replace_changes_only_show_readings(db_session):
    cli.seed(db_session, days=1, now=NOW)
    real = Tank(name='Not showcase', location='Store', tank_code='REAL-02')
    db_session.add(real)
    db_session.flush()
    original_id = reading(db_session, real).id
    db_session.commit()
    before = count(db_session, SensorReading)
    with pytest.raises(cli.ExhibitError, match='--replace'):
        cli.seed(db_session, days=1, now=NOW)
    db_session.rollback()
    assert count(db_session, SensorReading) == before
    cli.seed(db_session, days=1, replace=True, now=NOW + timedelta(days=1))
    assert count(db_session, SensorReading) == before
    assert db_session.get(SensorReading, original_id).timestamp.replace(tzinfo=timezone.utc) == NOW
    assert count(db_session, Tank) == 8


def test_cleanup_uses_shared_deletion_and_leaves_nonshow_and_species(db_session, monkeypatch):
    cli.seed(db_session, days=1, now=NOW)
    show = db_session.scalar(select(Tank).where(Tank.tank_code == 'SHOW-STABLE'))
    real = Tank(name='Real', location='Store', tank_code='REAL-03')
    db_session.add(real)
    db_session.flush()
    real_row = reading(db_session, real)
    for tank in (real, show):
        db_session.add(Alert(tank_id=tank.id, severity=AlertSeverity.warning, parameter='ph', message='fixture'))
    db_session.commit()
    species_count = count(db_session, FishSpecies)
    real_id, real_row_id = real.id, real_row.id
    calls = []
    original = cli.stage_retired_tank_deletion
    def tracked(db, tank):
        calls.append(tank.tank_code)
        assert tank.retired_at is not None
        return original(db, tank)
    monkeypatch.setattr(cli, 'stage_retired_tank_deletion', tracked)
    assert cli.cleanup(db_session, now=NOW) == 7
    assert set(calls) == set(demo_scenarios.SCENARIOS)
    assert count(db_session, Tank) == 1
    assert count(db_session, SensorReading) == 1
    assert count(db_session, Alert) == 1
    assert count(db_session, FishSpecies) == species_count
    assert db_session.get(Tank, real_id).retired_at is None
    assert db_session.get(SensorReading, real_row_id) is not None
    assert cli.cleanup(db_session) == 0


@pytest.mark.parametrize('operation', ['seed', 'cleanup'])
def test_active_show_hardware_refuses_entire_operation(db_session, operation):
    allowed = Tank(name='Allowed', location='Test', tank_code='SHOW-STABLE')
    hardware = Tank(name='Hardware', location='Test', tank_code='SHOW-PH')
    db_session.add_all([allowed, hardware])
    db_session.flush()
    db_session.add(RegisteredDevice(id='active', tank_id=hardware.id, key_hash='b' * 64))
    row_id = reading(db_session, hardware).id
    db_session.commit()
    with pytest.raises(cli.ExhibitError, match='active device'):
        if operation == 'seed':
            cli.seed(db_session, days=1, replace=True, now=NOW)
        else:
            cli.cleanup(db_session)
    db_session.rollback()
    assert count(db_session, Tank) == 2
    assert count(db_session, SensorReading) == 1
    assert db_session.get(SensorReading, row_id) is not None
    assert db_session.get(RegisteredDevice, 'active').is_active
    assert allowed.retired_at is None


def test_seed_refuses_real_readings_even_with_inactive_device(db_session):
    tank = Tank(name='Former hardware', location='Test', tank_code='SHOW-PH')
    db_session.add(tank)
    db_session.flush()
    reading(db_session, tank)
    db_session.commit()
    with pytest.raises(cli.ExhibitError, match='real/device readings'):
        cli.seed(db_session, days=1, replace=True)
    db_session.rollback()
    assert count(db_session, SensorReading) == 1


def test_status_and_cli_exit_codes(db_session):
    db_session.add(Tank(name='Unpopulated show', tank_code='SHOW-EMPTY', location='Test'))
    db_session.add(Tank(name='Hidden real', tank_code='REAL-04', location='Store'))
    db_session.commit()
    @contextmanager
    def factory():
        yield db_session
    output = []
    assert cli.main(['status'], session_factory=factory, stdout=output.append) == 0
    assert 'EXHIBIT_DEMO_UNTIL=' in output[0]
    assert 'SHOW-EMPTY' in output[1] and 'readings=0' in output[1]
    assert all('REAL-04' not in line for line in output)
    assert cli.main(['seed', '--days', '0'], session_factory=factory, stderr=output.append) == 2
    assert count(db_session, Tank) == 2


@pytest.fixture
def production_environment(monkeypatch):
    for name in ('EXHIBIT_DEMO_UNTIL', 'DEMO_SENSOR_ENABLED', 'DEMO_SENSOR_INSTANCE', 'DEBUG', 'DEMO_EXHIBIT_DATE'):
        monkeypatch.delenv(name, raising=False)
    for name, value in dict(ENVIRONMENT='production', DATABASE_URL='postgresql://a:b@db.example/aqualogic',
                            JWT_SECRET_KEY='Postgres-Ready!Secret-2026-Qwerty',
                            CORS_ORIGINS='https://example.com', TRUSTED_HOSTS='api.example.com').items():
        monkeypatch.setenv(name, value)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


@pytest.mark.parametrize('flag', ['DEMO_SENSOR_ENABLED', 'DEMO_SENSOR_INSTANCE'])
@pytest.mark.parametrize('offset', [None, 8, 'bad', 'naive', 'nonutc'])
def test_production_demo_rejects_invalid_deadline(production_environment, monkeypatch, flag, offset):
    monkeypatch.setenv(flag, 'true')
    if offset is not None:
        value = ((datetime.now(timezone.utc) + timedelta(days=offset)).isoformat()
                 if isinstance(offset, int) else {'bad': 'not-a-date', 'naive': '2030-01-01T00:00:00',
                                                  'nonutc': '2030-01-01T00:00:00+01:00'}[offset])
        monkeypatch.setenv('EXHIBIT_DEMO_UNTIL', value)
    with pytest.raises(ValueError, match='Production requires DEBUG and demo generation to be disabled'):
        config.get_settings()


@pytest.mark.parametrize('flags', [(True, True), (True, False), (False, True)])
@pytest.mark.parametrize('offset_seconds', [-86400, 0])
def test_expired_production_settings_startup_without_demo_thread_or_writes(
    production_environment, db_session, client, monkeypatch, caplog, flags, offset_seconds
):
    import anyio
    from app import main as app_main
    class Clock(datetime):
        @staticmethod
        def now(tz): return NOW
    monkeypatch.setattr(config, 'datetime', Clock)
    monkeypatch.setattr(demo_sensor, 'datetime', Clock)
    monkeypatch.setenv('DEMO_SENSOR_ENABLED', str(flags[0]))
    monkeypatch.setenv('DEMO_SENSOR_INSTANCE', str(flags[1]))
    monkeypatch.setenv('EXHIBIT_DEMO_UNTIL', (NOW + timedelta(seconds=offset_seconds)).isoformat())
    with caplog.at_level('WARNING', logger='app.config'):
        loaded = config.get_settings()
        assert config.get_settings() is loaded  # Cached startup emits only one warning.
    assert [record.getMessage() for record in caplog.records if record.name == 'app.config'] == [
        'Exhibit demo window expired; demo writer disabled. Remove DEMO_SENSOR_* and EXHIBIT_DEMO_UNTIL.']
    monkeypatch.setattr(app_main, 'settings', loaded)
    monkeypatch.setattr(demo_sensor, 'settings', loaded)
    def unexpected_thread(*args, **kwargs):
        pytest.fail('Expired exhibit must not construct a demo thread')
    monkeypatch.setattr(demo_sensor.threading, 'Thread', unexpected_thread)
    stopped = []
    monkeypatch.setattr(app_main, 'start_periodic_maintenance',
                        lambda: SimpleNamespace(stop=lambda: stopped.append(True)))
    monkeypatch.setattr(app_main, 'start_push_dispatcher', lambda: None)
    db_session.add(Tank(name='Expired show', tank_code='SHOW-STABLE', location='Test'))
    db_session.commit()
    async def startup():
        async with app_main.app.router.lifespan_context(app_main.app):
            assert demo_sensor.write_demo_cycle(db_session, now=NOW) == 0
    anyio.run(startup)
    assert stopped == [True]
    assert client.get('/health').status_code == 200
    assert count(db_session, SensorReading) == 0
    monkeypatch.setenv('DEBUG', 'true')
    config.get_settings.cache_clear()
    with pytest.raises(ValueError, match='Production requires DEBUG'):
        config.get_settings()


@pytest.mark.parametrize('days', [1, 7])
def test_production_exhibit_accepts_valid_deadline_but_never_debug(production_environment, monkeypatch, days):
    monkeypatch.setenv('DEMO_SENSOR_ENABLED', 'true')
    monkeypatch.setenv('DEMO_SENSOR_INSTANCE', 'true')
    until = datetime.now(timezone.utc) + timedelta(days=days)
    monkeypatch.setenv('EXHIBIT_DEMO_UNTIL', until.isoformat().replace('+00:00', 'Z'))
    settings = config.get_settings()
    assert settings.exhibit_demo_until == until
    assert settings.demo_exhibit_date.isoformat() == '2026-10-13'
    monkeypatch.setenv('DEBUG', 'true')
    config.get_settings.cache_clear()
    with pytest.raises(ValueError, match='Production requires DEBUG'):
        config.get_settings()


def test_loop_stops_permanently_at_expiry_and_logs_once(monkeypatch, caplog):
    monkeypatch.setattr(demo_sensor, 'settings', SimpleNamespace(exhibit_demo_until=NOW,
                                                               demo_sensor_interval_seconds=30))
    clock = [NOW - timedelta(seconds=30)]
    class Clock:
        @staticmethod
        def now(tz): return clock[0]
    monkeypatch.setattr(demo_sensor, 'datetime', Clock)
    cycles = []
    @contextmanager
    def factory():
        yield object()
    monkeypatch.setattr(demo_sensor, 'SessionLocal', factory)
    monkeypatch.setattr(demo_sensor, 'write_demo_cycle', lambda db: cycles.append(clock[0]))
    monkeypatch.setattr(demo_sensor.time, 'sleep', lambda seconds: clock.__setitem__(0, NOW))
    with caplog.at_level('INFO', logger='app.services.demo_sensor'):
        demo_sensor._loop()
    assert cycles == [NOW - timedelta(seconds=30)]
    assert caplog.text.count('stopped permanently') == 1


def test_writer_excludes_expired_deadline_without_queries(db_session, monkeypatch):
    monkeypatch.setattr(demo_sensor, 'settings', SimpleNamespace(exhibit_demo_until=NOW))
    assert demo_sensor.write_demo_cycle(db_session, now=NOW) == 0
    assert demo_sensor.write_demo_cycle(db_session, now=NOW + timedelta(days=1)) == 0
    assert count(db_session, SensorReading) == 0


@pytest.mark.parametrize('configured_date', ['2026-10-13', '2040-02-29'])
def test_arbitrary_configured_ph_date_covers_two_whole_days(monkeypatch, configured_date):
    original_settings = config.settings
    try:
        with monkeypatch.context() as patch:
            patch.setenv('DEMO_EXHIBIT_DATE', configured_date)
            config.get_settings.cache_clear()
            patch.setattr(config, 'settings', config.get_settings())
            importlib.reload(demo_scenarios)
            epoch = demo_scenarios.VARIABILITY_EPOCH
            assert epoch.date().isoformat() == configured_date
            for day in (0, 1):
                for hour, minute in ((0, 30), (12, 0), (23, 30)):
                    now = epoch + timedelta(days=day, hours=hour, minutes=minute)
                    window = ci.TankWindow([], now)
                    for i in range(8 * 24 * 12 + 1):
                        observed = now - timedelta(days=8) + timedelta(minutes=5 * i)
                        window.add(SimpleNamespace(timestamp=observed, is_mock=True, device_id=None,
                                                  **{p: demo_scenarios.scenario_value('SHOW-PH', p, observed)
                                                     for p in ci.PARAMETERS}))
                    stability = ci.build_stability('ph', window.stability_buckets[True]['ph'],
                                                  window.stability_sources[True]['ph'], window.end)
                    assert stability['status'] == 'more_variable', (configured_date, now, stability)
    finally:
        assert config.settings is original_settings
        importlib.reload(demo_scenarios)
        config.get_settings.cache_clear()


def test_timestamp_sets_capped_and_every_value_kept_for_medians():
    window = ci.TankWindow([], NOW)
    observed = NOW - timedelta(minutes=30)
    for i in range(100):
        window.add(SimpleNamespace(timestamp=observed + timedelta(seconds=i), is_mock=True, device_id=None,
                                  temperature=float(i), ph=7, tds=120, turbidity=2))
    key = ci.bucket_start(observed)
    for buckets in (window.buckets, window.stability_buckets):
        values, times = buckets[True]['temperature'][key]
        assert len(times) == 3
        assert values == list(map(float, range(100)))
        assert ci.median(values) == 49.5


def test_cleanup_includes_unknown_show_codes_but_seed_refuses_them(db_session):
    db_session.add(Tank(name="Unknown showcase", tank_code="SHOW-UNKNOWN", location="Test"))
    db_session.commit()
    with pytest.raises(cli.ExhibitError, match="Unrecognized SHOW"):
        cli.seed(db_session, days=1)
    db_session.rollback()
    assert cli.cleanup(db_session) == 1
    assert count(db_session, Tank) == 0


@pytest.mark.parametrize('value', ['20261013', '2026-13-01', '2026-10-13T00:00:00Z'])
def test_exhibit_date_requires_calendar_date(monkeypatch, value):
    monkeypatch.setenv('DEMO_EXHIBIT_DATE', value)
    config.get_settings.cache_clear()
    try:
        with pytest.raises(ValueError, match='DEMO_EXHIBIT_DATE must be YYYY-MM-DD'):
            config.get_settings()
    finally:
        config.get_settings.cache_clear()


def test_local_seed_preserves_legacy_tank_name_and_hardware(db_session):
    from seed.seed_tanks import seed_tanks
    tank = Tank(name='Riverbank Community', tank_code='DISPLAY-01', location='Real location')
    db_session.add(tank)
    db_session.flush()
    db_session.add(RegisteredDevice(id='legacy-device', tank_id=tank.id, key_hash='c' * 64))
    db_session.commit()
    assert seed_tanks(db_session) == 6
    db_session.commit()
    assert tank.tank_code == 'DISPLAY-01' and tank.location == 'Real location'
    assert seed_tanks(db_session) == 0
    assert db_session.get(RegisteredDevice, 'legacy-device').is_active
