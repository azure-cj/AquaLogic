import secrets
from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_admin, require_password_change_complete
from app.models import Customer, Tank, User
from app.schemas.customer import CustomerCreate, CustomerRead, CustomerUpdate
from app.schemas.user import UserCreate, UserRead, UserUpdate
from app.security import get_password_hash

router = APIRouter(tags=["management"])


@router.get("/customers", response_model=list[CustomerRead])
def customers(db: Session = Depends(get_db), _: User = Depends(require_password_change_complete)):
    return list(db.scalars(select(Customer).order_by(Customer.name)).all())


@router.post("/customers", response_model=CustomerRead, status_code=201)
def create_customer(payload: CustomerCreate, db: Session = Depends(get_db), _: User = Depends(require_password_change_complete)):
    customer = Customer(**payload.dict()); db.add(customer); db.commit(); db.refresh(customer); return customer


@router.put("/customers/{customer_id}", response_model=CustomerRead)
def update_customer(customer_id: int, payload: CustomerUpdate, db: Session = Depends(get_db), _: User = Depends(require_password_change_complete)):
    customer = db.get(Customer, customer_id)
    if not customer: raise HTTPException(404, "Customer not found")
    for key, value in payload.dict(exclude_unset=True).items(): setattr(customer, key, value)
    db.commit(); db.refresh(customer); return customer


@router.delete("/customers/{customer_id}", status_code=204)
def delete_customer(customer_id: int, db: Session = Depends(get_db), _: User = Depends(require_password_change_complete)):
    customer = db.get(Customer, customer_id)
    if not customer: raise HTTPException(404, "Customer not found")
    if db.scalar(select(Tank).where(Tank.customer_id == customer_id)):
        raise HTTPException(409, "Reassign this customer's tanks before deletion")
    db.delete(customer); db.commit(); return Response(status_code=204)


@router.get("/users", response_model=list[UserRead])
def users(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    return list(db.scalars(select(User).order_by(User.name)).all())


@router.post("/users", status_code=201)
def create_user(payload: UserCreate, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    if payload.role not in {"admin", "staff"}: raise HTTPException(422, "Invalid role")
    if db.scalar(select(User).where(User.email == payload.email)): raise HTTPException(409, "Email already exists")
    temporary_password = secrets.token_urlsafe(18)[:16]
    user = User(name=payload.name, email=payload.email, role=payload.role, hashed_password=get_password_hash(temporary_password), must_change_password=True)
    db.add(user); db.commit(); db.refresh(user)
    return {"user": UserRead.from_orm(user), "temporary_password": temporary_password}


@router.put("/users/{user_id}", response_model=UserRead)
def update_user(user_id: int, payload: UserUpdate, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    user = db.get(User, user_id)
    if not user: raise HTTPException(404, "User not found")
    values = payload.dict(exclude_unset=True)
    if "role" in values and values["role"] not in {"admin", "staff"}: raise HTTPException(422, "Invalid role")
    for key, value in values.items(): setattr(user, key, value)
    db.commit(); db.refresh(user); return user


@router.post("/users/{user_id}/reset-password")
def reset_password(user_id: int, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    user = db.get(User, user_id)
    if not user: raise HTTPException(404, "User not found")
    temporary_password = secrets.token_urlsafe(18)[:16]
    user.hashed_password, user.must_change_password = get_password_hash(temporary_password), True
    db.commit(); return {"temporary_password": temporary_password}
