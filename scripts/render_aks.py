import argparse
import json
import re
import subprocess
from pathlib import Path

PUBLIC_HOST_PATTERN = r"[a-z][a-z0-9-]{1,61}[a-z0-9]\.[a-z0-9]+\.cloudapp\.azure\.com"


def render(target: str, kubectl: str, **values: str) -> str:
    patterns = {
        "APP_CLIENT_ID": r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}",
        "TENANT_ID": r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}",
        "KEY_VAULT_NAME": r"[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]",
        "IMAGE_REPOSITORY": r"[a-z0-9]+\.azurecr\.io/status-board",
        "IMAGE_DIGEST": r"sha256:[0-9a-f]{64}",
        "APP_VERSION": r"[0-9a-f]{40}",
        "PUBLIC_DNS_LABEL": r"[a-z][a-z0-9-]{1,61}[a-z0-9]",
        "PUBLIC_HOSTNAME": PUBLIC_HOST_PATTERN,
        "ACME_ENVIRONMENT": r"staging|production",
    }
    targets = {
        "bootstrap": ("k8s/bootstrap/aks", {"APP_CLIENT_ID", "TENANT_ID", "KEY_VAULT_NAME"}),
        "application": ("k8s/overlays/aks", {"IMAGE_REPOSITORY", "IMAGE_DIGEST", "APP_VERSION"}),
        "public": (
            "k8s/bootstrap/public",
            {"PUBLIC_DNS_LABEL", "PUBLIC_HOSTNAME", "ACME_ENVIRONMENT"},
        ),
    }
    source_path, required = targets[target]
    for key in sorted(required):
        if not re.fullmatch(patterns[key], values.get(key, "")):
            raise ValueError(f"Invalid or missing {key}")
    if target == "public":
        if values["PUBLIC_HOSTNAME"].split(".")[0] != values["PUBLIC_DNS_LABEL"]:
            raise ValueError("PUBLIC_HOSTNAME must use PUBLIC_DNS_LABEL")
        server = (
            "https://acme-staging-v02.api.letsencrypt.org/directory"
            if values["ACME_ENVIRONMENT"] == "staging"
            else "https://acme-v02.api.letsencrypt.org/directory"
        )
        values["ACME_SERVER"] = server
        required = required | {"ACME_SERVER"}
    root = Path(__file__).resolve().parents[1]
    source = root / source_path
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
    parser.add_argument("target", choices=["bootstrap", "application", "public"])
    parser.add_argument("--kubectl", default="kubectl")
    parser.add_argument("--output", type=Path, required=True)
    for option in (
        "app-client-id",
        "tenant-id",
        "key-vault-name",
        "image-repository",
        "image-digest",
        "app-version",
        "public-dns-label",
        "public-hostname",
    ):
        parser.add_argument(f"--{option}", default="")
    parser.add_argument("--acme-environment", choices=["staging", "production"], default="staging")
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
