from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select, text

from app.models import Alert, AlertSeverity, FishSpecies, MonitoringIncident, PushNotificationEvent, SensorReading, Tank
from app.services import push_insight
from app.services.current_insights import bucket_start, stamp, build_current_insights, build_parameter_trend
from app.services.decision_engine import ensure_default_thresholds, ingest_reading

NOW = datetime(2026, 10, 10, 12, 0, tzinfo=timezone.utc)


def setup_alert(db, parameter="temperature", value=31, severity=AlertSeverity.critical):
    ensure_default_thresholds(db)
    tank = Tank(name="Tank A", location="Test")
    db.add(tank)
    db.flush()
    reading = SensorReading(tank_id=tank.id, timestamp=NOW, received_at=NOW,
                            temperature=25, ph=7, tds=150, turbidity=2, is_mock=False)
    setattr(reading, parameter, value)
    db.add(reading)
    db.flush()
    alert = Alert(tank_id=tank.id, reading_id=reading.id, parameter=parameter,
                  severity=severity, message="Test")
    db.add(alert)
    db.flush()
    return tank, reading, alert


def add_history(db, tank, *, mixed=False, mock=False):
    start = bucket_start(NOW) - 12 * 1800
    for bucket in range(12):
        for minute in (5, 15, 25):
            observed = stamp(start + bucket * 1800 + minute * 60)
            value = 31 + (observed - NOW).total_seconds() / 3600 * 0.4
            db.add(SensorReading(tank_id=tank.id, timestamp=observed, received_at=NOW,
                                temperature=value, ph=7, turbidity=2, tds=150, is_mock=mock,
                                device_id=None))
    if mixed:
        # A real sample suppresses an otherwise qualifying mock fit.
        db.add(SensorReading(tank_id=tank.id, timestamp=NOW - timedelta(minutes=10),
                            received_at=NOW, temperature=30, ph=7, turbidity=2, tds=150, is_mock=False))
    db.flush()


def assign_species(db, tank, count=1, long=False):
    tank.fish_species = [FishSpecies(common_name=("N" * 200 if long else "Neon Tetra") + str(i) if count > 1 else "Neon Tetra",
                                    scientific_name="Test", ideal_temp_min=20, ideal_temp_max=28)
                         for i in range(count)]
    db.flush()


def test_alert_without_optional_context(db_session):
    tank, reading, alert = setup_alert(db_session)
    title, body = push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=False, now=NOW)
    assert title == "Tank A · Temperature critical: 31.0°C"
    assert body == "Above the 30.0°C critical limit. First check: confirm the measurement, then inspect the heater if installed."


@pytest.mark.parametrize("parameter,value,label", [("ph", 9, "pH critical: 9.0"), ("tds", 600.4, "TDS critical: 600 ppm"), ("turbidity", 16, "Turbidity critical: 16.0 NTU")])
def test_labels_units_and_checks(db_session, parameter, value, label):
    tank, reading, alert = setup_alert(db_session, parameter, value)
    title, body = push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=False, now=NOW)
    assert title.endswith(label)
    assert "First check: confirm" in body
    assert "fix" not in body and "dosing amounts" not in body


def test_lower_warning_bound(db_session):
    tank, reading, alert = setup_alert(db_session, value=19, severity=AlertSeverity.warning)
    _, body = push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=False, now=NOW)
    assert body.startswith("Below the 20.0°C warning limit.")


def test_reliable_trend_and_species(db_session):
    tank, reading, alert = setup_alert(db_session)
    add_history(db_session, tank)
    assign_species(db_session, tank, 4)
    title, body = push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=True, now=NOW)
    assert "now CRITICAL: 31.0°C" in title
    assert "and rising about 0.4°C/h" in body
    assert "Neon Tetra0, Neon Tetra1 +2 more" in body
    fleet = build_current_insights(db_session, [tank.id], now=NOW)
    expected = next(p['trend'] for p in fleet['tanks'][0]['parameters'] if p['parameter'] == 'temperature')
    trend = build_parameter_trend(db_session, tank.id, 'temperature', now=NOW)
    assert trend['status'] == expected['status']
    assert trend['rate_per_hour'] == pytest.approx(expected['rate_per_hour'])


@pytest.mark.parametrize("kind", ["mixed", "unreceived", "stale_species"])
def test_unreliable_context_is_omitted(db_session, kind):
    tank, reading, alert = setup_alert(db_session)
    assign_species(db_session, tank)
    if kind == 'mixed':
        add_history(db_session, tank, mixed=True, mock=True)
    elif kind == 'unreceived':
        add_history(db_session, tank)
        for row in db_session.scalars(select(SensorReading)):
            if row.id != reading.id:
                row.received_at = NOW + timedelta(minutes=1)
        db_session.flush()
    else:
        reading.timestamp = NOW - timedelta(hours=1)
    _, body = push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=False, now=NOW)
    assert "rising" not in body
    if kind == 'stale_species':
        assert "comfort range" not in body


def test_length_limits_drop_species_before_trend(db_session):
    tank, reading, alert = setup_alert(db_session)
    tank.name = "Tank " * 200
    assign_species(db_session, tank, 10, long=True)
    add_history(db_session, tank)
    title, body = push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=True, now=NOW)
    assert len(title) <= 160 and len(body) <= 300
    assert title.endswith("now CRITICAL: 31.0°C")
    assert "comfort range" not in body and "rising" in body
    assert "Above the 30.0°C critical limit" in body
    assert "First check: confirm the measurement" in body


def test_species_without_trend(db_session):
    tank, reading, alert = setup_alert(db_session)
    assign_species(db_session, tank)
    _, body = push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=False, now=NOW)
    assert "Outside the comfort range for Neon Tetra." in body
    assert "rising" not in body


def test_deferred_parameter_is_generic(db_session):
    tank, reading, alert = setup_alert(db_session, 'ammonia', 1)
    title, body = push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=False, now=NOW)
    assert title == push_insight.ALERT_FALLBACK_TITLE
    assert "Open AquaLogic" in body


@pytest.mark.parametrize("normal", [True, False])
def test_outage_recovery_receipt_time_and_range(db_session, normal):
    tank, reading, alert = setup_alert(db_session, value=25 if normal else 31)
    reading.timestamp = NOW - timedelta(days=1)
    incident = MonitoringIncident(tank_id=tank.id, started_at=NOW, detected_at=NOW + timedelta(minutes=15),
                                  last_reading_received_at=NOW, resolved_at=NOW + timedelta(minutes=20),
                                  recovery_reading_id=reading.id)
    title, body = push_insight.compose_outage_push(db_session, tank, incident, now=NOW + timedelta(minutes=15))
    assert title == "Tank A stopped reporting"
    assert "No data for 15 minutes" in body
    assert f"Last reading at {NOW.astimezone():%H:%M}" in body
    assert ("readings were in range" if normal else "Temperature was out of range") in body
    assert "First check: device power and Wi-Fi." in body
    reading.received_at = NOW + timedelta(minutes=20)
    title, body = push_insight.compose_recovery_push(db_session, tank, incident, now=NOW + timedelta(hours=1))
    assert title == "Tank A reporting again"
    assert "Back after 20 minutes" in body
    assert ("readings are in range" if normal else "Temperature is out of range") in body


def test_outage_without_readings(db_session):
    tank, reading, alert = setup_alert(db_session)
    incident = MonitoringIncident(tank_id=tank.id, started_at=NOW - timedelta(minutes=15), detected_at=NOW)
    _, body = push_insight.compose_outage_push(db_session, tank, incident, now=NOW)
    assert "No data for 15 minutes" in body and "No previous reading on record" in body
    _, body = push_insight.compose_recovery_push(db_session, tank, incident, now=NOW)
    assert "readings are unavailable" in body


@pytest.mark.parametrize("sql_failure", [False, True])
def test_composition_failure_preserves_source_and_push(db_session, monkeypatch, caplog, sql_failure):
    from app.services import decision_engine
    ensure_default_thresholds(db_session)
    tank = Tank(name="Fallback tank", location="Test")
    db_session.add(tank)
    db_session.commit()
    def fail(db, *args, **kwargs):
        if sql_failure:
            db.execute(text("SELECT * FROM missing_push_context_table"))
        raise RuntimeError("composition failed")
    monkeypatch.setattr(decision_engine, 'compose_alert_push', fail)
    ingest_reading(db_session, tank.id, dict(temperature=31, ph=7, turbidity=2, tds=150))
    alert = db_session.scalar(select(Alert))
    event = db_session.scalar(select(PushNotificationEvent))
    assert alert is not None and alert.severity == AlertSeverity.critical
    assert event.title == push_insight.ALERT_FALLBACK_TITLE
    assert event.body == push_insight.ALERT_FALLBACK_BODY.format(tank=tank.name, parameter="Temperature", severity="critical")
    assert "using fallback" in caplog.text


def test_escalation_flapping_emits_once(db_session):
    ensure_default_thresholds(db_session)
    tank = Tank(name="Flapping tank", location="Test")
    db_session.add(tank)
    db_session.commit()
    for temperature, expected_count in [(29, 1), (31, 2), (31.5, 2), (29, 2), (31, 2), (25, 2)]:
        ingest_reading(db_session, tank.id, dict(temperature=temperature, ph=7, turbidity=2, tds=150))
        events = list(db_session.scalars(select(PushNotificationEvent)))
        assert len(events) == expected_count
    escalated = events[1]
    assert escalated.event_type == "water_quality_alert_escalated"
    assert escalated.event_key == f"water_quality_alert:{events[0].source_id}:escalated"
    assert escalated.payload['alert_id'] == events[0].source_id
    assert "now CRITICAL" in escalated.title
    assert db_session.scalar(select(Alert)).is_resolved


def test_sample_notifications(db_session):
    tank, reading, alert = setup_alert(db_session, value=29, severity=AlertSeverity.warning)
    samples = [push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=False, now=NOW)]
    alert.severity = AlertSeverity.critical
    reading.temperature = 31
    samples.append(push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=True, now=NOW))
    incident = MonitoringIncident(tank_id=tank.id, started_at=NOW, detected_at=NOW + timedelta(minutes=15),
                                  last_reading_received_at=NOW, recovery_reading_id=reading.id)
    samples.append(push_insight.compose_outage_push(db_session, tank, incident, now=NOW + timedelta(minutes=15)))
    reading.temperature = 25
    reading.received_at = NOW + timedelta(minutes=20)
    samples.append(push_insight.compose_recovery_push(db_session, tank, incident, now=reading.received_at))
    for label, (title, body) in zip(['New alert', 'Escalated alert', 'Outage', 'Recovery'], samples):
        print(f"{label}: {title}\n{body}\n")
        assert len(title) <= 160 and len(body) <= 300


@pytest.mark.parametrize("second_length,keeps_second", [(217, True), (245, False)])
def test_copy_budget_drops_trend_then_second_check(db_session, monkeypatch, second_length, keeps_second):
    from app.services.operator_guidance import CATALOGUE
    tank, reading, alert = setup_alert(db_session)
    add_history(db_session, tank)
    second = "Inspect " + "equipment " * 30
    second = second[:second_length] + "."
    monkeypatch.setitem(CATALOGUE, ('temperature', 'above'), ["Confirm the measurement.", second])
    title, body = push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=False, now=NOW)
    assert len(body) <= 300
    assert "rising" not in body
    assert "First check: confirm the measurement" in body
    assert ("then inspect" in body) == keeps_second


def test_critical_creation_downgrade_and_resolution_emit_no_escalation(db_session):
    ensure_default_thresholds(db_session)
    tank = Tank(name="Critical first", location="Test")
    db_session.add(tank)
    db_session.commit()
    for temperature in (31, 29, 25):
        ingest_reading(db_session, tank.id, dict(temperature=temperature, ph=7, turbidity=2, tds=150))
    events = list(db_session.scalars(select(PushNotificationEvent)))
    assert [event.event_type for event in events] == ['water_quality_alert']



def test_extreme_configured_bound_keeps_required_copy(db_session):
    from app.models import ThresholdConfig
    tank, reading, alert = setup_alert(db_session, value=-1)
    threshold = db_session.scalar(select(ThresholdConfig).where(ThresholdConfig.parameter == 'temperature'))
    threshold.critical_min = 1e200
    db_session.flush()
    title, body = push_insight.compose_alert_push(db_session, alert, reading, tank, escalated=False, now=NOW)
    assert len(title) <= 160 and len(body) <= 300
    assert body.startswith("Below the 1.0e+200")
    assert "First check: confirm the measurement" in body


@pytest.mark.parametrize("minutes,text", [(1, "1 minute"), (45, "45 minutes"), (60, "1 h"), (135, "2 h 15 min")])
def test_duration_wording(minutes, text):
    assert push_insight._duration(minutes) == text
