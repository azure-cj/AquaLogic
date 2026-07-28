import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import Response
from starlette.middleware.trustedhost import TrustedHostMiddleware

from .config import settings
from .database import Base, engine
from .routes import alerts, auth, dashboard, fish, management, public, security, sensors, species_suitability, tanks
from .services.decision_engine import ensure_default_thresholds
from .services.demo_sensor import start_demo_generator

# Ensure all SQLAlchemy models are registered before metadata is used.
from . import models  # noqa: F401


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Production schema ownership belongs to Alembic. This local convenience is opt-in only.
    if not settings.is_production:
        Base.metadata.create_all(bind=engine)
        from .database import SessionLocal

        db = SessionLocal()
        try:
            ensure_default_thresholds(db)
        finally:
            db.close()
    start_demo_generator()
    yield


app = FastAPI(title=settings.app_name, debug=settings.debug, lifespan=lifespan)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.trusted_hosts)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
)


def _content_security_policy() -> str:
    image_sources = ["'self'", "data:", *[f"https://{host}" for host in sorted(settings.public_image_hosts)]]
    return "; ".join(
        (
            "default-src 'self'",
            "base-uri 'none'",
            "object-src 'none'",
            "frame-ancestors 'none'",
            "script-src 'self'",
            "connect-src 'self'",
            "font-src 'self'",
            f"img-src {' '.join(image_sources)}",
            "style-src-elem 'self'",
            "style-src-attr 'unsafe-inline'",
        )
    )


def _apply_security_headers(request: Request, response: Response) -> Response:
    response.headers["X-Request-ID"] = request.state.request_id
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
    response.headers["Content-Security-Policy"] = _content_security_policy()
    if settings.is_production:
        response.headers["Strict-Transport-Security"] = "max-age=31536000"
    if request.url.path.startswith("/auth/") or request.headers.get("authorization"):
        response.headers["Cache-Control"] = "no-store"
    return response


@app.middleware("http")
async def security_headers_and_body_limit(request: Request, call_next):
    request.state.request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))[:64]
    content_length = request.headers.get("content-length")
    try:
        declared_size = int(content_length) if content_length else 0
    except ValueError:
        return _apply_security_headers(request, JSONResponse(status_code=400, content={"detail": "Invalid Content-Length"}))
    if declared_size > 64 * 1024:
        return _apply_security_headers(request, JSONResponse(status_code=413, content={"detail": "Request body is too large"}))
    if request.method in {"POST", "PUT", "PATCH", "DELETE"}:
        body = await request.body()
        if len(body) > 64 * 1024:
            return _apply_security_headers(request, JSONResponse(status_code=413, content={"detail": "Request body is too large"}))
    response = await call_next(request)
    return _apply_security_headers(request, response)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(auth.router)
app.include_router(tanks.router)
app.include_router(species_suitability.router)
app.include_router(fish.router)
app.include_router(sensors.router)
app.include_router(alerts.router)
app.include_router(public.router)
app.include_router(management.router)
app.include_router(dashboard.router)
app.include_router(security.router)
