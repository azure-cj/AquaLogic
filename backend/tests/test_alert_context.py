from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from app.models import Alert, AlertSeverity, SensorReading, Tank, ThresholdConfig, TankThresholdOverride, TankThresholdRevision
from app.services.alert_context import build_alert_context
from app.services.decision_engine import ensure_default_thresholds, ingest_reading, _severity
from app.services.operator_guidance import guidance_for


@pytest.mark.parametrize("parameter,direction,value", [
    ("temperature", "above", 31), ("temperature", "below", 17),
    ("ph", "above", 9), ("ph", "below", 5), ("turbidity", "above", 16),
    ("tds", "above", 600), ("tds", "below", 10),
])
def test_guidance_catalogue(db_session, parameter, direction, value):
    ensure_default_thresholds(db_session)
    threshold = db_session.query(ThresholdConfig).filter_by(parameter=parameter).one()
    result = guidance_for(parameter, value, threshold)
    assert result["direction"] == direction
    assert result["code"] == f"{parameter}.{direction}.v1"
    assert 3 <= len(result["checks"]) <= 4
    assert "does not confirm water recovery" in result["advisory"]
    assert not any(word in " ".join(result["checks"]).lower() for word in ["dose ", "caused", "diagnos"])


@pytest.mark.parametrize("value,enabled", [(None, True), (25, True), (31, False)])
def test_unavailable_direction(value, enabled):
    threshold = SimpleNamespace(enabled=enabled, warning_min=20, warning_max=28, critical_min=18, critical_max=30)
    assert guidance_for("temperature", value, threshold)["direction"] == "unavailable"
    assert _severity(30, threshold) is None
    assert _severity(18, threshold) is None


def fixture_alert(db):
    ensure_default_thresholds(db)
    tank = Tank(name="Context tank", location="Rack")
    db.add(tank)
    db.commit()
    now = datetime.now(timezone.utc)
    linked = ingest_reading(db, tank.id, dict(timestamp=now - timedelta(days=1), temperature=31, ph=7, turbidity=2, tds=100), received_at=now - timedelta(minutes=3))
    alert = db.query(Alert).filter_by(tank_id=tank.id, parameter="temperature").one()
    return tank, linked, alert, now


def test_context_receipt_selection_history_and_freshness(db_session, client, auth_headers):
    tank, linked, alert, now = fixture_alert(db_session)
    latest = SensorReading(tank_id=tank.id, timestamp=now - timedelta(days=2), received_at=now, temperature=24, ph=7, turbidity=2, tds=100)
    db_session.add(latest)
    db_session.commit()
    response = client.get(f"/alerts/{alert.id}/context", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["linked_reading"]["reading_id"] == linked.id
    assert data["linked_reading"]["reporting_freshness"] == "stale"
    assert data["latest_reading"]["reading_id"] == latest.id
    assert data["latest_reading"]["reporting_freshness"] == "fresh"
    assert data["latest_reading"]["observed_at"] < data["linked_reading"]["observed_at"]
    assert data["linked_threshold"]["source"] == "global"
    assert data["guidance"]["direction"] == "above"
    assert client.get(f"/alerts/{alert.id}/context").status_code == 401
    assert client.get(f"/alerts/{alert.id}/context", headers={"X-Device-Key": "invalid"}).status_code == 401
    assert client.get('/alerts/999999/context', headers=auth_headers).status_code == 404


def test_context_override_disabled_and_retired_history(db_session, client, auth_headers, test_user):
    tank, linked, alert, now = fixture_alert(db_session)
    override = TankThresholdOverride(tank_id=tank.id, parameter="temperature", unit="°C", warning_min=21, warning_max=27, critical_min=19, critical_max=29, enabled=False)
    revision = TankThresholdRevision(tank_id=tank.id, parameter="temperature", unit="°C", warning_min=21, warning_max=27, critical_min=19, critical_max=29, enabled=True, is_override=True, effective_from=now - timedelta(minutes=5))
    db_session.add_all([override, revision])
    tank.retired_at = now
    db_session.commit()
    test_user.role = "staff"
    db_session.commit()
    data = client.get(f"/alerts/{alert.id}/context", headers=auth_headers).json()
    assert data["tank"]["lifecycle"] == "retired"
    assert data["linked_threshold"]["source"] == "tank"
    assert data["linked_threshold"]["enabled"] is True
    assert data["current_threshold"]["enabled"] is False
    assert client.put(f"/alerts/{alert.id}/resolve", headers=auth_headers).status_code == 409


@pytest.mark.parametrize("resolved,source", [(False, None), (True, "operator"), (True, "system"), (True, None)])
def test_missing_readings_preserve_lifecycle(db_session, resolved, source):
    tank = Tank(name="Legacy tank", location="Rack")
    db_session.add(tank)
    db_session.flush()
    alert = Alert(tank_id=tank.id, parameter="ph", severity=AlertSeverity.warning, message="Legacy", is_resolved=resolved, resolution_source=source)
    db_session.add(alert)
    db_session.commit()
    context = build_alert_context(db_session, alert)
    assert context["linked_reading"] is None
    assert context["latest_reading"] is None
    assert context["guidance"]["direction"] == "unavailable"
    assert context["alert"].is_resolved == resolved
    assert context["alert"].resolution_source == source


def test_context_tracks_subsequent_linked_reading_and_acknowledgement(db_session, client, auth_headers):
    tank, linked, alert, now = fixture_alert(db_session)
    newer = ingest_reading(db_session, tank.id, dict(timestamp=now, temperature=29, ph=7, turbidity=2, tds=100), received_at=now)
    data = client.get(f"/alerts/{alert.id}/context", headers=auth_headers).json()
    assert data["linked_reading"]["reading_id"] == newer.id
    assert data["alert"]["severity"] == "warning"
    response = client.put(f"/alerts/{alert.id}/resolve", headers=auth_headers)
    assert response.json()["resolution_source"] == "operator"
    assert client.get(f"/alerts/{alert.id}/context", headers=auth_headers).json()["alert"]["is_resolved"]
