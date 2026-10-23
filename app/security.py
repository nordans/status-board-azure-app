import re
import secrets
from pathlib import Path

from fastapi import HTTPException, status


class TokenUnavailable(RuntimeError):
    pass


def read_token(path: Path) -> bytes:
    try:
        with path.open("rb") as token_file:
            raw = token_file.read(1025)
    except OSError:
        raise TokenUnavailable("Admin token file is unavailable") from None
    token = raw.strip()
    if len(raw) > 1024 or not re.fullmatch(rb"[A-Za-z0-9_-]{32,512}", token):
        raise TokenUnavailable("Admin token must be 32-512 URL-safe characters")
    return token


def verify_token(path: Path, supplied: str | None) -> None:
    try:
        expected = read_token(path)
    except TokenUnavailable:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, "Admin authentication unavailable"
        ) from None
    if supplied is None or not secrets.compare_digest(supplied.encode("utf-8"), expected):
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "Invalid or missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )
