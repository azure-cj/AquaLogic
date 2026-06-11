from sqlalchemy import select

from app.database import Base, SessionLocal, engine
from app.models import User
from app.security import get_password_hash
from seed.seed_fish import seed_fish_species
from seed.seed_tanks import seed_tanks

DEFAULT_ADMIN = {
    "name": "AquaLogic Staff Admin",
    "email": "admin@aqualogic.local",
    "password": "admin123",
    "role": "admin",
}


def seed_admin_user(db) -> bool:
    existing = db.scalar(select(User).where(User.email == DEFAULT_ADMIN["email"]))
    if existing:
        return False

    user = User(
        name=DEFAULT_ADMIN["name"],
        email=DEFAULT_ADMIN["email"],
        hashed_password=get_password_hash(DEFAULT_ADMIN["password"]),
        role=DEFAULT_ADMIN["role"],
    )
    db.add(user)
    return True


def run_seed() -> None:
    Base.metadata.create_all(bind=engine)

    with SessionLocal() as db:
        created_tanks = seed_tanks(db)
        created_fish = seed_fish_species(db)
        created_admin = seed_admin_user(db)
        db.commit()

    print("Seed complete")
    print(f"- Tanks created: {created_tanks}")
    print(f"- Fish species created: {created_fish}")
    print(f"- Admin user created: {created_admin}")
    print(f"- Admin login email: {DEFAULT_ADMIN['email']}")
    if created_admin:
        print(f"- Admin temporary password: {DEFAULT_ADMIN['password']}")


if __name__ == "__main__":
    run_seed()
