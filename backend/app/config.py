import os
from dataclasses import dataclass
from functools import lru_cache


def _parse_bool(value: str, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _parse_cors_origins(value: str | None) -> list[str]:
    if value is None:
        return ["*"]
    value = value.strip()
    if not value:
        return []
    if value == "*":
        return ["*"]
    return [origin.strip() for origin in value.split(",") if origin.strip()]


@dataclass(frozen=True)
class Settings:
    app_name: str
    debug: bool
    database_url: str
    jwt_secret_key: str
    jwt_algorithm: str
    access_token_expire_minutes: int
    cors_origins: list[str]


@lru_cache
def get_settings() -> Settings:
    return Settings(
        app_name=os.getenv("APP_NAME", "AquaLogic API"),
        debug=_parse_bool(os.getenv("DEBUG"), default=False),
        database_url=os.getenv("DATABASE_URL", "sqlite:///./aqualogic.db"),
        jwt_secret_key=os.getenv("JWT_SECRET_KEY", "change-this-secret"),
        jwt_algorithm=os.getenv("JWT_ALGORITHM", "HS256"),
        access_token_expire_minutes=int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "60")),
        cors_origins=_parse_cors_origins(os.getenv("CORS_ORIGINS")),
    )


settings = get_settings()
