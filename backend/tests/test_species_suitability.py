from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from app.models import Alert, AlertSeverity, SensorReading
from app.services.species_suitability import evaluate_species, evaluate_tank_species_suitability


NOW = datetime(2026, 7, 28, 10, 15, 30, tzinfo=timezone.utc)


def _species(**overrides):
    values = {
        "id": 7,
        "common_name": "Discus",
        "scientific_name": "Symphysodon aequifasciatus",
        "ideal_temp_min": 28.0,
        "ideal_temp_max": 31.0,
        "ideal_ph_min": 6.0,
        "ideal_ph_max": 7.0,
        "ideal_do_min": 5.0,
        "ideal_tds_min": 50.0,
        "ideal_tds_max": 150.0,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def _reading(**overrides):
    values = {
        "id": 812,
        "timestamp": NOW - timedelta(seconds=18),
        "temperature": 28.0,
        "ph": 6.0,
        "dissolved_oxygen": 5.0,
        "tds": 50.0,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def _create_tank(client, headers, name="Suitability tank"):
    response = client.post("/tanks", headers=headers, json={"name": name, "location": "Test rack"})
    assert response.status_code == 201
    return response.json()


def _create_fish(client, headers, **overrides):
    payload = {
        "common_name": "Discus",
        "scientific_name": "Symphysodon aequifasciatus",
        "ideal_temp_min": 28.0,
        "ideal_temp_max": 31.0,
        "ideal_ph_min": 6.0,
        "ideal_ph_max": 7.0,
        "ideal_do_min": 5.0,
        "ideal_tds_min": 50.0,
        "ideal_tds_max": 150.0,
    }
    payload.update(overrides)
    response = client.post("/fish", headers=headers, json=payload)
    assert response.status_code == 201
    return response.json()


def test_service_boundaries_one_sided_and_aggregation_are_deterministic():
    species = _species(ideal_temp_max=None, ideal_ph_min=None, ideal_ph_max=None, ideal_tds_min=None, ideal_tds_max=50.0)
    result = evaluate_species(species, _reading(temperature=28.0, tds=50.0), evaluated_at=NOW)

    assert result["status"] == "suitable"
    assert [item["reason"] for item in result["checks"]] == [
        "within_preferred_range", "species_range_missing", "within_preferred_range", "within_preferred_range",
    ]
    below = evaluate_species(species, _reading(temperature=27.99), evaluated_at=NOW)
    above = evaluate_species(species, _reading(tds=50.01), evaluated_at=NOW)
    assert below["status"] == above["status"] == "attention"
    assert below["checks"][0]["reason"] == "below_preferred_minimum"
    assert above["checks"][3]["reason"] == "above_preferred_maximum"


def test_service_handles_missing_stale_null_and_invalid_legacy_values():
    species = _species()
    no_reading = evaluate_species(species, None, evaluated_at=NOW)
    assert {item["reason"] for item in no_reading["checks"]} == {"no_current_reading"}

    stale = evaluate_species(species, _reading(timestamp=NOW - timedelta(seconds=91)), evaluated_at=NOW)
    assert stale["status"] == "unavailable"
    assert stale["checks"][0]["reason"] == "stale_reading"

    missing = evaluate_species(species, _reading(ph=None), evaluated_at=NOW)
    assert missing["checks"][1]["reason"] == "reading_value_missing"

    legacy = evaluate_species(_species(ideal_temp_min=31.0, ideal_temp_max=28.0), _reading(), evaluated_at=NOW)
    assert legacy["checks"][0]["reason"] == "invalid_species_range"


def test_tank_service_does_not_count_missing_species_configuration_as_required():
    tank = SimpleNamespace(id=3, fish_species=[_species(ideal_ph_min=None, ideal_ph_max=None)])
    result = evaluate_tank_species_suitability(tank, _reading(), evaluated_at=NOW)
    assert result["status"] == "suitable"
    assert result["species_counts"] == {"suitable": 1, "attention": 0, "unavailable": 0}

    empty = evaluate_tank_species_suitability(SimpleNamespace(id=3, fish_species=[]), None, evaluated_at=NOW)
    assert empty["status"] == "unavailable"
    assert empty["summary_reason"] == "no_species_assigned"
    assert empty["reading"] is None


def test_species_suitability_endpoint_requires_auth_and_reports_no_assignment(client, auth_headers):
    tank = _create_tank(client, auth_headers)
    assert client.get(f"/tanks/{tank['id']}/species-suitability").status_code == 401

    response = client.get(f"/tanks/{tank['id']}/species-suitability", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["summary_reason"] == "no_species_assigned"
    assert response.json()["species"] == []
    assert client.get("/tanks/99999/species-suitability", headers=auth_headers).status_code == 404


def test_endpoint_lifecycle_is_derived_and_preserves_operational_alerts(client, auth_headers, db_session):
    tank = _create_tank(client, auth_headers)
    fish = _create_fish(client, auth_headers)
    assert client.post(f"/tanks/{tank['id']}/fish", headers=auth_headers, json={"fish_species_id": fish["id"]}).status_code == 201
    first_reading = SensorReading(tank_id=tank["id"], timestamp=datetime.now(timezone.utc) - timedelta(seconds=20), temperature=25, ph=6.5, turbidity=1, dissolved_oxygen=6, tds=100, ammonia=0)
    db_session.add(first_reading)
    db_session.commit()

    response = client.get(f"/tanks/{tank['id']}/species-suitability", headers=auth_headers)
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "attention"
    assert payload["reading"]["timestamp"].endswith(("Z", "+00:00"))

    operational_alert = Alert(tank_id=tank["id"], reading_id=first_reading.id, parameter="ammonia", severity=AlertSeverity.warning, message="Operational ammonia warning")
    db_session.add(operational_alert)
    db_session.commit()
    client.get(f"/tanks/{tank['id']}/species-suitability", headers=auth_headers)
    client.get(f"/tanks/{tank['id']}/species-suitability", headers=auth_headers)
    assert db_session.query(Alert).count() == 1
    assert db_session.get(Alert, operational_alert.id).message == "Operational ammonia warning"

    db_session.add(SensorReading(tank_id=tank["id"], timestamp=datetime.now(timezone.utc) - timedelta(seconds=5), temperature=29, ph=6.5, turbidity=1, dissolved_oxygen=6, tds=100, ammonia=0))
    db_session.commit()
    suitable = client.get(f"/tanks/{tank['id']}/species-suitability", headers=auth_headers).json()
    assert suitable["status"] == "suitable"
    assert suitable["species"][0]["checks"][0]["current_value"] == 29

    assert client.put(f"/fish/{fish['id']}", headers=auth_headers, json={"ideal_temp_min": 30}).status_code == 200
    edited = client.get(f"/tanks/{tank['id']}/species-suitability", headers=auth_headers).json()
    assert edited["status"] == "attention"

    assert client.delete(f"/tanks/{tank['id']}/fish/{fish['id']}", headers=auth_headers).status_code == 204
    unassigned = client.get(f"/tanks/{tank['id']}/species-suitability", headers=auth_headers).json()
    assert unassigned["summary_reason"] == "no_species_assigned"
    assert unassigned["species"] == []


def test_species_range_create_and_effective_partial_update_validation(client, auth_headers):
    invalid = client.post(
        "/fish",
        headers=auth_headers,
        json={"common_name": "Invalid", "scientific_name": "Invalidus", "ideal_temp_min": 29, "ideal_temp_max": 28},
    )
    assert invalid.status_code == 422

    fish = _create_fish(client, auth_headers, ideal_temp_min=24, ideal_temp_max=28)
    response = client.put(f"/fish/{fish['id']}", headers=auth_headers, json={"ideal_temp_min": 29})
    assert response.status_code == 422
