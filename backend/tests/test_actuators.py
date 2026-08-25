from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base, configure_sqlite_foreign_keys
from app.models import ActuatorCommand, RegisteredDevice, SecurityAuditEvent, Tank, User
from app.security import get_password_hash
from app.security import utc_now
from app.services.actuator_commands import reconcile_actuator_commands, reconcile_all_actuator_commands


LIGHT_STATE = {
    "on": True,
    "remaining_ms": 5_000,
    "total_on_ms": 12_000,
    "schedule_enabled": True,
    "on_time": "08:00",
    "off_time": "18:00",
}

PUMP_STATE = {
    "active": False,
    "dose_count": 2,
    "last_dispensed": "12:34:56",
    "volume_ml": 1.0,
}


def create_tank(client, headers, name="Actuator tank"):
    response = client.post("/tanks", headers=headers, json={"name": name, "location": "Test bench"})
    assert response.status_code == 201
    return response.json()


def register(client, headers, tank_id, device_id="esp32-actuator-01"):
    response = client.post("/devices", headers=headers, json={"device_id": device_id, "tank_id": tank_id})
    assert response.status_code == 201
    return response.json()


def staff_headers(client, db_session):
    staff = User(
        name="Test Staff",
        email="staff-actuators@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
    )
    db_session.add(staff)
    db_session.commit()
    response = client.post("/auth/login", json={"email": staff.email, "password": "password123"})
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def queue(client, headers, tank_id, payload, device_id=None):
    body = {**payload}
    if device_id:
        body["device_id"] = device_id
    return client.post(f"/tanks/{tank_id}/actuators/commands", headers=headers, json=body)


def mark_bridge_online(client, device):
    response = client.get("/device-ingestion/actuators/pending", headers={"X-Device-Key": device["device_key"]})
    assert response.status_code == 200


def test_admin_can_queue_and_bridge_can_claim_and_report(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers)
    device = register(client, auth_headers, tank["id"])
    response = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "uv", "action": "timer", "payload": {"duration_ms": 10_000}},
    )
    assert response.status_code == 201
    command = response.json()
    assert command["status"] == "queued"
    assert command["actor_name"] == "Test Staff"
    assert command["device_id"] == device["device_id"]

    pending = client.get("/device-ingestion/actuators/pending", headers={"X-Device-Key": device["device_key"]})
    assert pending.status_code == 200
    assert pending.json()[0]["command_id"] == command["command_id"]
    executing = client.post(
        f"/device-ingestion/actuators/{command['command_id']}/executing",
        headers={"X-Device-Key": device["device_key"]},
    )
    assert executing.status_code == 200
    succeeded = client.post(
        f"/device-ingestion/actuators/{command['command_id']}/succeeded",
        headers={"X-Device-Key": device["device_key"]},
        json={"result": {"endpoint": "/uv/timer"}},
    )
    assert succeeded.status_code == 200
    assert succeeded.json()["status"] == "succeeded"

    state = client.post(
        "/device-ingestion/actuator-state",
        headers={"X-Device-Key": device["device_key"]},
        json={"actuator": "uv", "state": LIGHT_STATE, "command_id": command["command_id"]},
    )
    assert state.status_code == 200
    status_response = client.get(f"/tanks/{tank['id']}/actuators/status", headers=auth_headers)
    assert status_response.status_code == 200
    body = status_response.json()
    assert body["device_id"] == device["device_id"]
    assert body["device_online"] is True
    assert next(item for item in body["actuators"] if item["actuator"] == "uv")["state"] == LIGHT_STATE

    history = client.get(
        f"/tanks/{tank['id']}/actuators/history?page=1&page_size=10",
        headers=auth_headers,
    )
    assert history.status_code == 200
    assert history.json()["items"][0]["actor_name"] == "Test Staff"
    assert history.json()["total"] == 1
    assert history.json()["total_pages"] == 1
    assert history.json()["summary"]["total"] == 1
    assert history.json()["summary"]["queued"] == 0
    assert db_session.query(ActuatorCommand).count() == 1


def test_actuator_history_is_paginated(client, auth_headers):
    tank = create_tank(client, auth_headers, "Paginated actuator tank")
    register(client, auth_headers, tank["id"], "esp32-actuator-pagination")
    for action in ("on", "off", "on"):
        response = queue(client, auth_headers, tank["id"], {"actuator": "uv", "action": action, "payload": {}})
        assert response.status_code == 201

    first_page = client.get(
        f"/tanks/{tank['id']}/actuators/history?page=1&page_size=2",
        headers=auth_headers,
    )
    second_page = client.get(
        f"/tanks/{tank['id']}/actuators/history?page=2&page_size=2",
        headers=auth_headers,
    )
    filtered = client.get(
        f"/tanks/{tank['id']}/actuators/history?page=1&page_size=10&actuator=uv&status=queued",
        headers=auth_headers,
    )

    assert first_page.status_code == 200
    assert second_page.status_code == 200
    assert filtered.status_code == 200
    assert len(first_page.json()["items"]) == 2
    assert len(second_page.json()["items"]) == 1
    assert first_page.json()["total"] == 3
    assert first_page.json()["has_previous"] is False
    assert first_page.json()["has_next"] is True
    assert second_page.json()["has_previous"] is True
    assert second_page.json()["has_next"] is False
    assert filtered.json()["total"] == 3
    assert len(filtered.json()["items"]) == 3


def test_normal_command_expiry_defaults_and_bounds_are_explicit(client, auth_headers):
    tank = create_tank(client, auth_headers, "Command expiry tank")
    register(client, auth_headers, tank["id"], "esp32-expiry-bounds")

    default_command = queue(client, auth_headers, tank["id"], {"actuator": "uv", "action": "on", "payload": {}})
    maximum_command = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "led", "action": "off", "payload": {}, "expires_in_seconds": 300},
    )
    too_long = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "feeder", "action": "feed_now", "payload": {}, "expires_in_seconds": 301},
    )

    assert default_command.status_code == 201
    default_seconds = (
        datetime.fromisoformat(default_command.json()["expires_at"])
        - datetime.fromisoformat(default_command.json()["requested_at"])
    ).total_seconds()
    assert 119 <= default_seconds <= 121
    assert maximum_command.status_code == 201
    maximum_seconds = (
        datetime.fromisoformat(maximum_command.json()["expires_at"])
        - datetime.fromisoformat(maximum_command.json()["requested_at"])
    ).total_seconds()
    assert 299 <= maximum_seconds <= 301
    assert too_long.status_code == 422


def test_multiple_active_devices_require_explicit_selection(client, auth_headers):
    tank = create_tank(client, auth_headers, "Multiple bridge tank")
    first = register(client, auth_headers, tank["id"], "esp32-multiple-a")
    second = register(client, auth_headers, tank["id"], "esp32-multiple-b")

    ambiguous = queue(client, auth_headers, tank["id"], {"actuator": "uv", "action": "on", "payload": {}})
    first_command = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "uv", "action": "on", "payload": {}},
        device_id=first["device_id"],
    )
    second_command = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "led", "action": "off", "payload": {}},
        device_id=second["device_id"],
    )

    assert ambiguous.status_code == 409
    assert "Multiple active bridge devices" in ambiguous.json()["detail"]
    assert first_command.status_code == 201
    assert first_command.json()["device_id"] == first["device_id"]
    assert second_command.status_code == 201
    assert second_command.json()["device_id"] == second["device_id"]


def test_actuator_audit_is_complete_and_history_redacts_bridge_secrets(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers, "Audit actuator tank")
    device = register(client, auth_headers, tank["id"], "esp32-audit-safe")
    key_headers = {"X-Device-Key": device["device_key"]}

    succeeded = queue(client, auth_headers, tank["id"], {"actuator": "uv", "action": "on", "payload": {}}).json()
    path = f"/device-ingestion/actuators/{succeeded['command_id']}"
    assert client.post(f"{path}/executing", headers=key_headers).status_code == 200
    success = client.post(
        f"{path}/succeeded",
        headers=key_headers,
        json={"result": {"path": "/uv/on", "device_key": "do-not-store-this-key"}},
    )
    assert success.status_code == 200
    assert success.json()["result"]["device_key"] == "[redacted]"
    assert client.post(
        "/device-ingestion/actuator-state",
        headers=key_headers,
        json={"actuator": "uv", "state": LIGHT_STATE, "command_id": succeeded["command_id"]},
    ).status_code == 200

    failed = queue(client, auth_headers, tank["id"], {"actuator": "led", "action": "off", "payload": {}}).json()
    failed_path = f"/device-ingestion/actuators/{failed['command_id']}"
    assert client.post(f"{failed_path}/executing", headers=key_headers).status_code == 200
    failure = client.post(
        f"{failed_path}/failed",
        headers=key_headers,
        json={"error": "device_key=do-not-store-this-key", "result": {"secret": "hidden"}},
    )
    assert failure.status_code == 200
    assert "do-not-store-this-key" not in failure.text
    assert failure.json()["result"]["secret"] == "[redacted]"

    expired = queue(client, auth_headers, tank["id"], {"actuator": "feeder", "action": "feed_now", "payload": {}}).json()
    expired_row = db_session.get(ActuatorCommand, expired["command_id"])
    expired_row.expires_at = utc_now() - timedelta(seconds=1)
    db_session.commit()
    assert client.get("/device-ingestion/actuators/pending", headers=key_headers).status_code == 200

    history = client.get(f"/tanks/{tank['id']}/actuators/history?page=1&page_size=10", headers=auth_headers)
    assert history.status_code == 200
    assert "do-not-store-this-key" not in history.text
    assert "hidden" not in history.text

    event_types = {event.event_type for event in db_session.query(SecurityAuditEvent).all()}
    assert {
        "actuator.command.queued",
        "actuator.command.executing",
        "actuator.command.succeeded",
        "actuator.command.failed",
        "actuator.command.expired",
        "device.actuator_state",
    }.issubset(event_types)
    assert all("do-not-store-this-key" not in (event.details or "") for event in db_session.query(SecurityAuditEvent).all())


def test_staff_cannot_read_or_queue_actuator_controls(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers, "Staff blocked actuator tank")
    register(client, auth_headers, tank["id"], "esp32-actuator-02")
    headers = staff_headers(client, db_session)
    command = queue(client, headers, tank["id"], {"actuator": "uv", "action": "on", "payload": {}})
    assert command.status_code == 403
    assert client.get(f"/tanks/{tank['id']}/actuators/status", headers=headers).status_code == 403
    assert client.get(f"/tanks/{tank['id']}/actuators/history", headers=headers).status_code == 403
    assert client.get(f"/tanks/{tank['id']}/actuators/status").status_code == 401


def test_command_is_fixed_to_device_tank_and_payload_limits_are_enforced(client, auth_headers):
    tank = create_tank(client, auth_headers, "Mapped actuator tank")
    other = create_tank(client, auth_headers, "Other actuator tank")
    device = register(client, auth_headers, tank["id"], "esp32-actuator-03")

    wrong_tank = queue(
        client,
        auth_headers,
        other["id"],
        {"actuator": "uv", "action": "on", "payload": {}},
        device_id=device["device_id"],
    )
    assert wrong_tank.status_code == 404
    assert queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "uv", "action": "timer", "payload": {"duration_ms": 86_400_001}},
    ).status_code == 422
    assert queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "feeder", "action": "config", "payload": {"open_angle": 181, "duration_ms": 500}},
    ).status_code == 422
    assert queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "feeder", "action": "schedule", "payload": {"slots": [{"enabled": True, "time": "08:00"}]}},
    ).status_code == 422
    assert queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "uv", "action": "schedule", "payload": {"enabled": True, "on_time": "8:00", "off_time": "18:00"}},
    ).status_code == 422


def test_pump_commands_require_an_online_bridge_and_empty_dispense_payload(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers, "Pump test tank")
    device = register(client, auth_headers, tank["id"], "esp32-pump-test-01")

    offline = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "pump_a", "action": "dispense", "payload": {}},
    )
    assert offline.status_code == 409
    assert "not queued" in offline.json()["detail"]
    assert db_session.query(ActuatorCommand).count() == 0

    mark_bridge_online(client, device)
    command = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "pump_a", "action": "dispense", "payload": {}},
    )
    assert command.status_code == 201
    body = command.json()
    assert body["actuator"] == "pump_a"
    assert body["payload"] == {}
    expiry_seconds = (datetime.fromisoformat(body["expires_at"]) - datetime.fromisoformat(body["requested_at"])).total_seconds()
    assert 19 <= expiry_seconds <= 21

    assert queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "pump_b", "action": "dispense", "payload": {"volume_ml": 1}},
    ).status_code == 422
    assert queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "pump_b", "action": "retract", "payload": {"duration_ms": 500}},
    ).status_code == 422
    assert queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "pump_b", "action": "stop", "payload": {}, "expires_in_seconds": 31},
    ).status_code == 422


def test_pump_commands_use_fixed_mapping_and_report_state(client, auth_headers):
    tank = create_tank(client, auth_headers, "Pump state tank")
    other = create_tank(client, auth_headers, "Other pump tank")
    device = register(client, auth_headers, tank["id"], "esp32-pump-state-01")
    mark_bridge_online(client, device)

    wrong_tank = queue(
        client,
        auth_headers,
        other["id"],
        {"actuator": "pump_a", "action": "stop", "payload": {}},
        device_id=device["device_id"],
    )
    assert wrong_tank.status_code == 404

    command = queue(client, auth_headers, tank["id"], {"actuator": "pump_b", "action": "stop", "payload": {}}).json()
    key_headers = {"X-Device-Key": device["device_key"]}
    assert client.post(f"/device-ingestion/actuators/{command['command_id']}/executing", headers=key_headers).status_code == 200
    assert client.post(
        f"/device-ingestion/actuators/{command['command_id']}/succeeded",
        headers=key_headers,
        json={"result": {"path": "/syringeB/stop"}},
    ).status_code == 200
    state = client.post(
        "/device-ingestion/actuator-state",
        headers=key_headers,
        json={"actuator": "pump_b", "state": PUMP_STATE, "command_id": command["command_id"]},
    )
    assert state.status_code == 200
    status_response = client.get(f"/tanks/{tank['id']}/actuators/status", headers=auth_headers)
    assert status_response.status_code == 200
    assert next(item for item in status_response.json()["actuators"] if item["actuator"] == "pump_b")["state"] == PUMP_STATE
    history = client.get(
        f"/tanks/{tank['id']}/actuators/history?page=1&page_size=10&actuator=pump_b&status=succeeded",
        headers=auth_headers,
    )
    assert history.status_code == 200
    assert history.json()["total"] == 1


def test_staff_cannot_queue_pump_commands(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers, "Staff pump tank")
    register(client, auth_headers, tank["id"], "esp32-pump-staff-01")
    headers = staff_headers(client, db_session)
    command = queue(client, headers, tank["id"], {"actuator": "pump_a", "action": "stop", "payload": {}})
    assert command.status_code == 403


def test_expired_commands_are_never_returned_or_executed(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers, "Expiry actuator tank")
    device = register(client, auth_headers, tank["id"], "esp32-actuator-04")
    response = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "led", "action": "on", "payload": {}, "expires_in_seconds": 1},
    )
    command_id = response.json()["command_id"]
    command = db_session.get(ActuatorCommand, command_id)
    command.expires_at = utc_now() - timedelta(seconds=1)
    db_session.commit()

    pending = client.get("/device-ingestion/actuators/pending", headers={"X-Device-Key": device["device_key"]})
    assert pending.status_code == 200
    assert pending.json() == []
    refreshed = db_session.get(ActuatorCommand, command_id)
    assert refreshed.status == "expired"
    executing = client.post(
        f"/device-ingestion/actuators/{command_id}/executing",
        headers={"X-Device-Key": device["device_key"]},
    )
    assert executing.status_code == 409


def test_duplicate_delivery_and_reporting_are_idempotent(client, auth_headers):
    tank = create_tank(client, auth_headers, "Idempotent actuator tank")
    device = register(client, auth_headers, tank["id"], "esp32-actuator-05")
    command = queue(client, auth_headers, tank["id"], {"actuator": "feeder", "action": "feed_now", "payload": {}}).json()
    key_headers = {"X-Device-Key": device["device_key"]}
    path = f"/device-ingestion/actuators/{command['command_id']}"
    assert client.post(f"{path}/executing", headers=key_headers).status_code == 200
    assert client.post(f"{path}/executing", headers=key_headers).status_code == 409
    result = {"endpoint": "/feeder/feed", "fed": True}
    assert client.post(f"{path}/succeeded", headers=key_headers, json={"result": result}).status_code == 200
    assert client.post(f"{path}/succeeded", headers=key_headers, json={"result": result}).status_code == 200
    assert client.get("/device-ingestion/actuators/pending", headers=key_headers).json() == []


def test_failed_command_reporting_is_preserved(client, auth_headers):
    tank = create_tank(client, auth_headers, "Failed actuator tank")
    device = register(client, auth_headers, tank["id"], "esp32-actuator-06")
    command = queue(client, auth_headers, tank["id"], {"actuator": "led", "action": "off", "payload": {}}).json()
    key_headers = {"X-Device-Key": device["device_key"]}
    path = f"/device-ingestion/actuators/{command['command_id']}"
    client.post(f"{path}/executing", headers=key_headers)
    failed = client.post(
        f"{path}/failed",
        headers=key_headers,
        json={"error": "ESP32 returned invalid JSON"},
    )
    assert failed.status_code == 200
    assert failed.json()["status"] == "failed"
    assert failed.json()["error"] == "ESP32 returned invalid JSON"


def test_bridge_unknown_report_blocks_same_pump_but_keeps_stop_available(client, auth_headers):
    tank = create_tank(client, auth_headers, "Bridge uncertainty report tank")
    device = register(client, auth_headers, tank["id"], "esp32-unknown-report-01")
    mark_bridge_online(client, device)
    command = queue(client, auth_headers, tank["id"], {"actuator": "pump_a", "action": "dispense", "payload": {}}).json()
    key_headers = {"X-Device-Key": device["device_key"]}
    path = f"/device-ingestion/actuators/{command['command_id']}"
    assert client.post(f"{path}/executing", headers=key_headers).status_code == 200

    unknown = client.post(
        f"{path}/outcome-unknown",
        headers=key_headers,
        json={"error": "Physical request timed out after dispatch"},
    )
    assert unknown.status_code == 200
    assert unknown.json()["status"] == "outcome_unknown"

    blocked = queue(client, auth_headers, tank["id"], {"actuator": "pump_a", "action": "dispense", "payload": {}})
    assert blocked.status_code == 409
    assert queue(client, auth_headers, tank["id"], {"actuator": "pump_b", "action": "dispense", "payload": {}}).status_code == 201
    assert queue(client, auth_headers, tank["id"], {"actuator": "pump_a", "action": "stop", "payload": {}}).status_code == 201


def test_executing_command_becomes_unknown_after_confirmation_deadline_once(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers, "Unknown outcome tank")
    device = register(client, auth_headers, tank["id"], "esp32-unknown-01")
    command = queue(client, auth_headers, tank["id"], {"actuator": "uv", "action": "on", "payload": {}}).json()
    key_headers = {"X-Device-Key": device["device_key"]}
    path = f"/device-ingestion/actuators/{command['command_id']}"
    assert client.post(f"{path}/executing", headers=key_headers).status_code == 200

    row = db_session.get(ActuatorCommand, command["command_id"])
    row.confirmation_deadline_at = utc_now() + timedelta(seconds=60)
    db_session.commit()
    below_deadline = client.get(f"/tanks/{tank['id']}/actuators/history?page=1&page_size=10", headers=auth_headers)
    assert below_deadline.status_code == 200
    assert below_deadline.json()["items"][0]["status"] == "executing"

    row = db_session.get(ActuatorCommand, command["command_id"])
    row.confirmation_deadline_at = utc_now() - timedelta(seconds=1)
    db_session.commit()

    first_history = client.get(f"/tanks/{tank['id']}/actuators/history?page=1&page_size=10", headers=auth_headers)
    assert first_history.status_code == 200
    assert first_history.json()["items"][0]["status"] == "outcome_unknown"
    assert first_history.json()["summary"]["outcome_unknown"] == 1
    assert first_history.json()["items"][0]["error"] == "Confirmation deadline elapsed; physical outcome is unknown"
    assert db_session.get(ActuatorCommand, command["command_id"]).status == "outcome_unknown"

    second_history = client.get(f"/tanks/{tank['id']}/actuators/history?page=1&page_size=10", headers=auth_headers)
    assert second_history.status_code == 200
    assert second_history.json()["summary"]["outcome_unknown"] == 1
    assert db_session.query(SecurityAuditEvent).filter_by(
        event_type="actuator.command.outcome_unknown",
        target_id=command["command_id"],
    ).count() == 1

    assert client.get("/device-ingestion/actuators/pending", headers=key_headers).json() == []
    assert client.post(f"{path}/executing", headers=key_headers).status_code == 409
    late_success = client.post(f"{path}/succeeded", headers=key_headers, json={"result": {"confirmed": True}})
    assert late_success.status_code == 409
    late_failure = client.post(f"{path}/failed", headers=key_headers, json={"error": "late failure"})
    assert late_failure.status_code == 409
    repeated_late_success = client.post(f"{path}/succeeded", headers=key_headers, json={"result": {"confirmed": True}})
    assert repeated_late_success.status_code == 409
    assert db_session.query(SecurityAuditEvent).filter_by(
        event_type="actuator.command.late_report_rejected",
        target_id=command["command_id"],
    ).count() == 2


def test_concurrent_reconciliation_transitions_and_audits_once(tmp_path):
    engine = create_engine(
        f"sqlite:///{tmp_path / 'actuator-reconciliation.db'}",
        connect_args={"check_same_thread": False, "timeout": 10},
        future=True,
    )
    configure_sqlite_foreign_keys(engine)
    Base.metadata.create_all(bind=engine)
    sessions = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)
    now = utc_now()
    setup = sessions()
    try:
        tank = Tank(name="Concurrent reconciliation tank", location="Test bench")
        setup.add(tank)
        setup.flush()
        device_id = "esp32-reconcile-concurrent"
        device = RegisteredDevice(id=device_id, tank_id=tank.id, key_hash="reconcile-key-hash")
        setup.add(device)
        setup.flush()
        setup.add(
            ActuatorCommand(
                command_id="reconcile-concurrent-command",
                device_id=device.id,
                tank_id=tank.id,
                actuator="uv",
                action="on",
                payload_json="{}",
                status="executing",
                requested_at=now - timedelta(minutes=5),
                expires_at=now + timedelta(minutes=5),
                executing_at=now - timedelta(seconds=181),
                confirmation_deadline_at=now - timedelta(seconds=1),
            )
        )
        setup.commit()
    finally:
        setup.close()

    results: list[int] = []
    errors: list[BaseException] = []

    def reconcile_once() -> None:
        db = sessions()
        try:
            results.append(reconcile_actuator_commands(db, device_id, now=now))
            db.commit()
        except BaseException as error:  # pragma: no cover - assertion reports unexpected worker failures
            errors.append(error)
            db.rollback()
        finally:
            db.close()

    with ThreadPoolExecutor(max_workers=2) as workers:
        futures = [workers.submit(reconcile_once) for _ in range(2)]
        for future in futures:
            future.result()

    check = sessions()
    try:
        command = check.get(ActuatorCommand, "reconcile-concurrent-command")
        assert not errors
        assert sorted(results) == [0, 1]
        assert command.status == "outcome_unknown"
        assert check.query(SecurityAuditEvent).filter_by(
            event_type="actuator.command.outcome_unknown",
            target_id=command.command_id,
        ).count() == 1
    finally:
        check.close()
        Base.metadata.drop_all(bind=engine)
        engine.dispose()


def test_autonomous_reconciliation_does_not_require_a_status_request(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers, "Autonomous reconciliation tank")
    device = register(client, auth_headers, tank["id"], "esp32-autonomous-reconcile")
    command = queue(client, auth_headers, tank["id"], {"actuator": "uv", "action": "on", "payload": {}}).json()
    key_headers = {"X-Device-Key": device["device_key"]}
    path = f"/device-ingestion/actuators/{command['command_id']}"
    assert client.post(f"{path}/executing", headers=key_headers).status_code == 200
    row = db_session.get(ActuatorCommand, command["command_id"])
    deadline = utc_now() - timedelta(seconds=1)
    row.confirmation_deadline_at = deadline
    db_session.commit()

    assert reconcile_all_actuator_commands(db_session, now=utc_now()) == 1
    db_session.commit()
    assert db_session.get(ActuatorCommand, command["command_id"]).status == "outcome_unknown"
    assert reconcile_all_actuator_commands(db_session, now=utc_now()) == 0
    assert db_session.query(SecurityAuditEvent).filter_by(
        event_type="actuator.command.outcome_unknown",
        target_id=command["command_id"],
    ).count() == 1


def test_same_device_pump_dispense_interlock_clearance_and_stop(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers, "Pump interlock tank")
    device = register(client, auth_headers, tank["id"], "esp32-interlock-01")
    key_headers = {"X-Device-Key": device["device_key"]}
    mark_bridge_online(client, device)

    first = queue(client, auth_headers, tank["id"], {"actuator": "pump_a", "action": "dispense", "payload": {}}).json()
    path = f"/device-ingestion/actuators/{first['command_id']}"
    assert client.post(f"{path}/executing", headers=key_headers).status_code == 200

    blocked = queue(client, auth_headers, tank["id"], {"actuator": "pump_a", "action": "dispense", "payload": {}})
    assert blocked.status_code == 409
    assert "Physically verify the pump" in blocked.json()["detail"]
    pump_b = queue(client, auth_headers, tank["id"], {"actuator": "pump_b", "action": "dispense", "payload": {}})
    assert pump_b.status_code == 201
    stop = queue(client, auth_headers, tank["id"], {"actuator": "pump_a", "action": "stop", "payload": {}})
    assert stop.status_code == 201

    row = db_session.get(ActuatorCommand, first["command_id"])
    row.confirmation_deadline_at = utc_now() - timedelta(seconds=1)
    db_session.commit()
    status_response = client.get(f"/tanks/{tank['id']}/actuators/status", headers=auth_headers)
    assert status_response.status_code == 200
    assert status_response.json()["pump_dispense_locks"] == [{
        "actuator": "pump_a",
        "command_id": first["command_id"],
        "status": "outcome_unknown",
        "verification_required": True,
    }]
    still_blocked = queue(client, auth_headers, tank["id"], {"actuator": "pump_a", "action": "dispense", "payload": {}})
    assert still_blocked.status_code == 409

    cleared = client.post(
        f"/tanks/{tank['id']}/actuators/commands/{first['command_id']}/clear-uncertainty",
        headers=auth_headers,
        json={"note": "Verified empty syringe and cleared the line"},
    )
    assert cleared.status_code == 200
    assert cleared.json()["status"] == "outcome_unknown"
    assert cleared.json()["physical_verification_actor_name"] == "Test Staff"
    assert cleared.json()["physical_verification_note"] == "Verified empty syringe and cleared the line"
    assert db_session.get(ActuatorCommand, first["command_id"]).status == "outcome_unknown"

    repeated_clearance = client.post(
        f"/tanks/{tank['id']}/actuators/commands/{first['command_id']}/clear-uncertainty",
        headers=auth_headers,
        json={"note": "A different note must not rewrite the original verification"},
    )
    assert repeated_clearance.status_code == 200
    assert repeated_clearance.json()["physical_verification_note"] == "Verified empty syringe and cleared the line"

    allowed_after_clearance = queue(client, auth_headers, tank["id"], {"actuator": "pump_a", "action": "dispense", "payload": {}})
    assert allowed_after_clearance.status_code == 201
    verification_event = db_session.query(SecurityAuditEvent).filter_by(
        event_type="actuator.command.physical_verification_cleared",
        target_id=first["command_id"],
    ).one()
    assert "Verified empty syringe and cleared the line" in (verification_event.details or "")


def test_tank_retirement_blocks_executing_and_uncleared_unknown_actuator_work(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers, "Retirement actuator lock tank")
    device = register(client, auth_headers, tank["id"], "esp32-retirement-lock-01")
    key_headers = {"X-Device-Key": device["device_key"]}
    mark_bridge_online(client, device)

    command = queue(client, auth_headers, tank["id"], {"actuator": "pump_a", "action": "dispense", "payload": {}}).json()
    path = f"/device-ingestion/actuators/{command['command_id']}"
    assert client.post(f"{path}/executing", headers=key_headers).status_code == 200
    executing_retirement = client.post(f"/tanks/{tank['id']}/retire", headers=auth_headers, json={})
    assert executing_retirement.status_code == 409

    row = db_session.get(ActuatorCommand, command["command_id"])
    row.status = "outcome_unknown"
    row.outcome_unknown_at = utc_now()
    row.error_message = "Confirmation deadline elapsed; physical outcome is unknown"
    db_session.commit()
    unknown_retirement = client.post(f"/tanks/{tank['id']}/retire", headers=auth_headers, json={})
    assert unknown_retirement.status_code == 409

    cleared = client.post(
        f"/tanks/{tank['id']}/actuators/commands/{command['command_id']}/clear-uncertainty",
        headers=auth_headers,
        json={"note": "Verified the physical setup before retirement"},
    )
    assert cleared.status_code == 200
    successful_retirement = client.post(f"/tanks/{tank['id']}/retire", headers=auth_headers, json={})
    assert successful_retirement.status_code == 200
    assert successful_retirement.json()["lifecycle"] == "retired"


def test_pump_interlock_is_scoped_to_device_and_pump_and_claim_rechecks_concurrency(client, auth_headers):
    tank = create_tank(client, auth_headers, "Scoped pump interlock tank")
    first_device = register(client, auth_headers, tank["id"], "esp32-interlock-scope-a")
    second_device = register(client, auth_headers, tank["id"], "esp32-interlock-scope-b")
    mark_bridge_online(client, first_device)
    mark_bridge_online(client, second_device)

    first = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "pump_a", "action": "dispense", "payload": {}},
        device_id=first_device["device_id"],
    ).json()
    competing = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "pump_a", "action": "dispense", "payload": {}},
        device_id=first_device["device_id"],
    ).json()
    second = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "pump_a", "action": "dispense", "payload": {}},
        device_id=second_device["device_id"],
    ).json()
    first_path = f"/device-ingestion/actuators/{first['command_id']}"
    competing_path = f"/device-ingestion/actuators/{competing['command_id']}"
    second_path = f"/device-ingestion/actuators/{second['command_id']}"
    assert client.post(f"{first_path}/executing", headers={"X-Device-Key": first_device["device_key"]}).status_code == 200
    assert client.post(f"{competing_path}/executing", headers={"X-Device-Key": first_device["device_key"]}).status_code == 409
    # The second device is independent, while a second queued command for the
    # first device cannot claim once the first dispense is executing.
    assert client.post(f"{second_path}/executing", headers={"X-Device-Key": second_device["device_key"]}).status_code == 200

    same_device_b = queue(
        client,
        auth_headers,
        tank["id"],
        {"actuator": "pump_b", "action": "dispense", "payload": {}},
        device_id=first_device["device_id"],
    )
    assert same_device_b.status_code == 201


def test_physical_verification_clearance_is_admin_only(client, auth_headers, db_session):
    tank = create_tank(client, auth_headers, "Clearance permissions tank")
    device = register(client, auth_headers, tank["id"], "esp32-clearance-permissions")
    mark_bridge_online(client, device)
    command = queue(client, auth_headers, tank["id"], {"actuator": "pump_a", "action": "stop", "payload": {}}).json()
    row = db_session.get(ActuatorCommand, command["command_id"])
    row.status = "outcome_unknown"
    row.outcome_unknown_at = utc_now()
    db_session.commit()
    staff = staff_headers(client, db_session)
    path = f"/tanks/{tank['id']}/actuators/commands/{command['command_id']}/clear-uncertainty"
    assert client.post(path, headers=staff, json={}).status_code == 403
    assert client.post(path, headers={"X-Device-Key": device["device_key"]}, json={}).status_code == 401
    assert client.post(path, json={}).status_code == 401
