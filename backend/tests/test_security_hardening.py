from datetime import timedelta

from app.models import AccountSetupToken, AuthSession, RefreshToken, User
from app.security import decode_access_token, get_password_hash, utc_now


def _refresh_header(response):
    cookie = response.headers["set-cookie"].split(";", 1)[0]
    return {"Cookie": cookie}


def test_login_issues_claim_complete_access_token_and_http_only_refresh_cookie(client, test_user):
    response = client.post("/auth/login", json={"email": test_user.email, "password": "password123"})
    assert response.status_code == 200
    payload = response.json()
    claims = decode_access_token(payload["access_token"])
    assert {"sub", "sid", "ver", "iss", "aud", "iat", "exp", "jti", "amr"} <= claims.keys()
    assert "HttpOnly" in response.headers["set-cookie"]
    assert "SameSite=strict" in response.headers["set-cookie"]
    assert "Path=/" in response.headers["set-cookie"]
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert "object-src 'none'" in response.headers["content-security-policy"]
    assert payload["user"]["id"] == test_user.id


def test_refresh_rotates_once_then_revokes_a_replayed_session(client, test_user, db_session):
    login = client.post("/auth/login", json={"email": test_user.email, "password": "password123"})
    original_cookie = _refresh_header(login)
    rotated = client.post("/auth/refresh", headers=original_cookie)
    assert rotated.status_code == 200
    original_hash = next(
        row.token_hash
        for row in db_session.query(RefreshToken).all()
        if row.consumed_at is not None
    )
    token = db_session.get(RefreshToken, original_hash)
    token.consumed_at = utc_now() - timedelta(seconds=6)
    db_session.commit()

    replay = client.post("/auth/refresh", headers=original_cookie)
    assert replay.status_code == 401
    assert "aqualogic_refresh=\"\"" in replay.headers["set-cookie"]
    cleared_cookies = replay.headers.get_list("set-cookie")
    assert any("Path=/;" in cookie for cookie in cleared_cookies)
    assert any("Path=/auth;" in cookie for cookie in cleared_cookies)
    session = db_session.get(AuthSession, decode_access_token(login.json()["access_token"])["sid"])
    assert session.revoked_at is not None
    assert client.get("/auth/me", headers={"Authorization": f"Bearer {login.json()['access_token']}"}).status_code == 401


def test_staff_can_assign_fish_but_cannot_write_admin_resources(client, db_session):
    staff = User(name="Limited Staff", email="limited@example.com", hashed_password=get_password_hash("password123"), role="staff")
    db_session.add(staff)
    db_session.commit()
    login = client.post("/auth/login", json={"email": staff.email, "password": "password123"})
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    assert client.post("/tanks", headers=headers, json={"name": "Denied", "location": "Rack"}).status_code == 403
    assert client.post("/customers", headers=headers, json={"name": "Denied"}).status_code == 403
    assert client.get("/tanks", headers=headers).status_code == 200


def test_login_throttle_and_oversized_requests_are_rejected(client, test_user):
    for _ in range(5):
        response = client.post("/auth/login", json={"email": test_user.email, "password": "wrong-password"})
    assert response.status_code == 429
    assert response.headers["retry-after"] == "900"
    oversized = client.post("/auth/login", content=b"x" * (64 * 1024 + 1), headers={"content-type": "application/json"})
    assert oversized.status_code == 413
    assert oversized.headers["cache-control"] == "no-store"


def test_setup_link_is_single_use_and_replaces_the_account_password(client, auth_headers):
    created = client.post("/users", headers=auth_headers, json={"name": "Invite", "email": "invite@example.com", "role": "staff"})
    assert created.status_code == 201
    setup_token = created.json()["setup_url"].split("#token=", 1)[1]
    setup = client.post("/auth/setup-password", json={"token": setup_token, "password": "an entirely new password"})
    assert setup.status_code == 200
    assert client.post("/auth/setup-password", json={"token": setup_token, "password": "an entirely new password"}).status_code == 400
    assert client.post("/auth/login", json={"email": "invite@example.com", "password": "an entirely new password"}).status_code == 200


def test_replacing_a_setup_link_invalidates_the_previous_link(client, auth_headers):
    created = client.post(
        "/users",
        headers=auth_headers,
        json={"name": "Replaced Invite", "email": "replaced-invite@example.com", "role": "staff"},
    )
    assert created.status_code == 201
    first_token = created.json()["setup_url"].split("#token=", 1)[1]
    user_id = created.json()["user"]["id"]

    reset = client.post(f"/users/{user_id}/reset-password", headers=auth_headers)
    assert reset.status_code == 200
    second_token = reset.json()["setup_url"].split("#token=", 1)[1]

    assert client.post("/auth/setup-password", json={"token": first_token, "password": "a replaced secure password"}).status_code == 400
    assert client.post("/auth/setup-password", json={"token": second_token, "password": "a replaced secure password"}).status_code == 200


def test_password_change_invalidates_prior_access_and_refresh_sessions(client, test_user):
    login = client.post("/auth/login", json={"email": test_user.email, "password": "password123"})
    access_headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    refresh_headers = _refresh_header(login)

    changed = client.post(
        "/auth/change-password",
        headers=access_headers,
        json={"current_password": "password123", "new_password": "a brand new password"},
    )
    assert changed.status_code == 200
    assert client.get("/auth/me", headers=access_headers).status_code == 401
    assert client.post("/auth/refresh", headers=refresh_headers).status_code == 401
    assert client.get("/auth/me", headers={"Authorization": f"Bearer {changed.json()['access_token']}"}).status_code == 200


def test_logout_everywhere_invalidates_all_access_and_refresh_sessions(client, test_user):
    first_login = client.post("/auth/login", json={"email": test_user.email, "password": "password123"})
    second_login = client.post("/auth/login", json={"email": test_user.email, "password": "password123"})
    first_access = {"Authorization": f"Bearer {first_login.json()['access_token']}"}
    second_access = {"Authorization": f"Bearer {second_login.json()['access_token']}"}

    signed_out = client.post("/auth/logout-all", headers=first_access, json={"current_password": "password123"})
    assert signed_out.status_code == 200
    assert client.get("/auth/me", headers=first_access).status_code == 401
    assert client.get("/auth/me", headers=second_access).status_code == 401
    assert client.post("/auth/refresh", headers=_refresh_header(first_login)).status_code == 401
    assert client.post("/auth/refresh", headers=_refresh_header(second_login)).status_code == 401


def test_deactivation_invalidates_existing_access_and_refresh_sessions(client, test_user, db_session):
    login = client.post("/auth/login", json={"email": test_user.email, "password": "password123"})
    access_headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    refresh_headers = _refresh_header(login)

    test_user.is_active = False
    db_session.commit()

    assert client.get("/auth/me", headers=access_headers).status_code == 401
    assert client.post("/auth/refresh", headers=refresh_headers).status_code == 401


def test_role_change_takes_effect_for_existing_access_token(client, test_user, db_session):
    target = User(
        name="Role Change Target",
        email="role-target@example.com",
        hashed_password=get_password_hash("password123"),
        role="admin",
    )
    db_session.add(target)
    db_session.commit()
    target_login = client.post("/auth/login", json={"email": target.email, "password": "password123"})
    target_headers = {"Authorization": f"Bearer {target_login.json()['access_token']}"}
    admin_headers = {"Authorization": f"Bearer {client.post('/auth/login', json={'email': test_user.email, 'password': 'password123'}).json()['access_token']}"}

    changed = client.put(f"/users/{target.id}", headers=admin_headers, json={"role": "staff"})
    assert changed.status_code == 200
    assert client.get("/fleet", headers=target_headers).status_code == 200
    assert client.get("/users", headers=target_headers).status_code == 403


def test_last_active_admin_cannot_be_demoted_or_deactivated(client, auth_headers, test_user):
    assert client.put(f"/users/{test_user.id}", headers=auth_headers, json={"role": "staff"}).status_code == 409
    assert client.put(f"/users/{test_user.id}", headers=auth_headers, json={"is_active": False}).status_code == 409


def test_password_reset_invalidates_existing_access_and_refresh_sessions(client, test_user, db_session):
    target = User(
        name="Reset Target",
        email="reset-target@example.com",
        hashed_password=get_password_hash("old-password-123"),
        role="staff",
    )
    db_session.add(target)
    db_session.commit()
    target_login = client.post("/auth/login", json={"email": target.email, "password": "old-password-123"})
    target_headers = {"Authorization": f"Bearer {target_login.json()['access_token']}"}
    refresh_headers = _refresh_header(target_login)
    admin_login = client.post("/auth/login", json={"email": test_user.email, "password": "password123"})
    admin_headers = {"Authorization": f"Bearer {admin_login.json()['access_token']}"}

    reset = client.post(f"/users/{target.id}/reset-password", headers=admin_headers)
    assert reset.status_code == 200
    assert client.get("/auth/me", headers=target_headers).status_code == 401
    assert client.post("/auth/refresh", headers=refresh_headers).status_code == 401


def test_session_listing_and_revocation_are_owner_scoped(client, test_user, db_session):
    other = User(
        name="Other Session User",
        email="other-session@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
    )
    db_session.add(other)
    db_session.commit()
    owner_login = client.post("/auth/login", json={"email": test_user.email, "password": "password123"})
    other_login = client.post("/auth/login", json={"email": other.email, "password": "password123"})
    owner_headers = {"Authorization": f"Bearer {owner_login.json()['access_token']}"}
    other_session_id = decode_access_token(other_login.json()["access_token"])["sid"]

    sessions = client.get("/auth/sessions", headers=owner_headers)
    assert sessions.status_code == 200
    assert all(item["id"] != other_session_id for item in sessions.json())
    assert client.delete(f"/auth/sessions/{other_session_id}", headers=owner_headers).status_code == 404


def test_setup_link_expiry_is_enforced(client, auth_headers, db_session):
    created = client.post(
        "/users",
        headers=auth_headers,
        json={"name": "Expired Setup", "email": "expired-setup@example.com", "role": "staff"},
    )
    assert created.status_code == 201
    token = created.json()["setup_url"].split("#token=", 1)[1]
    setup = db_session.query(AccountSetupToken).one()
    setup.expires_at = utc_now() - timedelta(seconds=1)
    db_session.commit()

    expired = client.post("/auth/setup-password", json={"token": token, "password": "a sufficiently secure password"})
    assert expired.status_code == 400
