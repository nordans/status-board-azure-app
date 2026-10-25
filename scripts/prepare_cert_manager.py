import argparse
import hashlib
from pathlib import Path
from urllib.request import urlopen

VERSION = "v1.21.3"
MANIFEST_URL = (
    f"https://github.com/cert-manager/cert-manager/releases/download/{VERSION}/cert-manager.yaml"
)
MANIFEST_SHA256 = "c04a51295adda2b1a775146751f973e787190778c7f35180861d9678876e5c74"
KUSTOMIZATION = """apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cert-manager.yaml
patches:
  - target:
      group: apps
      version: v1
      kind: Deployment
      name: cert-manager
      namespace: cert-manager
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --enable-gateway-api
"""


def prepare(output: Path) -> None:
    with urlopen(MANIFEST_URL, timeout=60) as response:
        manifest = response.read()
    if hashlib.sha256(manifest).hexdigest() != MANIFEST_SHA256:
        raise RuntimeError("cert-manager manifest SHA-256 does not match the pinned release")
    output.mkdir(parents=True, exist_ok=True)
    (output / "cert-manager.yaml").write_bytes(manifest)
    (output / "kustomization.yaml").write_text(KUSTOMIZATION, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    arguments = parser.parse_args()
    prepare(arguments.output_dir)
    print(f"Prepared verified cert-manager {VERSION} manifests in {arguments.output_dir}")


if __name__ == "__main__":
    main()
