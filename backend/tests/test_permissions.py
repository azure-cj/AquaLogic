from datetime import datetime, timezone

from app.models import Alert, AlertSeverity, Customer, FishSpecies, SensorReading, Tank, User
from app.security import get_password_hash
from app.services.decision_engine import ensure_default_thresholds


def _headers_for_user(client, *, email: str, password: str = "password123"):
    response = client.post("/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _create_staff(db_session):
    staff = User(
        name="Operations Staff",
        email="operations@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
    )
    db_session.add(staff)
    db_session.commit()
    return staff


def _seed_operational_data(db_session):
    ensure_default_thresholds(db_session)
    customer = Customer(name="Permission Customer")
    tank = Tank(name="Permission Tank", location="Operations Rack", customer=customer)
    fish = FishSpecies(
        common_name="Permission Guppy",
        scientific_name="Poecilia permissionensis",
    )
    db_session.add_all([customer, tank, fish])
    db_session.flush()
    reading = SensorReading(
        tank_id=tank.id,
        timestamp=datetime.now(timezone.utc),
        temperature=25,
        ph=7,
        turbidity=2,
        dissolved_oxygen=6,
        tds=100,
        ammonia=0.1,
    )
    alert = Alert(
        tank_id=tank.id,
        reading=reading,
        parameter="temperature",
        severity=AlertSeverity.warning,
        message="Permission test alert",
    )
    db_session.add_all([reading, alert])
    db_session.commit()
    return tank, fish, alert


def test_staff_can_use_every_staff_capability(client, db_session):
    _create_staff(db_session)
    tank, fish, alert = _seed_operational_data(db_session)
    headers = _headers_for_user(client, email="operations@example.com")

    readable_routes = [
        ("GET", "/fleet"),
        ("GET", "/analytics/fleet?range=24h"),
        ("GET", "/tanks"),
        ("GET", f"/tanks/{tank.id}"),
        ("GET", f"/tanks/{tank.id}/operations"),
        ("GET", f"/tanks/{tank.id}/sensors"),
        ("GET", f"/tanks/{tank.id}/sensors/history"),
        ("GET", "/alerts"),
        ("GET", f"/tanks/{tank.id}/alerts"),
        ("GET", "/alerts/history"),
        ("GET", "/fish"),
        ("GET", f"/fish/{fish.id}"),
        ("GET", f"/tanks/{tank.id}/species-suitability"),
        ("GET", "/customers"),
        ("GET", "/thresholds"),
    ]
    for method, path in readable_routes:
        response = client.request(method, path, headers=headers)
        assert response.status_code == 200, f"{method} {path}: {response.text}"

    resolved = client.put(f"/alerts/{alert.id}/resolve", headers=headers)
    assert resolved.status_code == 200
    assigned = client.post(
        f"/tanks/{tank.id}/fish",
        headers=headers,
        json={"fish_species_id": fish.id},
    )
    assert assigned.status_code == 201
    removed = client.delete(f"/tanks/{tank.id}/fish/{fish.id}", headers=headers)
    assert removed.status_code == 204


def test_staff_is_denied_every_administrator_only_browser_capability(client, db_session):
    _create_staff(db_session)
    tank, fish, _ = _seed_operational_data(db_session)
    headers = _headers_for_user(client, email="operations@example.com")
    valid_fish = {"common_name": "Denied Fish", "scientific_name": "Danio deniedensis"}
    valid_reading = {
        "temperature": 25,
        "ph": 7,
        "turbidity": 2,
        "tds": 100,
    }
    admin_only_routes = [
        ("GET", "/users", {}),
        ("POST", "/users", {"json": {"name": "Denied", "email": "denied@example.com", "role": "staff"}}),
        ("PUT", "/users/999999", {"json": {"name": "Denied"}}),
        ("POST", "/users/999999/reset-password", {}),
        ("POST", "/tanks", {"json": {"name": "Denied Tank", "location": "Rack"}}),
        ("PUT", f"/tanks/{tank.id}", {"json": {"location": "Denied"}}),
        ("DELETE", f"/tanks/{tank.id}", {}),
        ("POST", f"/tanks/{tank.id}/hero-image", {"files": {"image": ("hero.jpg", b"not-an-image", "image/jpeg")}}),
        ("POST", "/fish", {"json": valid_fish}),
        ("PUT", f"/fish/{fish.id}", {"json": {"common_name": "Denied"}}),
        ("DELETE", f"/fish/{fish.id}", {}),
        ("POST", f"/fish/{fish.id}/photo-image", {"files": {"image": ("fish.jpg", b"not-an-image", "image/jpeg")}}),
        ("POST", f"/tanks/{tank.id}/sensors", {"json": valid_reading}),
        ("PUT", "/thresholds/temperature", {"json": {"unit": "C", "enabled": True}}),
        ("POST", "/customers", {"json": {"name": "Denied Customer"}}),
        ("PUT", "/customers/999999", {"json": {"name": "Denied"}}),
        ("DELETE", "/customers/999999", {}),
        ("POST", "/devices", {"json": {"device_id": "denied-device", "tank_id": tank.id}}),
        (
            "POST",
            f"/tanks/{tank.id}/actuators/commands",
            {"json": {"actuator": "uv", "action": "on", "payload": {}}},
        ),
        ("GET", f"/tanks/{tank.id}/actuators/status", {}),
        ("GET", f"/tanks/{tank.id}/actuators/history", {}),
        ("GET", "/security/audit-events", {}),
    ]
    for method, path, kwargs in admin_only_routes:
        response = client.request(method, path, headers=headers, **kwargs)
        assert response.status_code == 403, f"{method} {path}: {response.status_code} {response.text}"


def test_public_and_device_boundaries_do_not_accept_staff_bearer_tokens(client, db_session):
    _create_staff(db_session)
    tank, _, _ = _seed_operational_data(db_session)
    headers = _headers_for_user(client, email="operations@example.com")

    public_response = client.get(f"/public/tanks/{tank.public_id}", headers=headers)
    assert public_response.status_code == 200

    device_response = client.post(
        "/device-ingestion/readings",
        headers={**headers, "X-Device-Key": "not-a-device-key"},
        json={"temperature": 25, "ph": 7, "turbidity": 2, "tds": 100},
    )
    assert device_response.status_code == 401
