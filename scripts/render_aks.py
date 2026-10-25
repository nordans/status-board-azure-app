import argparse
import json
import re
import subprocess
from pathlib import Path


def render(target: str, kubectl: str, **values: str) -> str:
    patterns = {
        "APP_CLIENT_ID": r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}",
        "TENANT_ID": r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}",
        "KEY_VAULT_NAME": r"[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]",
        "IMAGE_REPOSITORY": r"[a-z0-9]+\.azurecr\.io/status-board",
        "IMAGE_DIGEST": r"sha256:[0-9a-f]{64}",
        "APP_VERSION": r"[0-9a-f]{40}",
    }
    required = (
        {"APP_CLIENT_ID", "TENANT_ID", "KEY_VAULT_NAME"}
        if target == "bootstrap"
        else {"IMAGE_REPOSITORY", "IMAGE_DIGEST", "APP_VERSION"}
    )
    for key in sorted(required):
        if not re.fullmatch(patterns[key], values.get(key, "")):
            raise ValueError(f"Invalid or missing {key}")
    root = Path(__file__).resolve().parents[1]
    source = root / ("k8s/bootstrap/aks" if target == "bootstrap" else "k8s/overlays/aks")
    result = subprocess.run(
        [kubectl, "kustomize", str(source)],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout
    for key in required:
        value = json.dumps(values[key]) if key == "APP_VERSION" else values[key]
        result = result.replace(f"__{key}__", value)
    if re.search(r"__[A-Z_]+__", result):
        raise RuntimeError("Rendered manifests contain unresolved placeholders")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", choices=["bootstrap", "application"])
    parser.add_argument("--kubectl", default="kubectl")
    parser.add_argument("--output", type=Path, required=True)
    for option in (
        "app-client-id",
        "tenant-id",
        "key-vault-name",
        "image-repository",
        "image-digest",
        "app-version",
    ):
        parser.add_argument(f"--{option}", default="")
    arguments = parser.parse_args()
    values = {
        key.upper(): value
        for key, value in vars(arguments).items()
        if key not in {"target", "kubectl", "output"}
    }
    arguments.output.write_text(
        render(arguments.target, arguments.kubectl, **values), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
