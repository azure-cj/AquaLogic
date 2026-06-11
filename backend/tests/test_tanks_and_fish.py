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
            "ideal_temp_min": 22.0,
            "ideal_temp_max": 28.0,
            "ideal_ph_min": 7.0,
            "ideal_ph_max": 8.0,
            "ideal_do_min": 5.0,
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

    delete_response = client.delete(f"/tanks/{tank_id}", headers=auth_headers)
    assert delete_response.status_code == 204

    missing_response = client.get(f"/tanks/{tank_id}", headers=auth_headers)
    assert missing_response.status_code == 404


def test_fish_crud_and_assignment_flow(client, auth_headers):
    tank = _create_tank(client, auth_headers)
    fish = _create_fish(client, auth_headers)

    assign_response = client.post(
        f"/tanks/{tank['id']}/fish",
        headers=auth_headers,
        json={"fish_species_id": fish["id"]},
    )
    assert assign_response.status_code == 201

    tank_detail = client.get(f"/tanks/{tank['id']}", headers=auth_headers)
    assert tank_detail.status_code == 200
    assert len(tank_detail.json()["fish_species"]) == 1

    remove_response = client.delete(
        f"/tanks/{tank['id']}/fish/{fish['id']}",
        headers=auth_headers,
    )
    assert remove_response.status_code == 204

    fish_delete = client.delete(f"/fish/{fish['id']}", headers=auth_headers)
    assert fish_delete.status_code == 204
