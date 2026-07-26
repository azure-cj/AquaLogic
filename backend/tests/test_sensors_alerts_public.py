from datetime import datetime, timedelta, timezone

import pytest

from app.models import Alert, AlertSeverity, SensorReading
from app.services.decision_engine import ensure_default_thresholds


def _create_tank(client, headers, name="Tank Sensor"):
    response = client.post(
        "/tanks",
        headers=headers,
        json={
            "name": name,
            "location": "Rear Rack",
            "description": "Sensor validation tank",
            "tank_code": f"PUBLIC-{name.replace(' ', '-').upper()}",
            "habitat_label": "Tropical community",
            "water_type": "freshwater",
            "volume_liters": 180,
            "established_on": "2026-03-01",
            "hero_image_url": "https://images.example.test/tank.webp",
        },
    )
    assert response.status_code == 201
    return response.json()


def _create_fish(client, headers):
    response = client.post(
        "/fish",
        headers=headers,
        json={
            "common_name": "Neon Tetra",
            "scientific_name": "Paracheirodon innesi",
            "ideal_temp_min": 22.0,
            "ideal_temp_max": 26.0,
            "ideal_ph_min": 6.0,
            "ideal_ph_max": 7.0,
            "ideal_do_min": 5.0,
            "ideal_tds_min": 50.0,
            "ideal_tds_max": 180.0,
        },
    )
    assert response.status_code == 201
    return response.json()


def test_sensor_endpoints_and_public_view(client, auth_headers, db_session):
    ensure_default_thresholds(db_session)
    tank = _create_tank(client, auth_headers)
    fish = _create_fish(client, auth_headers)

    assign_response = client.post(
        f"/tanks/{tank['id']}/fish",
        headers=auth_headers,
        json={"fish_species_id": fish["id"]},
    )
    assert assign_response.status_code == 201

    create_sensor = client.post(
        f"/tanks/{tank['id']}/sensors",
        headers=auth_headers,
        json={
            "temperature": 25.5,
            "ph": 7.2,
            "turbidity": 3.1,
            "dissolved_oxygen": 6.2,
            "tds": 180.0,
            "ammonia": 0.2,
            "is_mock": True,
        },
    )
    assert create_sensor.status_code == 201

    latest_sensor = client.get(f"/tanks/{tank['id']}/sensors", headers=auth_headers)
    assert latest_sensor.status_code == 200
    assert latest_sensor.json()["tank_id"] == tank["id"]

    history_sensor = client.get(f"/tanks/{tank['id']}/sensors/history", headers=auth_headers)
    assert history_sensor.status_code == 200
    assert len(history_sensor.json()) == 1

    public_response = client.get(f"/public/tanks/{tank['public_id']}")
    assert public_response.status_code == 200
    public_payload = public_response.json()
    assert "id" not in public_payload
    assert public_payload["tank_code"].startswith("PUBLIC-")
    assert public_payload["water_type"] == "freshwater"
    assert public_payload["volume_liters"] == 180
    assert len(public_payload["fish_species"]) == 1
    assert public_payload["latest_reading"]["temperature"] == 25.5
    assert "id" not in public_payload["latest_reading"]
    assert "tank_id" not in public_payload["latest_reading"]
    assert "is_mock" not in public_payload["latest_reading"]
    assert public_payload["status"] == "normal"
    assert public_payload["parameter_statuses"]["temperature"] == "normal"
    assert public_payload["parameter_statuses"]["ammonia"] == "normal"


def test_public_view_reports_stale_readings_without_leaking_private_ids(
    client, auth_headers, db_session
):
    ensure_default_thresholds(db_session)
    tank = _create_tank(client, auth_headers, name="Stale Display")
    db_session.add(
        SensorReading(
            tank_id=tank["id"],
            timestamp=datetime.now(timezone.utc) - timedelta(minutes=10),
            temperature=25.0,
            ph=7.1,
            turbidity=2.0,
            dissolved_oxygen=6.3,
            tds=180.0,
            ammonia=0.1,
        )
    )
    db_session.commit()

    response = client.get(f"/public/tanks/{tank['public_id']}")
    assert response.status_code == 200
    assert response.json()["status"] == "offline"
    assert set(response.json()["parameter_statuses"].values()) == {"offline"}
    assert "tank_id" not in response.json()["latest_reading"]


def test_public_view_without_readings_uses_unavailable_metric_states(client, auth_headers):
    tank = _create_tank(client, auth_headers, name="New Display")

    response = client.get(f"/public/tanks/{tank['public_id']}")
    assert response.status_code == 200
    assert response.json()["status"] == "offline"
    assert "latest_reading" not in response.json()
    assert set(response.json()["parameter_statuses"].values()) == {"unavailable"}


@pytest.mark.parametrize(
    ("name", "temperature", "expected"),
    [
        ("Warning Display", 29.0, "warning"),
        ("Critical Display", 31.0, "critical"),
    ],
)
def test_public_view_exposes_threshold_backed_metric_statuses(
    client, auth_headers, db_session, name, temperature, expected
):
    ensure_default_thresholds(db_session)
    tank = _create_tank(client, auth_headers, name=name)
    reading = client.post(
        f"/tanks/{tank['id']}/sensors",
        headers=auth_headers,
        json={
            "temperature": temperature,
            "ph": 7.2,
            "turbidity": 3.1,
            "dissolved_oxygen": 6.2,
            "tds": 180.0,
            "ammonia": 0.1,
            "is_mock": True,
        },
    )
    assert reading.status_code == 201

    response = client.get(f"/public/tanks/{tank['public_id']}")
    assert response.status_code == 200
    assert response.json()["status"] == expected
    assert response.json()["parameter_statuses"]["temperature"] == expected
    assert response.json()["parameter_statuses"]["ph"] == "normal"


def test_private_and_unknown_tanks_use_the_same_public_response(client, auth_headers):
    tank = _create_tank(client, auth_headers, name="Private Display")
    update = client.put(
        f"/tanks/{tank['id']}",
        headers=auth_headers,
        json={"is_public": False},
    )
    assert update.status_code == 200

    private_response = client.get(f"/public/tanks/{tank['public_id']}")
    unknown_response = client.get("/public/tanks/not-a-real-public-id")
    assert private_response.status_code == 404
    assert unknown_response.status_code == 404
    assert private_response.json() == unknown_response.json() == {"detail": "Tank not found"}


def test_alert_list_and_resolve(client, auth_headers, db_session):
    tank = _create_tank(client, auth_headers, name="Tank Alerts")

    sensor_response = client.post(
        f"/tanks/{tank['id']}/sensors",
        headers=auth_headers,
        json={
            "temperature": 29.0,
            "ph": 8.9,
            "turbidity": 12.0,
            "dissolved_oxygen": 4.5,
            "tds": 520.0,
            "ammonia": 0.7,
            "is_mock": True,
        },
    )
    assert sensor_response.status_code == 201
    reading_id = sensor_response.json()["id"]

    alert = Alert(
        tank_id=tank["id"],
        reading_id=reading_id,
        parameter="ph",
        severity=AlertSeverity.warning,
        message="pH above safe threshold",
        is_resolved=False,
    )
    db_session.add(alert)
    db_session.commit()
    db_session.refresh(alert)

    alerts_response = client.get("/alerts", headers=auth_headers)
    assert alerts_response.status_code == 200
    assert len(alerts_response.json()) == 1

    tank_alerts_response = client.get(f"/tanks/{tank['id']}/alerts", headers=auth_headers)
    assert tank_alerts_response.status_code == 200
    assert len(tank_alerts_response.json()) == 1

    resolve_response = client.put(f"/alerts/{alert.id}/resolve", headers=auth_headers)
    assert resolve_response.status_code == 200
    assert resolve_response.json()["is_resolved"] is True

    unresolved_after = client.get("/alerts", headers=auth_headers)
    assert unresolved_after.status_code == 200
    assert unresolved_after.json() == []
