import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

from app.models import RegisteredDevice, SensorReading, User
from app.security import get_password_hash, hash_opaque_token
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
    assert body["device_id"] == device["device_id"]
    assert body["received_at"]
    assert body["timestamp"]
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
    forged = {**bridge_payload(), "device_id": device["device_id"], "received_at": datetime.now(timezone.utc).isoformat()}
    assert client.post("/device-ingestion/readings", headers={"X-Device-Key": device["device_key"]}, json=forged).status_code == 422


def test_observation_timestamp_is_normalized_to_utc(client, auth_headers):
    tank = create_tank(client, auth_headers, "Timestamp normalization tank")
    device = register(client, auth_headers, tank["id"], "timestamp-device")
    response = client.post(
        "/device-ingestion/readings",
        headers={"X-Device-Key": device["device_key"]},
        json={**bridge_payload(), "observed_at": "2026-08-21T12:00:00+08:00"},
    )
    assert response.status_code == 201
    assert response.json()["timestamp"].startswith("2026-08-21T04:00:00")
    assert response.json()["timestamp"].endswith(("+00:00", "Z"))


def test_manual_readings_have_no_device_provenance(client, auth_headers):
    tank = create_tank(client, auth_headers, "Manual provenance tank")
    response = client.post(
        f"/tanks/{tank['id']}/sensors",
        headers=auth_headers,
        json={"temperature": 25, "ph": 7, "turbidity": 2, "tds": 100},
    )
    assert response.status_code == 201
    assert response.json()["device_id"] is None
    assert response.json()["received_at"]


def test_administrator_can_manage_devices_and_rotation_invalidates_old_key(client, auth_headers):
    tank = create_tank(client, auth_headers, "Device lifecycle tank")
    provisioned = register(client, auth_headers, tank["id"], "lifecycle-device")

    listed = client.get("/devices", headers=auth_headers)
    assert listed.status_code == 200
    device = next(item for item in listed.json() if item["device_id"] == provisioned["device_id"])
    assert device["tank_name"] == tank["name"]
    assert device["status"] == "offline"
    assert "key_hash" not in device
    assert "device_key" not in device

    rotated = client.post(f"/devices/{provisioned['device_id']}/rotate-key", headers=auth_headers)
    assert rotated.status_code == 200
    replacement_key = rotated.json()["device_key"]
    assert replacement_key
    assert client.post(
        "/device-ingestion/readings",
        headers={"X-Device-Key": provisioned["device_key"]},
        json=bridge_payload(),
    ).status_code == 401
    ingested = client.post(
        "/device-ingestion/readings",
        headers={"X-Device-Key": replacement_key},
        json=bridge_payload(),
    )
    assert ingested.status_code == 201
    assert client.get("/devices/lifecycle-device", headers=auth_headers).json()["status"] == "online"

    deactivated = client.patch(
        "/devices/lifecycle-device",
        headers=auth_headers,
        json={"is_active": False},
    )
    assert deactivated.status_code == 200
    assert deactivated.json()["status"] == "disabled"
    assert client.post(
        "/device-ingestion/readings",
        headers={"X-Device-Key": replacement_key},
        json=bridge_payload(),
    ).status_code == 401

    reactivated = client.patch(
        "/devices/lifecycle-device",
        headers=auth_headers,
        json={"is_active": True},
    )
    assert reactivated.status_code == 200
    assert reactivated.json()["status"] == "online"


def test_device_management_is_administrator_only(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers, "Device permissions tank")
    provisioned = register(client, auth_headers, tank["id"], "permissions-device")
    staff = User(
        name="Device Staff",
        email="device-staff@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
    )
    db_session.add(staff)
    db_session.commit()
    login = client.post("/auth/login", json={"email": staff.email, "password": "password123"})
    staff_headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

    for response in (
        client.get("/devices", headers=staff_headers),
        client.get(f"/devices/{provisioned['device_id']}", headers=staff_headers),
        client.patch(f"/devices/{provisioned['device_id']}", headers=staff_headers, json={"is_active": False}),
        client.post(f"/devices/{provisioned['device_id']}/rotate-key", headers=staff_headers),
    ):
        assert response.status_code == 403


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
