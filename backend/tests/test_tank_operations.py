from datetime import datetime, timedelta, timezone

from app.models import Alert, AlertSeverity, SensorReading
from app.services.decision_engine import ensure_default_thresholds


def _tank(client, headers, name="Operations Tank"):
    response = client.post("/tanks", headers=headers, json={"name": name, "location": "Test rack"})
    assert response.status_code == 201
    return response.json()


def _reading(tank_id, timestamp):
    return SensorReading(
        tank_id=tank_id, timestamp=timestamp, temperature=25, ph=7.2, turbidity=2,
        dissolved_oxygen=6, tds=160, ammonia=.1,
    )


def test_operations_requires_auth_and_handles_unknown_tank(client, auth_headers):
    assert client.get("/tanks/404/operations").status_code == 401
    assert client.get("/tanks/404/operations", headers=auth_headers).status_code == 404


def test_operations_returns_consistent_states_and_unresolved_alerts(client, auth_headers, db_session):
    ensure_default_thresholds(db_session)
    tank = _tank(client, auth_headers)
    other = _tank(client, auth_headers, "Other Operations Tank")
    reading = _reading(tank["id"], datetime.now(timezone.utc))
    db_session.add(reading)
    db_session.flush()
    active = Alert(tank_id=tank["id"], reading_id=reading.id, parameter="ph", severity=AlertSeverity.warning, message="Active")
    resolved = Alert(tank_id=tank["id"], reading_id=reading.id, parameter="tds", severity=AlertSeverity.warning, message="Resolved", is_resolved=True)
    foreign = Alert(tank_id=other["id"], reading_id=None, parameter="ph", severity=AlertSeverity.critical, message="Other")
    db_session.add_all([active, resolved, foreign])
    db_session.commit()

    response = client.get(f"/tanks/{tank['id']}/operations", headers=auth_headers)
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "normal"
    assert payload["latest_reading"]["timestamp"].endswith(("+00:00", "Z"))
    assert payload["evaluated_at"].endswith(("+00:00", "Z"))
    assert set(payload["parameter_statuses"]) == {"temperature", "ph", "turbidity", "dissolved_oxygen", "tds", "ammonia"}
    assert [item["message"] for item in payload["active_alerts"]] == ["Active"]

    client.put(f"/alerts/{active.id}/resolve", headers=auth_headers)
    assert client.get(f"/tanks/{tank['id']}/operations", headers=auth_headers).json()["active_alerts"] == []


def test_operations_reports_offline_for_stale_and_missing_readings(client, auth_headers, db_session):
    ensure_default_thresholds(db_session)
    tank = _tank(client, auth_headers)
    missing = client.get(f"/tanks/{tank['id']}/operations", headers=auth_headers).json()
    assert missing["status"] == "offline"
    assert missing["latest_reading"] is None
    assert set(missing["parameter_statuses"].values()) == {"unavailable"}

    db_session.add(_reading(tank["id"], datetime.now(timezone.utc) - timedelta(minutes=3)))
    db_session.commit()
    stale = client.get(f"/tanks/{tank['id']}/operations", headers=auth_headers).json()
    assert stale["status"] == "offline"
    assert set(stale["parameter_statuses"].values()) == {"offline"}


def test_tank_detail_customer_and_fleet_species_summary(
    client, auth_headers, db_session
):
    ensure_default_thresholds(db_session)
    customer_response = client.post(
        "/customers",
        headers=auth_headers,
        json={"name": "JRed Client", "is_active": True},
    )
    assert customer_response.status_code == 201
    customer = customer_response.json()
    tank_response = client.post(
        "/tanks",
        headers=auth_headers,
        json={
            "name": "Customer Care Tank",
            "location": "Front rack",
            "customer_id": customer["id"],
        },
    )
    assert tank_response.status_code == 201
    tank = tank_response.json()
    fish_response = client.post(
        "/fish",
        headers=auth_headers,
        json={
            "common_name": "Warmwater Fish",
            "scientific_name": "Piscis calidus",
            "ideal_temp_min": 28,
            "ideal_temp_max": 30,
        },
    )
    assert fish_response.status_code == 201
    fish = fish_response.json()
    assert client.post(
        f"/tanks/{tank['id']}/fish",
        headers=auth_headers,
        json={"fish_species_id": fish["id"]},
    ).status_code == 201
    db_session.add(
        _reading(tank["id"], datetime.now(timezone.utc))
    )
    db_session.commit()

    detail = client.get(f"/tanks/{tank['id']}", headers=auth_headers)
    assert detail.status_code == 200
    assert detail.json()["customer"] == {
        "id": customer["id"],
        "name": "JRed Client",
    }

    fleet = client.get("/fleet", headers=auth_headers)
    assert fleet.status_code == 200
    summary = next(item for item in fleet.json() if item["id"] == tank["id"])
    assert summary["assigned_species_count"] == 1
    assert summary["species_care_status"] == "attention"
    assert db_session.query(Alert).count() == 0
