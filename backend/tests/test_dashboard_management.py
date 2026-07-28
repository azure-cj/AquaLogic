from datetime import datetime, timedelta, timezone

from sqlalchemy import select

from app.models import (
    Alert,
    AlertSeverity,
    SensorReading,
    Tank,
    ThresholdConfig,
    ThresholdRevision,
    User,
)
from app.security import get_password_hash


def _tank(client, headers, name="Dashboard tank"):
    response = client.post("/tanks", headers=headers, json={"name": name, "location": "Rack"})
    assert response.status_code == 201
    return response.json()


def test_alert_history_filters_and_analytics_buckets(client, auth_headers, db_session):
    tank = _tank(client, auth_headers)
    base = datetime.now(timezone.utc).replace(second=0, microsecond=0) - timedelta(minutes=5)
    reading = SensorReading(tank_id=tank["id"], timestamp=base, temperature=25, ph=7, turbidity=2, dissolved_oxygen=6, tds=100, ammonia=.1)
    db_session.add(reading)
    db_session.flush()
    db_session.add_all([
        SensorReading(tank_id=tank["id"], timestamp=base + timedelta(seconds=10), temperature=25, ph=7, turbidity=2, dissolved_oxygen=6, tds=100, ammonia=.1),
        SensorReading(tank_id=tank["id"], timestamp=base + timedelta(seconds=35), temperature=25, ph=7, turbidity=2, dissolved_oxygen=6, tds=100, ammonia=.1),
        SensorReading(tank_id=tank["id"], timestamp=base - timedelta(hours=25), temperature=25, ph=7, turbidity=2, dissolved_oxygen=6, tds=100, ammonia=.1),
    ])
    db_session.add(Alert(tank_id=tank["id"], reading_id=reading.id, parameter="ammonia", severity=AlertSeverity.critical, message="critical ammonia"))
    db_session.commit()
    response = client.get("/alerts/history?parameter=ammonia&severity=critical", headers=auth_headers)
    assert response.status_code == 200
    assert len(response.json()) == 1
    analytics = client.get("/analytics/fleet?range=24h", headers=auth_headers)
    assert analytics.status_code == 200
    payload = analytics.json()
    assert sum(bucket["critical"] for bucket in payload["alert_series"]) == 1
    assert payload["alert_events"][0]["value"] == .1
    assert len(payload["fleet_series"]) == 96
    assert any(point["values"]["temperature"] == 25 for point in payload["fleet_series"])
    assert any(point["values"]["temperature"] is None for point in payload["fleet_series"])
    tank_uptime = next(item for item in analytics.json()["uptime"] if item["tank_id"] == tank["id"])
    assert tank_uptime["reported_intervals"] == 2
    assert tank_uptime["previous_reported_intervals"] == 1
    assert tank_uptime["expected_intervals"] == 24 * 120
    assert tank_uptime["status"] == "critical"
    assert payload["uptime_comparison"]["change"] > 0

    selected = client.get(
        f"/analytics/fleet?range=24h&tank_id={tank['id']}",
        headers=auth_headers,
    )
    assert selected.status_code == 200
    assert selected.json()["tank_series"][0]["tank_name"] == tank["name"]

    custom_start = (base - timedelta(hours=1)).isoformat().replace("+00:00", "Z")
    custom_end = (base + timedelta(hours=1)).isoformat().replace("+00:00", "Z")
    custom = client.get(
        f"/analytics/fleet?range=custom&start={custom_start}&end={custom_end}&bucket=15m",
        headers=auth_headers,
    )
    assert custom.status_code == 200
    assert len(custom.json()["fleet_series"]) == 8


def test_admin_staff_lifecycle_and_threshold_validation(client, db_session):
    admin = User(name="Admin", email="admin@example.com", role="admin", hashed_password=get_password_hash("password123"))
    db_session.add(admin)
    db_session.add(ThresholdConfig(parameter="ammonia", unit="ppm", warning_max=.25, critical_max=.5))
    db_session.commit()
    login = client.post("/auth/login", json={"email": admin.email, "password": "password123"})
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    created = client.post("/users", headers=headers, json={"name": "New Staff", "email": "new@example.com", "role": "staff"})
    assert created.status_code == 201
    new_id = created.json()["user"]["id"]
    assert client.put(f"/users/{new_id}", headers=headers, json={"role": "admin", "is_active": False}).status_code == 200
    assert client.post(f"/users/{new_id}/reset-password", headers=headers).status_code == 200
    invalid = client.put("/thresholds/ammonia", headers=headers, json={"unit": "ppm", "critical_min": 3, "warning_min": 2, "warning_max": 1, "critical_max": 0, "enabled": True})
    assert invalid.status_code == 422
    valid = client.put(
        "/thresholds/ammonia",
        headers=headers,
        json={
            "unit": "ppm",
            "warning_min": None,
            "warning_max": .2,
            "critical_min": None,
            "critical_max": .4,
            "enabled": True,
        },
    )
    assert valid.status_code == 200
    revisions = list(
        db_session.scalars(
            select(ThresholdRevision)
            .where(ThresholdRevision.parameter == "ammonia")
            .order_by(ThresholdRevision.effective_from)
        ).all()
    )
    assert len(revisions) == 2
    assert revisions[-1].warning_max == .2
    revision_boundary = datetime.now(timezone.utc) - timedelta(minutes=20)
    revisions[0].effective_from = revision_boundary - timedelta(minutes=20)
    revisions[1].effective_from = revision_boundary
    db_session.commit()
    threshold_start = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat().replace("+00:00", "Z")
    threshold_end = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat().replace("+00:00", "Z")
    analytics = client.get(
        "/analytics/fleet?range=custom"
        f"&start={threshold_start}&end={threshold_end}&bucket=15m",
        headers=headers,
    )
    assert analytics.status_code == 200
    segments = [
        segment
        for segment in analytics.json()["threshold_segments"]
        if segment["parameter"] == "ammonia"
    ]
    assert len(segments) == 2
    assert segments[-1]["warning_max"] == .2


def test_analytics_query_validation(client, auth_headers):
    first = _tank(client, auth_headers, "One")
    second = _tank(client, auth_headers, "Two")
    third = _tank(client, auth_headers, "Three")
    fourth = _tank(client, auth_headers, "Four")
    too_many = "&".join(
        f"tank_id={tank['id']}" for tank in (first, second, third, fourth)
    )
    assert client.get(
        f"/analytics/fleet?range=24h&{too_many}",
        headers=auth_headers,
    ).status_code == 422
    assert client.get(
        "/analytics/fleet?range=custom",
        headers=auth_headers,
    ).status_code == 422
    assert client.get(
        "/analytics/fleet?range=custom"
        "&start=2026-01-01T00:00:00Z&end=2026-03-01T00:00:00Z",
        headers=auth_headers,
    ).status_code == 422
