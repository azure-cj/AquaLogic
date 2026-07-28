import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from .database import get_db
from .models import AuthSession, User
from .security import decode_access_token, utc_now


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def _credentials_exception() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    try:
        payload = decode_access_token(token)
        user_id = int(payload["sub"])
        session_id = str(payload["sid"])
        token_version = int(payload["ver"])
    except (jwt.InvalidTokenError, KeyError, TypeError, ValueError):
        raise _credentials_exception()

    user = db.scalar(select(User).where(User.id == user_id))
    session = db.scalar(select(AuthSession).where(AuthSession.id == session_id, AuthSession.user_id == user_id))
    if (
        user is None
        or not user.is_active
        or user.token_version != token_version
        or session is None
        or session.revoked_at is not None
        or (session.expires_at if session.expires_at.tzinfo else session.expires_at.replace(tzinfo=utc_now().tzinfo)) <= utc_now()
    ):
        raise _credentials_exception()
    return user


def require_password_change_complete(current_user: User = Depends(get_current_user)) -> User:
    if current_user.must_change_password:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Password change is required")
    return current_user


def require_staff(current_user: User = Depends(require_password_change_complete)) -> User:
    if current_user.role not in {"staff", "admin"}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Staff access is required")
    return current_user


def require_admin(current_user: User = Depends(require_password_change_complete)) -> User:
    if current_user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access is required")
    return current_user
