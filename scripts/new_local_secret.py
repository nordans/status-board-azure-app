import os
import secrets
from pathlib import Path

secret_path = Path(__file__).resolve().parent.parent / ".secrets" / "admin_api_token"
secret_path.parent.mkdir(mode=0o700, exist_ok=True)
try:
    descriptor = os.open(secret_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
except FileExistsError:
    print("Local secret already exists; left unchanged.")
else:
    with os.fdopen(descriptor, "w", encoding="ascii") as token_file:
        token_file.write(secrets.token_urlsafe(32))
    print("Created .secrets/admin_api_token (ignored by Git and excluded from the image).")
