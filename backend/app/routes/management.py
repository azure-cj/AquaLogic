from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_admin, require_staff
from app.models import AuthSession, Customer, SecurityAuditEvent, Tank, User
from app.schemas.auth import AdminSessionRead, RevokeSessionsResponse, SetupLinkResponse
from app.schemas.customer import CustomerCreate, CustomerRead, CustomerUpdate
from app.schemas.user import AdminUserRead, UserCreate, UserRead, UserUpdate
from app.security import get_password_hash, normalize_email, opaque_token, utc_now
from app.services.auth_security import audit_event, issue_setup_url, revoke_all_sessions


router = APIRouter(tags=["management"])


def _aware(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def _latest(*values: datetime | None) -> datetime | None:
    present = [_aware(value) for value in values if value is not None]
    return max(present) if present else None


def _admin_user_read(db: Session, user: User) -> AdminUserRead:
    now = utc_now()
    active_session_count = db.scalar(
        select(func.count())
        .select_from(AuthSession)
        .where(
            AuthSession.user_id == user.id,
            AuthSession.revoked_at.is_(None),
            AuthSession.expires_at > now,
        )
    ) or 0
    latest_session_activity = db.scalar(
        select(func.max(AuthSession.last_seen_at)).where(AuthSession.user_id == user.id)
    )
    latest_audit_activity = db.scalar(
        select(func.max(SecurityAuditEvent.created_at)).where(
            or_(
                SecurityAuditEvent.actor_user_id == user.id,
                and_(
                    SecurityAuditEvent.target_type == "user",
                    SecurityAuditEvent.target_id == str(user.id),
                ),
            )
        )
    )
    if not user.is_active:
        account_status = "inactive"
    elif user.must_change_password:
        account_status = "setup_required"
    else:
        account_status = "active"
    return AdminUserRead(
        id=user.id,
        name=user.name,
        email=user.email,
        role=user.role,
        is_active=user.is_active,
        must_change_password=user.must_change_password,
        created_at=user.created_at,
        account_status=account_status,
        password_changed_at=user.password_changed_at,
        active_session_count=int(active_session_count),
        last_activity_at=_latest(latest_session_activity, latest_audit_activity),
    )


@router.get("/customers", response_model=list[CustomerRead])
def customers(db: Session = Depends(get_db), _: User = Depends(require_staff)):
    return list(db.scalars(select(Customer).order_by(Customer.name)).all())


@router.post("/customers", response_model=CustomerRead, status_code=201)
def create_customer(payload: CustomerCreate, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    customer = Customer(**payload.model_dump())
    db.add(customer)
    audit_event(db, request, "customer.create", "success", actor_user_id=current_user.id, target_type="customer")
    db.commit()
    db.refresh(customer)
    return customer


@router.put("/customers/{customer_id}", response_model=CustomerRead)
def update_customer(customer_id: int, payload: CustomerUpdate, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    customer = db.get(Customer, customer_id)
    if not customer:
        raise HTTPException(404, "Customer not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(customer, key, value)
    audit_event(db, request, "customer.update", "success", actor_user_id=current_user.id, target_type="customer", target_id=customer.id)
    db.commit()
    db.refresh(customer)
    return customer


@router.delete("/customers/{customer_id}", status_code=204)
def delete_customer(customer_id: int, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    customer = db.get(Customer, customer_id)
    if not customer:
        raise HTTPException(404, "Customer not found")
    if db.scalar(select(Tank).where(Tank.customer_id == customer_id)):
        raise HTTPException(409, "Reassign this customer's tanks before deletion")
    audit_event(db, request, "customer.delete", "success", actor_user_id=current_user.id, target_type="customer", target_id=customer.id)
    db.delete(customer)
    db.commit()
    return Response(status_code=204)


@router.get("/users", response_model=list[AdminUserRead])
def users(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    return [_admin_user_read(db, user) for user in db.scalars(select(User).order_by(User.name)).all()]


@router.post("/users", response_model=SetupLinkResponse, status_code=201)
def create_user(payload: UserCreate, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    if payload.role not in {"admin", "staff"}:
        raise HTTPException(422, "Invalid role")
    email = normalize_email(str(payload.email))
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(409, "Email already exists")
    user = User(
        name=payload.name,
        email=email,
        role=payload.role,
        hashed_password=get_password_hash(opaque_token()),
        must_change_password=True,
    )
    db.add(user)
    db.flush()
    setup_url, expires_at = issue_setup_url(db, user, "invite")
    audit_event(db, request, "user.create", "success", actor_user_id=current_user.id, target_type="user", target_id=user.id)
    db.commit()
    db.refresh(user)
    return SetupLinkResponse(user=UserRead.model_validate(user), setup_url=setup_url, expires_at=expires_at)


@router.get("/users/{user_id}", response_model=AdminUserRead)
def get_user(user_id: int, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(404, "User not found")
    return _admin_user_read(db, user)


@router.get("/users/{user_id}/sessions", response_model=list[AdminSessionRead])
def get_user_sessions(user_id: int, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    if not db.get(User, user_id):
        raise HTTPException(404, "User not found")
    now = utc_now()
    sessions = db.scalars(
        select(AuthSession)
        .where(
            AuthSession.user_id == user_id,
            AuthSession.revoked_at.is_(None),
            AuthSession.expires_at > now,
        )
        .order_by(AuthSession.last_seen_at.desc(), AuthSession.created_at.desc())
    ).all()
    return [AdminSessionRead.model_validate(session) for session in sessions]


@router.post("/users/{user_id}/revoke-sessions", response_model=RevokeSessionsResponse)
def revoke_user_sessions(
    user_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(404, "User not found")
    if user.id == current_user.id:
        raise HTTPException(409, "Use Sign out everywhere from your own Security page")
    sessions = db.scalars(
        select(AuthSession).where(AuthSession.user_id == user.id, AuthSession.revoked_at.is_(None))
    ).all()
    for session in sessions:
        session.revoked_at = utc_now()
        session.revoke_reason = "admin_revoke_all"
    user.token_version += 1
    audit_event(
        db,
        request,
        "user.sessions_revoked",
        "success",
        actor_user_id=current_user.id,
        target_type="user",
        target_id=user.id,
        details={"revoked_count": len(sessions)},
    )
    db.commit()
    return RevokeSessionsResponse(revoked_count=len(sessions))


@router.put("/users/{user_id}", response_model=UserRead)
def update_user(user_id: int, payload: UserUpdate, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(404, "User not found")
    values = payload.model_dump(exclude_unset=True)
    if "role" in values and values["role"] not in {"admin", "staff"}:
        raise HTTPException(422, "Invalid role")
    if user.id == current_user.id and (values.get("role") == "staff" or values.get("is_active") is False):
        raise HTTPException(409, "You cannot demote or deactivate your own account")

    would_remove_admin = user.role == "admin" and user.is_active and (
        values.get("role") == "staff" or values.get("is_active") is False
    )
    if would_remove_admin:
        active_admins = list(
            db.scalars(select(User).where(User.role == "admin", User.is_active.is_(True)).with_for_update()).all()
        )
        if len(active_admins) <= 1:
            raise HTTPException(409, "At least one active administrator is required")
    was_active = user.is_active
    for key, value in values.items():
        setattr(user, key, value)
    if was_active and values.get("is_active") is False:
        user.token_version += 1
        revoke_all_sessions(db, user, "admin_deactivate")
    audit_event(db, request, "user.update", "success", actor_user_id=current_user.id, target_type="user", target_id=user.id)
    db.commit()
    db.refresh(user)
    return user


@router.post("/users/{user_id}/reset-password", response_model=SetupLinkResponse)
def reset_password(user_id: int, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(404, "User not found")
    user.hashed_password = get_password_hash(opaque_token())
    user.must_change_password = True
    user.password_changed_at = utc_now()
    user.token_version += 1
    revoke_all_sessions(db, user, "admin_reset")
    setup_url, expires_at = issue_setup_url(db, user, "reset")
    audit_event(db, request, "user.password_reset", "success", actor_user_id=current_user.id, target_type="user", target_id=user.id)
    db.commit()
    db.refresh(user)
    return SetupLinkResponse(user=UserRead.model_validate(user), setup_url=setup_url, expires_at=expires_at)
