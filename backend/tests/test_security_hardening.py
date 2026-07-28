from datetime import timedelta

from app.models import AuthSession, RefreshToken, User
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
