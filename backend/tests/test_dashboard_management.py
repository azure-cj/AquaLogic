from datetime import datetime, timedelta, timezone

from app.models import Alert, AlertSeverity, SensorReading, Tank, ThresholdConfig, User
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
    assert analytics.json()["alert_series"][0]["critical"] == 1
    tank_uptime = next(item for item in analytics.json()["uptime"] if item["tank_id"] == tank["id"])
    assert tank_uptime["reported_intervals"] == 2
    assert tank_uptime["previous_reported_intervals"] == 1
    assert tank_uptime["expected_intervals"] == 24 * 120
    assert analytics.json()["uptime_comparison"]["change"] > 0


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
