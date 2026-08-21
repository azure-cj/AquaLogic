from datetime import timedelta
from urllib.parse import quote

from app.models import AuthSession, SecurityAuditEvent, User
from app.security import decode_access_token, get_password_hash, utc_now


def _login_headers(client, email: str, password: str = "password123"):
    response = client.post("/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['access_token']}"}, response


def test_administrator_user_summaries_include_derived_lifecycle_metadata(client, auth_headers, db_session, test_user):
    now = utc_now()
    active = User(
        name="Active Operator",
        email="active-operator@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
    )
    setup_required = User(
        name="Pending Operator",
        email="pending-operator@example.com",
        hashed_password=get_password_hash("temporary-password"),
        role="staff",
        must_change_password=True,
    )
    inactive = User(
        name="Inactive Operator",
        email="inactive-operator@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
        is_active=False,
    )
    db_session.add_all([active, setup_required, inactive])
    db_session.flush()
    db_session.add(
        AuthSession(
            id="lifecycle-active-session",
            user_id=active.id,
            expires_at=now + timedelta(days=1),
            last_seen_at=now - timedelta(minutes=10),
            user_agent="Lifecycle browser",
        )
    )
    db_session.add(
        SecurityAuditEvent(
            event_type="lifecycle.check",
            outcome="success",
            actor_user_id=active.id,
            target_type="user",
            target_id=str(active.id),
            created_at=now - timedelta(minutes=2),
        )
    )
    db_session.commit()

    response = client.get("/users", headers=auth_headers)
    assert response.status_code == 200
    by_email = {item["email"]: item for item in response.json()}

    assert by_email[active.email]["account_status"] == "active"
    assert by_email[active.email]["active_session_count"] == 1
    assert by_email[active.email]["last_activity_at"] is not None
    assert by_email[active.email]["password_changed_at"] is None
    assert by_email[setup_required.email]["account_status"] == "setup_required"
    assert by_email[inactive.email]["account_status"] == "inactive"
    assert by_email[test_user.email]["account_status"] == "active"


def test_admin_can_inspect_and_revoke_another_users_sessions_but_not_own(client, auth_headers, db_session, test_user):
    target = User(
        name="Session Target",
        email="session-target@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
    )
    staff = User(
        name="Session Staff",
        email="session-staff@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
    )
    db_session.add_all([target, staff])
    db_session.commit()

    target_headers, target_login = _login_headers(client, target.email)
    staff_headers, _ = _login_headers(client, staff.email)
    target_session_id = decode_access_token(target_login.json()["access_token"])["sid"]

    listed = client.get(f"/users/{target.id}/sessions", headers=auth_headers)
    assert listed.status_code == 200
    assert listed.json()[0]["id"] == target_session_id
    assert "client_ip_hash" not in listed.json()[0]
    assert "token_hash" not in listed.json()[0]

    assert client.get(f"/users/{target.id}", headers=staff_headers).status_code == 403
    assert client.get(f"/users/{target.id}/sessions", headers=staff_headers).status_code == 403
    assert client.post(f"/users/{target.id}/revoke-sessions", headers=staff_headers).status_code == 403
    assert client.post(f"/users/{test_user.id}/revoke-sessions", headers=auth_headers).status_code == 409

    revoked = client.post(f"/users/{target.id}/revoke-sessions", headers=auth_headers)
    assert revoked.status_code == 200
    assert revoked.json() == {"revoked_count": 1}
    assert client.get("/auth/me", headers=target_headers).status_code == 401
    assert client.post("/auth/refresh", headers={"Cookie": target_login.headers["set-cookie"].split(";", 1)[0]}).status_code == 401
    assert client.get(f"/users/{target.id}/sessions", headers=auth_headers).json() == []


def test_audit_filters_match_actor_or_target_and_return_no_sensitive_fields(client, auth_headers, db_session, test_user):
    target = User(
        name="Audit Target",
        email="audit-target@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
    )
    db_session.add(target)
    db_session.flush()
    now = utc_now()
    actor_event = SecurityAuditEvent(
        event_type="audit.filtered",
        outcome="failure",
        actor_user_id=target.id,
        target_type="tank",
        target_id="44",
        client_ip_hash="should-not-appear",
        details='{"refresh_token":"should-not-appear"}',
        created_at=now - timedelta(hours=2),
    )
    target_event = SecurityAuditEvent(
        event_type="audit.filtered",
        outcome="failure",
        actor_user_id=test_user.id,
        target_type="user",
        target_id=str(target.id),
        created_at=now - timedelta(hours=1),
    )
    unrelated = SecurityAuditEvent(
        event_type="audit.filtered",
        outcome="success",
        actor_user_id=test_user.id,
        target_type="user",
        target_id=str(test_user.id),
        created_at=now,
    )
    db_session.add_all([actor_event, target_event, unrelated])
    db_session.commit()

    filtered = client.get(
        f"/security/audit-events?user_id={target.id}&event_type=audit.filtered&outcome=failure"
        f"&since={quote((now - timedelta(hours=3)).isoformat())}&until={quote((now - timedelta(minutes=30)).isoformat())}",
        headers=auth_headers,
    )
    assert filtered.status_code == 200
    assert {item["id"] for item in filtered.json()} == {actor_event.id, target_event.id}
    assert all("client_ip_hash" not in item and "details" not in item for item in filtered.json())

    targeted_only = client.get(
        f"/security/audit-events?user_id={target.id}&event_type=audit.filtered&outcome=success",
        headers=auth_headers,
    )
    assert targeted_only.status_code == 200
    assert targeted_only.json() == []


def test_deactivation_does_not_allow_old_sessions_to_return_after_reactivation(client, auth_headers, db_session):
    target = User(
        name="Deactivate Target",
        email="deactivate-target@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
    )
    db_session.add(target)
    db_session.commit()

    target_headers, target_login = _login_headers(client, target.email)
    refresh_cookie = {"Cookie": target_login.headers["set-cookie"].split(";", 1)[0]}
    deactivated = client.put(f"/users/{target.id}", headers=auth_headers, json={"is_active": False})
    assert deactivated.status_code == 200
    assert client.get("/auth/me", headers=target_headers).status_code == 401
    assert client.post("/auth/refresh", headers=refresh_cookie).status_code == 401

    target.is_active = True
    db_session.commit()
    assert client.get("/auth/me", headers=target_headers).status_code == 401
    assert client.post("/auth/refresh", headers=refresh_cookie).status_code == 401
