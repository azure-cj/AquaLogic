import json
import uuid
from datetime import timedelta

from fastapi import HTTPException, Request, Response, status
from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from app.config import settings
from app.models import AccountSetupToken, AuthSession, AuthThrottle, RefreshToken, SecurityAuditEvent, User
from app.security import anonymized_value, create_access_token, hash_opaque_token, opaque_token, utc_now


REFRESH_COOKIE = "aqualogic_refresh"
REFRESH_GRACE_SECONDS = 5
THROTTLE_WINDOW = timedelta(minutes=15)


def _aware(value):
    return value if value.tzinfo else value.replace(tzinfo=utc_now().tzinfo)


def request_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def request_user_agent(request: Request) -> str:
    return request.headers.get("user-agent", "")[:256]


def audit_event(
    db: Session,
    request: Request | None,
    event_type: str,
    outcome: str,
    *,
    actor_user_id: int | None = None,
    target_type: str | None = None,
    target_id: str | int | None = None,
    details: dict | None = None,
) -> None:
    now = utc_now()
    if request:
        ip_hash = anonymized_value(request_ip(request))
        user_agent = request_user_agent(request)
        request_id = getattr(request.state, "request_id", None)
    else:
        ip_hash = user_agent = request_id = None
    db.add(
        SecurityAuditEvent(
            event_type=event_type,
            outcome=outcome,
            request_id=request_id,
            actor_user_id=actor_user_id,
            target_type=target_type,
            target_id=str(target_id) if target_id is not None else None,
            client_ip_hash=ip_hash,
            user_agent=user_agent,
            details=json.dumps(details, separators=(",", ":")) if details else None,
        )
    )
    db.execute(delete(SecurityAuditEvent).where(SecurityAuditEvent.created_at < now - timedelta(days=180)))


def set_refresh_cookie(response: Response, raw_token: str) -> None:
    response.set_cookie(
        REFRESH_COOKIE,
        raw_token,
        max_age=settings.refresh_session_expire_days * 86_400,
        httponly=True,
        secure=settings.refresh_cookie_secure,
        samesite="strict",
        path="/auth",
    )


def clear_refresh_cookie(response: Response) -> None:
    response.delete_cookie(REFRESH_COOKIE, path="/auth", httponly=True, secure=settings.refresh_cookie_secure, samesite="strict")


def create_session(db: Session, user: User, request: Request, *, amr: str = "pwd") -> tuple[str, str, object]:
    now = utc_now()
    session = AuthSession(
        id=str(uuid.uuid4()),
        user_id=user.id,
        expires_at=now + timedelta(days=settings.refresh_session_expire_days),
        client_ip_hash=anonymized_value(request_ip(request)),
        user_agent=request_user_agent(request),
        amr=amr,
        last_seen_at=now,
    )
    raw_refresh = opaque_token()
    db.add(session)
    db.add(RefreshToken(token_hash=hash_opaque_token(raw_refresh), session=session, expires_at=session.expires_at))
    token, expires_at = create_access_token(user_id=user.id, session_id=session.id, token_version=user.token_version, amr=amr)
    return token, raw_refresh, expires_at


def revoke_session(session: AuthSession, reason: str) -> None:
    if session.revoked_at is None:
        session.revoked_at = utc_now()
        session.revoke_reason = reason


def revoke_all_sessions(db: Session, user: User, reason: str) -> None:
    for session in db.scalars(select(AuthSession).where(AuthSession.user_id == user.id, AuthSession.revoked_at.is_(None))).all():
        revoke_session(session, reason)


def rotate_refresh_token(db: Session, raw_token: str) -> tuple[User, AuthSession, str | None, object]:
    now = utc_now()
    row = db.scalar(
        select(RefreshToken)
        .where(RefreshToken.token_hash == hash_opaque_token(raw_token))
        .with_for_update()
    )
    if row is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh session is invalid")
    session = row.session
    user = session.user
    if session.revoked_at or _aware(session.expires_at) <= now or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh session is no longer active")
    if _aware(row.expires_at) <= now:
        revoke_session(session, "refresh_expired")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh session expired")
    if row.consumed_at:
        consumed_at = _aware(row.consumed_at)
        if (now - consumed_at).total_seconds() > REFRESH_GRACE_SECONDS:
            revoke_session(session, "refresh_replay")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token replay detected")
        access, expires_at = create_access_token(user_id=user.id, session_id=session.id, token_version=user.token_version, amr=session.amr)
        return user, session, None, (access, expires_at)
    row.consumed_at = now
    next_raw = opaque_token()
    next_hash = hash_opaque_token(next_raw)
    row.replaced_by_hash = next_hash
    db.add(RefreshToken(token_hash=next_hash, session=session, expires_at=session.expires_at))
    session.last_seen_at = now
    access, expires_at = create_access_token(user_id=user.id, session_id=session.id, token_version=user.token_version, amr=session.amr)
    return user, session, next_raw, (access, expires_at)


def issue_setup_url(db: Session, user: User, purpose: str) -> tuple[str, object]:
    now = utc_now()
    db.execute(
        update(AccountSetupToken)
        .where(AccountSetupToken.user_id == user.id, AccountSetupToken.consumed_at.is_(None))
        .values(consumed_at=now)
    )
    raw_token = opaque_token()
    expires_at = now + timedelta(minutes=30)
    db.add(AccountSetupToken(token_hash=hash_opaque_token(raw_token), user_id=user.id, purpose=purpose, expires_at=expires_at))
    return f"{settings.public_base_url}/admin/setup-password#token={raw_token}", expires_at


def consume_setup_token(db: Session, raw_token: str) -> AccountSetupToken:
    item = db.scalar(
        select(AccountSetupToken)
        .where(AccountSetupToken.token_hash == hash_opaque_token(raw_token))
        .with_for_update()
    )
    if item is None or item.consumed_at is not None or _aware(item.expires_at) <= utc_now():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This setup link is invalid or expired")
    item.consumed_at = utc_now()
    return item


def _throttle(db: Session, scope: str, key: str, now):
    hashed = anonymized_value(key)
    item = db.scalar(
        select(AuthThrottle)
        .where(AuthThrottle.scope == scope, AuthThrottle.key_hash == hashed)
        .with_for_update()
    )
    if item and item.blocked_until and _aware(item.blocked_until) > now:
        seconds = max(1, int((_aware(item.blocked_until) - now).total_seconds()))
        raise HTTPException(status_code=429, detail="Too many login attempts", headers={"Retry-After": str(seconds)})
    return item, hashed


def check_login_throttles(db: Session, normalized_email: str, ip: str) -> None:
    now = utc_now()
    _throttle(db, "account", normalized_email, now)
    _throttle(db, "ip", ip, now)


def record_login_failure(db: Session, normalized_email: str, ip: str) -> bool:
    now = utc_now()
    blocked = False
    for scope, key, limit in (("account", normalized_email, 5), ("ip", ip, 20)):
        item, hashed = _throttle(db, scope, key, now)
        if item is None:
            item = AuthThrottle(scope=scope, key_hash=hashed, failures=0, window_started_at=now)
            db.add(item)
        if now - _aware(item.window_started_at) >= THROTTLE_WINDOW:
            item.failures = 0
            item.window_started_at = now
            item.blocked_until = None
        item.failures += 1
        if item.failures >= limit:
            item.blocked_until = now + THROTTLE_WINDOW
            blocked = True
    return blocked


def clear_login_throttles(db: Session, normalized_email: str, ip: str) -> None:
    for scope, key in (("account", normalized_email), ("ip", ip)):
        db.execute(delete(AuthThrottle).where(AuthThrottle.scope == scope, AuthThrottle.key_hash == anonymized_value(key)))
