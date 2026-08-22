from app.models import SecurityAuditEvent


def _create_tank(client, headers, name="Tank Alpha"):
    response = client.post(
        "/tanks",
        headers=headers,
        json={
            "name": name,
            "location": "Front Display",
            "description": "Main test tank",
        },
    )
    assert response.status_code == 201
    return response.json()


def _create_fish(client, headers, common_name="Test Guppy"):
    response = client.post(
        "/fish",
        headers=headers,
        json={
            "common_name": common_name,
            "scientific_name": "Poecilia reticulata",
            "category": "Livebearers",
            "diet_type": "Omnivore",
            "diet": "Flakes, pellets, and vegetable supplements.",
            "ideal_temp_min": 22.0,
            "ideal_temp_max": 28.0,
            "ideal_ph_min": 7.0,
            "ideal_ph_max": 8.0,
            "ideal_tds_min": 150.0,
            "ideal_tds_max": 300.0,
        },
    )
    assert response.status_code == 201
    return response.json()


def test_tank_crud_flow(client, auth_headers):
    tank = _create_tank(client, auth_headers)
    tank_id = tank["id"]

    list_response = client.get("/tanks", headers=auth_headers)
    assert list_response.status_code == 200
    assert len(list_response.json()) == 1

    detail_response = client.get(f"/tanks/{tank_id}", headers=auth_headers)
    assert detail_response.status_code == 200
    assert detail_response.json()["name"] == "Tank Alpha"

    update_response = client.put(
        f"/tanks/{tank_id}",
        headers=auth_headers,
        json={"location": "Breeding Room"},
    )
    assert update_response.status_code == 200
    assert update_response.json()["location"] == "Breeding Room"

    active_delete_response = client.delete(f"/tanks/{tank_id}", headers=auth_headers)
    assert active_delete_response.status_code == 409

    retire_response = client.post(
        f"/tanks/{tank_id}/retire",
        headers=auth_headers,
        json={"note": "Display replaced during refurbishment"},
    )
    assert retire_response.status_code == 200
    assert retire_response.json()["lifecycle"] == "retired"
    assert retire_response.json()["is_public"] is False
    assert retire_response.json()["retirement_note"] == "Display replaced during refurbishment"
    assert client.get(f"/public/tanks/{tank['public_id']}").status_code == 404

    assert client.get("/tanks", headers=auth_headers).json() == []
    assert client.get("/tanks?lifecycle=retired", headers=auth_headers).json()[0]["id"] == tank_id
    assert client.get("/tanks?lifecycle=all", headers=auth_headers).json()[0]["lifecycle"] == "retired"

    idempotent_retire = client.post(f"/tanks/{tank_id}/retire", headers=auth_headers, json={})
    assert idempotent_retire.status_code == 200
    assert idempotent_retire.json()["retirement_note"] == "Display replaced during refurbishment"

    delete_response = client.delete(f"/tanks/{tank_id}", headers=auth_headers)
    assert delete_response.status_code == 204

    missing_response = client.get(f"/tanks/{tank_id}", headers=auth_headers)
    assert missing_response.status_code == 404


def test_fish_crud_and_assignment_flow(client, auth_headers):
    tank = _create_tank(client, auth_headers)
    fish = _create_fish(client, auth_headers)
    assert "ideal_do_min" not in fish

    assign_response = client.post(
        f"/tanks/{tank['id']}/fish",
        headers=auth_headers,
        json={"fish_species_id": fish["id"]},
    )
    assert assign_response.status_code == 201

    fish_list = client.get("/fish", headers=auth_headers)
    assert fish_list.status_code == 200
    assert fish_list.json()[0]["tank_count"] == 1
    assert fish_list.json()[0]["category"] == "Livebearers"
    assert fish_list.json()[0]["diet_type"] == "Omnivore"
    assert fish_list.json()[0]["ideal_temp_min"] == 22.0
    assert fish_list.json()[0]["ideal_temp_max"] == 28.0
    assert fish_list.json()[0]["assigned_tanks"] == [{"id": tank["id"], "name": tank["name"]}]

    protected_delete = client.delete(f"/fish/{fish['id']}", headers=auth_headers)
    assert protected_delete.status_code == 409
    assert protected_delete.json()["detail"] == "Fish species is assigned to 1 tank"

    tank_detail = client.get(f"/tanks/{tank['id']}", headers=auth_headers)
    assert tank_detail.status_code == 200
    assert len(tank_detail.json()["fish_species"]) == 1

    remove_response = client.delete(
        f"/tanks/{tank['id']}/fish/{fish['id']}",
        headers=auth_headers,
    )
    assert remove_response.status_code == 204

    fish_detail = client.get(f"/fish/{fish['id']}", headers=auth_headers)
    assert fish_detail.status_code == 200
    assert fish_detail.json()["tank_count"] == 0

    fish_delete = client.delete(f"/fish/{fish['id']}", headers=auth_headers)
    assert fish_delete.status_code == 204


def test_retired_tank_is_read_only_preserves_device_history_and_deactivates_bridge(client, auth_headers, db_session):
    tank = _create_tank(client, auth_headers, "Retired read-only tank")
    fish = _create_fish(client, auth_headers, "Retired tank fish")
    device_response = client.post(
        "/devices",
        headers=auth_headers,
        json={"device_id": "retired-read-only-device", "tank_id": tank["id"]},
    )
    assert device_response.status_code == 201
    device = device_response.json()

    queued = client.post(
        f"/tanks/{tank['id']}/actuators/commands",
        headers=auth_headers,
        json={"device_id": device["device_id"], "actuator": "uv", "action": "on", "payload": {}},
    )
    assert queued.status_code == 201

    retired = client.post(
        f"/tanks/{tank['id']}/retire",
        headers=auth_headers,
        json={"note": "No longer in service"},
    )
    assert retired.status_code == 200
    assert retired.json()["lifecycle"] == "retired"

    assert client.get(f"/devices/{device['device_id']}", headers=auth_headers).json()["status"] == "disabled"
    assert client.post(
        "/device-ingestion/readings",
        headers={"X-Device-Key": device["device_key"]},
        json={"temperature": 25, "ph": 7, "turbidity": 2, "tds": 100},
    ).status_code == 401

    history = client.get(f"/tanks/{tank['id']}/actuators/history", headers=auth_headers)
    assert history.status_code == 200
    assert history.json()["total"] == 1
    assert history.json()["items"][0]["command_id"] == queued.json()["command_id"]

    assert client.put(
        f"/tanks/{tank['id']}",
        headers=auth_headers,
        json={"location": "Should remain unchanged"},
    ).status_code == 409
    assert client.post(
        f"/tanks/{tank['id']}/sensors",
        headers=auth_headers,
        json={"temperature": 25, "ph": 7, "turbidity": 2, "tds": 100},
    ).status_code == 409
    assert client.post(
        f"/tanks/{tank['id']}/fish",
        headers=auth_headers,
        json={"fish_species_id": fish["id"]},
    ).status_code == 409
    assert client.post(
        "/devices",
        headers=auth_headers,
        json={"device_id": "retired-second-device", "tank_id": tank["id"]},
    ).status_code == 409
    assert client.post(
        f"/tanks/{tank['id']}/actuators/commands",
        headers=auth_headers,
        json={"actuator": "uv", "action": "on", "payload": {}},
    ).status_code == 409

    audit_events = db_session.query(SecurityAuditEvent).filter_by(event_type="tank.retire").all()
    assert len(audit_events) == 1
    assert audit_events[0].actor_user_id is not None
