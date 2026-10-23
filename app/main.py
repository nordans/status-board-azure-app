import json
import logging
import os
import socket
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles

from app.config import Settings, load_services
from app.security import TokenUnavailable, read_token, verify_token
from app.store import BoardSnapshot, BoardStore, Service, StatusUpdate, utc_now

logger = logging.getLogger("status_board")
STATIC = Path(__file__).resolve().parent / "static"
bearer = HTTPBearer(auto_error=False)


class BoardResponse(BoardSnapshot):
    title: str
    version: str
    environment: str
    instance: str
    uptime_seconds: int
    generated_at: str


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        level = os.getenv("LOG_LEVEL", "INFO").upper()
        logging.basicConfig(level=level, format="%(message)s")
        read_token(settings.token_file)
        application.state.store = BoardStore(load_services(settings.services_file))
        application.state.started = time.monotonic()
        logger.info(json.dumps({"event": "application_started", "version": settings.version}))
        yield
        logger.info(json.dumps({"event": "application_stopped"}))

    application = FastAPI(
        title="Status Board API",
        version=settings.version,
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
    )

    @application.middleware("http")
    async def request_metadata(request: Request, call_next):
        started = time.perf_counter()
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; script-src 'self'; style-src 'self'; "
            "img-src 'self'; connect-src 'self'; object-src 'none'; "
            "base-uri 'none'; frame-ancestors 'none'; form-action 'self'"
        )
        response.headers["Cache-Control"] = "no-store"
        route = request.scope.get("route")
        route_path = getattr(route, "path", "unmatched")
        logger.info(
            json.dumps(
                {
                    "event": "http_request",
                    "method": request.method,
                    "route": route_path,
                    "status": response.status_code,
                    "duration_ms": round((time.perf_counter() - started) * 1000, 2),
                }
            )
        )
        return response

    def require_admin(
        credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    ) -> None:
        verify_token(settings.token_file, credentials.credentials if credentials else None)

    @application.get("/health/live", tags=["health"])
    def live() -> dict[str, str]:
        return {"status": "alive"}

    @application.get("/health/ready", tags=["health"])
    def ready():
        try:
            read_token(settings.token_file)
        except TokenUnavailable:
            return JSONResponse({"status": "not_ready"}, status_code=503)
        return {"status": "ready"}

    @application.get("/api/status", response_model=BoardResponse, tags=["status"])
    def board(request: Request) -> BoardResponse:
        snapshot = request.app.state.store.snapshot()
        return BoardResponse(
            **snapshot.model_dump(),
            title=settings.title,
            version=settings.version,
            environment=settings.environment,
            instance=socket.gethostname(),
            uptime_seconds=int(time.monotonic() - request.app.state.started),
            generated_at=utc_now().isoformat(),
        )

    @application.put(
        "/api/services/{service_id}/status",
        response_model=Service,
        dependencies=[Depends(require_admin)],
        tags=["status"],
    )
    def update_status(service_id: str, update: StatusUpdate, request: Request) -> Service:
        try:
            return request.app.state.store.update(service_id, update)
        except KeyError:
            raise HTTPException(404, "Service not found") from None

    @application.get("/", include_in_schema=False)
    def index() -> FileResponse:
        return FileResponse(STATIC / "index.html")

    application.mount("/static", StaticFiles(directory=STATIC), name="static")
    return application


app = create_app()
