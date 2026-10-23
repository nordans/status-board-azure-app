from collections import deque
from datetime import datetime, timezone
from enum import Enum
from threading import Lock

from pydantic import BaseModel, ConfigDict, Field

from app.config import ServiceConfig


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class ServiceStatus(str, Enum):
    operational = "operational"
    degraded = "degraded"
    outage = "outage"
    maintenance = "maintenance"
    unknown = "unknown"


class StatusUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    status: ServiceStatus
    message: str = Field(default="", max_length=240)
    response_time_ms: int | None = Field(default=None, ge=0, le=600_000, strict=True)


class Service(BaseModel):
    id: str
    name: str
    description: str
    status: ServiceStatus = ServiceStatus.unknown
    message: str = "Awaiting first report"
    response_time_ms: int | None = None
    updated_at: datetime | None = None


class Event(BaseModel):
    id: int
    service_id: str
    service_name: str
    status: ServiceStatus
    message: str
    created_at: datetime


class BoardSnapshot(BaseModel):
    services: list[Service]
    events: list[Event]


class BoardStore:
    def __init__(self, configs: list[ServiceConfig]) -> None:
        self._lock = Lock()
        self._services = {
            item.id: Service(id=item.id, name=item.name, description=item.description)
            for item in configs
        }
        self._events: deque[Event] = deque(maxlen=50)
        self._revision = 0

    def snapshot(self) -> BoardSnapshot:
        with self._lock:
            return BoardSnapshot(
                services=[item.model_copy() for item in self._services.values()],
                events=list(self._events),
            )

    def update(self, service_id: str, update: StatusUpdate) -> Service:
        with self._lock:
            current = self._services[service_id]
            now = utc_now()
            updated = current.model_copy(update={**update.model_dump(), "updated_at": now})
            self._services[service_id] = updated
            self._revision += 1
            self._events.appendleft(
                Event(
                    id=self._revision,
                    service_id=service_id,
                    service_name=current.name,
                    status=update.status,
                    message=update.message,
                    created_at=now,
                )
            )
            return updated.model_copy()
