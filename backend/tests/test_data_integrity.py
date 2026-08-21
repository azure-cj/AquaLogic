from datetime import datetime, timezone

import pytest
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from app.models import (
    ActuatorCommand,
    ActuatorState,
    ActuatorStateHistory,
    Alert,
    AlertSeverity,
    Customer,
    FishSpecies,
    RegisteredDevice,
    SecurityAuditEvent,
    SensorReading,
    Tank,
    TankFish,
    User,
)


def _reading(tank_id: int) -> SensorReading:
    return SensorReading(
        tank_id=tank_id,
        timestamp=datetime.now(timezone.utc),
        temperature=25,
        ph=7,
        turbidity=2,
        dissolved_oxygen=6,
        tds=100,
        ammonia=0.1,
    )


def test_sqlite_foreign_keys_are_enabled(db_session):
    assert db_session.execute(text("PRAGMA foreign_keys")).scalar() == 1


def test_customer_delete_preserves_tank_and_clears_reference(db_session):
    customer = Customer(name="Integrity Customer")
    tank = Tank(name="Integrity Customer Tank", location="Rack", customer=customer)
    db_session.add(tank)
    db_session.commit()
    customer_id = customer.id
    tank_id = tank.id

    db_session.delete(customer)
    db_session.commit()

    restored_tank = db_session.get(Tank, tank_id)
    assert restored_tank is not None
    assert restored_tank.customer_id is None
    assert db_session.get(Customer, customer_id) is None


def test_tank_delete_cascades_relational_records(db_session):
    tank = Tank(name="Integrity Cascade Tank", location="Rack")
    fish = FishSpecies(common_name="Cascade Fish", scientific_name="Cascade integrityus")
    user = User(name="Integrity Admin", email="integrity@example.com", hashed_password="hash", role="admin")
    db_session.add_all([tank, fish, user])
    db_session.flush()
    reading = _reading(tank.id)
    db_session.add(reading)
    db_session.flush()
    alert = Alert(
        tank_id=tank.id,
        reading_id=reading.id,
        parameter="temperature",
        severity=AlertSeverity.warning,
        message="Cascade alert",
    )
    device = RegisteredDevice(id="integrity-device", tank_id=tank.id, key_hash="integrity-key")
    db_session.add_all([alert, TankFish(tank_id=tank.id, fish_species_id=fish.id), device])
    db_session.flush()
    command = ActuatorCommand(
        command_id="integrity-command",
        device_id=device.id,
        tank_id=tank.id,
        actor_user_id=user.id,
        actuator="uv",
        action="on",
        payload_json="{}",
        status="queued",
        requested_at=datetime.now(timezone.utc),
        expires_at=datetime.now(timezone.utc),
    )
    state = ActuatorState(
        device_id=device.id,
        tank_id=tank.id,
        actuator="uv",
        state_json="{}",
        refreshed_at=datetime.now(timezone.utc),
    )
    history = ActuatorStateHistory(
        device_id=device.id,
        tank_id=tank.id,
        actuator="uv",
        command_id=command.command_id,
        state_json="{}",
        reported_at=datetime.now(timezone.utc),
    )
    db_session.add_all([command, state, history])
    db_session.commit()
    tank_id = tank.id

    db_session.delete(tank)
    db_session.commit()

    assert db_session.get(Tank, tank_id) is None
    assert db_session.query(SensorReading).filter_by(tank_id=tank_id).count() == 0
    assert db_session.query(Alert).filter_by(tank_id=tank_id).count() == 0
    assert db_session.query(TankFish).filter_by(tank_id=tank_id).count() == 0
    assert db_session.query(RegisteredDevice).filter_by(tank_id=tank_id).count() == 0
    assert db_session.query(ActuatorCommand).filter_by(tank_id=tank_id).count() == 0
    assert db_session.query(ActuatorState).filter_by(tank_id=tank_id).count() == 0
    assert db_session.query(ActuatorStateHistory).filter_by(tank_id=tank_id).count() == 0


def test_reading_delete_sets_alert_reading_reference_null(db_session):
    tank = Tank(name="Integrity Reading Tank", location="Rack")
    db_session.add(tank)
    db_session.flush()
    reading = _reading(tank.id)
    db_session.add(reading)
    db_session.flush()
    alert = Alert(
        tank_id=tank.id,
        reading_id=reading.id,
        parameter="ph",
        severity=AlertSeverity.warning,
        message="Reading reference",
    )
    db_session.add(alert)
    db_session.commit()

    db_session.delete(reading)
    db_session.commit()

    assert db_session.get(Alert, alert.id).reading_id is None


def test_tank_fish_composite_key_rejects_duplicate_assignment(db_session):
    tank = Tank(name="Integrity Assignment Tank", location="Rack")
    fish = FishSpecies(common_name="Assignment Fish", scientific_name="Assignment integrityus")
    db_session.add_all([tank, fish])
    db_session.flush()
    db_session.add(TankFish(tank_id=tank.id, fish_species_id=fish.id))
    db_session.commit()

    db_session.add(TankFish(tank_id=tank.id, fish_species_id=fish.id))
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()
    assert db_session.query(TankFish).count() == 1


def test_duplicate_email_is_rejected_without_partial_user_write(db_session):
    db_session.add(User(name="First User", email="duplicate@example.com", hashed_password="hash", role="staff"))
    db_session.commit()

    db_session.add(User(name="Duplicate User", email="duplicate@example.com", hashed_password="hash", role="staff"))
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()

    assert db_session.query(User).filter_by(email="duplicate@example.com").count() == 1


def test_duplicate_tank_name_and_device_key_are_rejected(db_session):
    tank = Tank(name="Unique Tank", location="Rack")
    second_tank = Tank(name="Second Tank", location="Rack")
    db_session.add_all([tank, second_tank])
    db_session.commit()

    db_session.add(Tank(name="Unique Tank", location="Another Rack"))
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()
    assert db_session.query(Tank).filter_by(name="Unique Tank").count() == 1

    first_device = RegisteredDevice(id="unique-device", tank_id=tank.id, key_hash="duplicate-key")
    db_session.add(first_device)
    db_session.commit()
    db_session.add(RegisteredDevice(id="second-device", tank_id=second_tank.id, key_hash="duplicate-key"))
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()
    assert db_session.query(RegisteredDevice).filter_by(key_hash="duplicate-key").count() == 1


def test_domain_and_audit_writes_roll_back_together_on_failure(db_session):
    db_session.add(Tank(name="Already Exists", location="Rack"))
    db_session.commit()

    db_session.add(Tank(name="Already Exists", location="Other Rack"))
    db_session.add(SecurityAuditEvent(event_type="tank.create", outcome="success"))
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()
    assert db_session.query(Tank).filter_by(name="Already Exists").count() == 1
    assert db_session.query(SecurityAuditEvent).count() == 0

    db_session.add(Tank(name="Audit Failure", location="Rack"))
    db_session.add(SecurityAuditEvent(event_type=None, outcome="success"))
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()
    assert db_session.query(Tank).filter_by(name="Audit Failure").count() == 0
    assert db_session.query(SecurityAuditEvent).count() == 0
