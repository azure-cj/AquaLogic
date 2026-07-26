def test_login_success(client, test_user):
    response = client.post(
        "/auth/login",
        json={"email": test_user.email, "password": "password123"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert "access_token" in payload
    assert payload["token_type"] == "bearer"


def test_login_invalid_credentials(client, test_user):
    response = client.post(
        "/auth/login",
        json={"email": test_user.email, "password": "wrong-password"},
    )

    assert response.status_code == 401


def test_me_requires_auth(client):
    response = client.get("/auth/me")
    assert response.status_code == 401


def test_me_success(client, auth_headers):
    response = client.get("/auth/me", headers=auth_headers)

    assert response.status_code == 200
    payload = response.json()
    assert payload["email"] == "staff@example.com"
    assert payload["role"] == "staff"


def test_temporary_password_user_cannot_access_dashboard(client, test_user, db_session):
    test_user.must_change_password = True
    db_session.commit()
    response = client.post(
        "/auth/login",
        json={"email": test_user.email, "password": "password123"},
    )
    headers = {"Authorization": f"Bearer {response.json()['access_token']}"}
    assert client.get("/auth/me", headers=headers).status_code == 200
    assert client.get("/fleet", headers=headers).status_code == 403
