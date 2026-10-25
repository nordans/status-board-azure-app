import argparse
import hashlib
import re
import subprocess
import tempfile
import time
from pathlib import Path

from scripts.infra_backend_access import run_az


def download_plan(account: str, container: str, name: str, destination: Path, sha256: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise ValueError("A lowercase SHA256 digest of the reviewed plan is required")
    if destination.exists():
        raise FileExistsError("The plan destination must not already exist")
    deadline = time.monotonic() + 300
    with tempfile.TemporaryDirectory(prefix="reviewed-plan-", dir=destination.parent) as directory:
        temporary = Path(directory) / "plan.tfplan"
        while True:
            try:
                run_az(
                    "storage",
                    "blob",
                    "download",
                    "--auth-mode",
                    "login",
                    "--account-name",
                    account,
                    "--container-name",
                    container,
                    "--name",
                    name,
                    "--file",
                    str(temporary),
                    "--overwrite",
                    "true",
                    "-o",
                    "none",
                )
                break
            except subprocess.CalledProcessError as error:
                temporary.unlink(missing_ok=True)
                detail = error.stderr or "Azure CLI returned no error details"
                message = detail.lower()
                permanent = any(
                    code in message
                    for code in (
                        "authorizationpermissionmismatch",
                        "authenticationfailed",
                        "blobnotfound",
                        "containernotfound",
                    )
                )
                network_denial = (
                    "authorizationfailure" in message
                    or "request may be blocked by network rules" in message
                )
                if permanent or not network_denial:
                    raise RuntimeError(f"Plan download failed: {detail}") from None
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise RuntimeError(
                        f"Plan download access remained denied for five minutes: {detail}"
                    ) from None
                print(
                    "Storage denied plan download; retrying within the five-minute window",
                    flush=True,
                )
                time.sleep(min(5, remaining))
        with temporary.open("rb") as plan:
            actual_sha = hashlib.file_digest(plan, "sha256").hexdigest()
        if actual_sha != sha256:
            raise RuntimeError("Downloaded plan SHA256 does not match the reviewed plan")
        temporary.replace(destination)
    print("Reviewed plan downloaded and SHA256 verified", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--account", required=True)
    parser.add_argument("--container", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    arguments = parser.parse_args()
    download_plan(
        arguments.account,
        arguments.container,
        arguments.name,
        arguments.destination,
        arguments.sha256,
    )


if __name__ == "__main__":
    main()
