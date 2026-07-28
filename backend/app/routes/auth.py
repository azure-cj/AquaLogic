from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, oauth2_scheme
from app.models import AuthSession, User
from app.schemas.auth import (
    ChangePasswordRequest,
    LoginRequest,
    LogoutAllRequest,
    SessionRead,
    SetupPasswordRequest,
    Token,
)
from app.schemas.user import UserRead
from app.security import (
    decode_access_token,
    get_password_hash,
    normalize_email,
    password_needs_rehash,
    utc_now,
    verify_password,
)
from app.services.auth_security import (
    REFRESH_COOKIE,
    audit_event,
    check_login_throttles,
    clear_login_throttles,
    clear_refresh_cookie,
    consume_setup_token,
    create_session,
    request_ip,
    record_login_failure,
    revoke_all_sessions,
    revoke_session,
    rotate_refresh_token,
    set_refresh_cookie,
)


router = APIRouter(prefix="/auth", tags=["auth"])
DUMMY_PASSWORD_HASH = get_password_hash("aqualogic-dummy-password")


def _token_response(user: User, access_token: str, expires_at) -> Token:
    return Token(
        access_token=access_token,
        expires_at=expires_at,
        user=UserRead.model_validate(user),
        must_change_password=user.must_change_password,
    )


def _current_session(token: str, user: User, db: Session) -> AuthSession:
    try:
        session_id = str(decode_access_token(token)["sid"])
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Could not validate credentials")
    session = db.scalar(select(AuthSession).where(AuthSession.id == session_id, AuthSession.user_id == user.id))
    if session is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Could not validate credentials")
    return session


@router.post("/login", response_model=Token)
def login(payload: LoginRequest, response: Response, request: Request, db: Session = Depends(get_db)) -> Token:
    email = normalize_email(str(payload.email))
    ip = request_ip(request)
    try:
        check_login_throttles(db, email, ip)
    except HTTPException:
        audit_event(db, request, "login.throttled", "blocked", target_type="account")
        db.commit()
        raise

    user = db.scalar(select(User).where(User.email == email))
    verified = verify_password(payload.password, user.hashed_password if user else DUMMY_PASSWORD_HASH)
    if user is None or not user.is_active or not verified:
        throttled = record_login_failure(db, email, ip)
        audit_event(db, request, "login", "failure", target_type="account")
        db.commit()
        if throttled:
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Too many login attempts", headers={"Retry-After": "900"})
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")

    if password_needs_rehash(user.hashed_password):
        user.hashed_password = get_password_hash(payload.password)
    clear_login_throttles(db, email, ip)
    access_token, raw_refresh, expires_at = create_session(db, user, request)
    audit_event(db, request, "login", "success", actor_user_id=user.id, target_type="session")
    db.commit()
    set_refresh_cookie(response, raw_refresh)
    return _token_response(user, access_token, expires_at)


@router.post("/refresh", response_model=Token)
def refresh(response: Response, request: Request, db: Session = Depends(get_db)) -> Token | JSONResponse:
    raw_refresh = request.cookies.get(REFRESH_COOKIE)
    if not raw_refresh:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh session is required")
    try:
        user, session, replacement, token_data = rotate_refresh_token(db, raw_refresh)
    except HTTPException as error:
        audit_event(db, request, "refresh", "failure", target_type="session")
        db.commit()
        error_response = JSONResponse(status_code=error.status_code, content={"detail": error.detail}, headers=error.headers)
        clear_refresh_cookie(error_response)
        return error_response
    access_token, expires_at = token_data
    audit_event(db, request, "refresh", "success", actor_user_id=user.id, target_type="session", target_id=session.id)
    db.commit()
    if replacement:
        set_refresh_cookie(response, replacement)
    return _token_response(user, access_token, expires_at)


@router.post("/logout")
def logout(
    response: Response,
    request: Request,
    token: str = Depends(oauth2_scheme),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict[str, str]:
    session = _current_session(token, current_user, db)
    revoke_session(session, "logout")
    audit_event(db, request, "logout", "success", actor_user_id=current_user.id, target_type="session", target_id=session.id)
    db.commit()
    clear_refresh_cookie(response)
    return {"message": "Logged out successfully"}


@router.post("/logout-all")
def logout_all(
    payload: LogoutAllRequest,
    response: Response,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict[str, str]:
    if not verify_password(payload.current_password, current_user.hashed_password):
        audit_event(db, request, "logout_all", "failure", actor_user_id=current_user.id)
        db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Current password is incorrect")
    current_user.token_version += 1
    revoke_all_sessions(db, current_user, "logout_all")
    audit_event(db, request, "logout_all", "success", actor_user_id=current_user.id)
    db.commit()
    clear_refresh_cookie(response)
    return {"message": "Signed out on every device"}


@router.get("/me", response_model=UserRead)
def me(current_user: User = Depends(get_current_user)) -> User:
    return current_user


@router.post("/change-password", response_model=Token)
def change_password(
    payload: ChangePasswordRequest,
    response: Response,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Token:
    if not verify_password(payload.current_password, current_user.hashed_password):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Current password is incorrect")
    if verify_password(payload.new_password, current_user.hashed_password):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Choose a password you have not used for this account")
    current_user.hashed_password = get_password_hash(payload.new_password)
    current_user.must_change_password = False
    current_user.password_changed_at = utc_now()
    current_user.token_version += 1
    revoke_all_sessions(db, current_user, "password_changed")
    access_token, raw_refresh, expires_at = create_session(db, current_user, request)
    audit_event(db, request, "password.change", "success", actor_user_id=current_user.id)
    db.commit()
    set_refresh_cookie(response, raw_refresh)
    return _token_response(current_user, access_token, expires_at)


@router.post("/setup-password", response_model=Token)
def setup_password(payload: SetupPasswordRequest, response: Response, request: Request, db: Session = Depends(get_db)) -> Token:
    setup = consume_setup_token(db, payload.token)
    user = db.get(User, setup.user_id)
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This setup link is invalid or expired")
    if verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Choose a password you have not used for this account")
    user.hashed_password = get_password_hash(payload.password)
    user.must_change_password = False
    user.password_changed_at = utc_now()
    user.token_version += 1
    revoke_all_sessions(db, user, "password_setup")
    access_token, raw_refresh, expires_at = create_session(db, user, request)
    audit_event(db, request, "password.setup", "success", actor_user_id=user.id)
    db.commit()
    set_refresh_cookie(response, raw_refresh)
    return _token_response(user, access_token, expires_at)


@router.get("/sessions", response_model=list[SessionRead])
def sessions(token: str = Depends(oauth2_scheme), current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> list[SessionRead]:
    current = _current_session(token, current_user, db)
    return [
        SessionRead(
            id=item.id,
            created_at=item.created_at,
            last_seen_at=item.last_seen_at,
            expires_at=item.expires_at,
            current=item.id == current.id,
            user_agent=item.user_agent,
        )
        for item in db.scalars(
            select(AuthSession).where(AuthSession.user_id == current_user.id, AuthSession.revoked_at.is_(None)).order_by(AuthSession.created_at.desc())
        ).all()
    ]


@router.delete("/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_individual_session(
    session_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Response:
    session = db.scalar(select(AuthSession).where(AuthSession.id == session_id, AuthSession.user_id == current_user.id))
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    revoke_session(session, "user_revoked")
    audit_event(db, request, "session.revoke", "success", actor_user_id=current_user.id, target_type="session", target_id=session.id)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
