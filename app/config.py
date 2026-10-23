import json
import os
import re
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class ServiceConfig:
    id: str
    name: str
    description: str


@dataclass(frozen=True)
class Settings:
    token_file: Path
    services_file: Path = ROOT / "config" / "services.json"
    title: str = "Platform Status"
    version: str = "dev"
    environment: str = "local"

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            token_file=Path(os.getenv("ADMIN_API_TOKEN_FILE", ".secrets/admin_api_token")),
            services_file=Path(os.getenv("SERVICES_FILE", str(ROOT / "config/services.json"))),
            title=os.getenv("BOARD_TITLE", "Platform Status"),
            version=os.getenv("APP_VERSION", "dev"),
            environment=os.getenv("APP_ENV", "local"),
        )


def load_services(path: Path) -> list[ServiceConfig]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list) or not 1 <= len(data) <= 100:
        raise ValueError("SERVICES_FILE must contain 1 to 100 services")
    services = []
    ids: set[str] = set()
    for item in data:
        if not isinstance(item, dict) or set(item) != {"id", "name", "description"}:
            raise ValueError("Each service needs id, name and description")
        if not all(isinstance(value, str) for value in item.values()):
            raise ValueError("Service fields must be strings")
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", item["id"]) or len(item["id"]) > 64:
            raise ValueError("Service ids must be lowercase slugs, at most 64 characters")
        if item["id"] in ids or not 1 <= len(item["name"].strip()) <= 80:
            raise ValueError("Service ids must be unique and names must be nonempty")
        if len(item["description"]) > 200:
            raise ValueError("Service descriptions must be at most 200 characters")
        ids.add(item["id"])
        services.append(ServiceConfig(**item))
    return services
