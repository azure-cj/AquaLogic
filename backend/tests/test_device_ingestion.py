import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

from app.models import RegisteredDevice, SensorReading
from app.security import hash_opaque_token
from app.services.decision_engine import ensure_default_thresholds, parameter_statuses, status_for_reading


FIXTURE = Path(__file__).parent / "fixtures" / "esp32_data.json"


def create_tank(client, headers, name="Bridge tank"):
    response = client.post("/tanks", headers=headers, json={"name": name, "location": "Test bench"})
    assert response.status_code == 201
    return response.json()


def register(client, headers, tank_id, device_id="esp32-test-01"):
    response = client.post("/devices", headers=headers, json={"device_id": device_id, "tank_id": tank_id})
    assert response.status_code == 201
    return response.json()


def bridge_payload():
    source = json.loads(FIXTURE.read_text())
    return {"temperature": source["temp_c"], "ph": source["ph_value"], "turbidity": source["turbidity_ntu"], "tds": source["tds_ppm"]}


def test_device_ingestion_uses_fixed_device_tank_and_defers_uninstalled_metrics(client, auth_headers, db_session):
    ensure_default_thresholds(db_session)
    mapped = create_tank(client, auth_headers)
    other = create_tank(client, auth_headers, "Other tank")
    device = register(client, auth_headers, mapped["id"])

    response = client.post("/device-ingestion/readings", headers={"X-Device-Key": device["device_key"]}, json=bridge_payload())
    assert response.status_code == 201
    body = response.json()
    assert body["tank_id"] == mapped["id"]
    assert body["dissolved_oxygen"] is None
    assert body["ammonia"] is None
    assert not db_session.query(SensorReading).filter_by(tank_id=other["id"]).count()
    assert parameter_statuses(db_session, db_session.get(SensorReading, body["id"]))["dissolved_oxygen"] == "unavailable"
    assert parameter_statuses(db_session, db_session.get(SensorReading, body["id"]))["ammonia"] == "unavailable"


def test_device_authentication_and_values_are_validated(client, auth_headers):
    tank = create_tank(client, auth_headers)
    device = register(client, auth_headers, tank["id"])
    assert client.post("/device-ingestion/readings", json=bridge_payload()).status_code == 422
    assert client.post("/device-ingestion/readings", headers={"X-Device-Key": "wrong"}, json=bridge_payload()).status_code == 401
    invalid = {**bridge_payload(), "ph": 15}
    assert client.post("/device-ingestion/readings", headers={"X-Device-Key": device["device_key"]}, json=invalid).status_code == 422


def test_device_key_cannot_be_reused_for_another_mapping(client, auth_headers, db_session):
    first = create_tank(client, auth_headers)
    second = create_tank(client, auth_headers, "Second mapping")
    first_device = register(client, auth_headers, first["id"], "bridge-one")
    db_session.add(RegisteredDevice(id="bridge-two", tank_id=second["id"], key_hash=hash_opaque_token("different-key")))
    db_session.commit()
    response = client.post("/device-ingestion/readings", headers={"X-Device-Key": first_device["device_key"]}, json=bridge_payload())
    assert response.json()["tank_id"] == first["id"]


def test_partial_reading_becomes_offline_when_stale(db_session):
    ensure_default_thresholds(db_session)
    reading = SensorReading(tank_id=1, timestamp=datetime.now(timezone.utc) - timedelta(minutes=2), temperature=25, ph=7, turbidity=2, tds=150, dissolved_oxygen=None, ammonia=None)
    assert status_for_reading(db_session, reading) == "offline"
    assert set(parameter_statuses(db_session, reading).values()) == {"offline"}
