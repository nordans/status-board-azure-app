import argparse
import json
import re
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, build_opener

from scripts.render_aks import PUBLIC_HOST_PATTERN


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def fetch(url: str) -> tuple[int, dict, bytes]:
    opener = build_opener(NoRedirect())
    try:
        response = opener.open(url, timeout=15)
    except HTTPError as error:
        response = error
    with response:
        return response.status, dict(response.headers), response.read()


def verify(hostname: str, expected_version: str) -> None:
    if not re.fullmatch(PUBLIC_HOST_PATTERN, hostname):
        raise ValueError("Expected an Azure regional cloudapp.azure.com hostname")
    if not re.fullmatch(r"[0-9a-f]{40}", expected_version):
        raise ValueError("Expected a full commit SHA")
    code, headers, _ = fetch(f"http://{hostname}/api/status")
    headers = {key.lower(): value for key, value in headers.items()}
    if code != 301 or headers.get("location") not in {
        f"https://{hostname}/api/status",
        f"https://{hostname}:443/api/status",
    }:
        raise RuntimeError("HTTP must redirect to HTTPS on the same hostname and path")
    for path in ("/", "/health/ready", "/api/status"):
        code, headers, body = fetch(f"https://{hostname}{path}")
        if code != 200:
            raise RuntimeError(f"Public HTTPS check failed: {path} ({code})")
        headers = {key.lower(): value for key, value in headers.items()}
        if headers.get("strict-transport-security") != "max-age=86400":
            raise RuntimeError("Missing expected Strict-Transport-Security header")
        if path == "/api/status" and json.loads(body).get("version") != expected_version:
            raise RuntimeError("Public endpoint is not serving the deployed commit")
    for path in ("/metrics", "/metrics/"):
        code, _, _ = fetch(f"https://{hostname}{path}")
        if code != 404:
            raise RuntimeError("Metrics must not be exposed by the public Gateway")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hostname", required=True)
    parser.add_argument("--expected-version", required=True)
    arguments = parser.parse_args()
    verify(arguments.hostname, arguments.expected_version)
    print(
        "Public checks passed: trusted HTTPS, HTTP redirect, HSTS, readiness and deployed commit."
    )


if __name__ == "__main__":
    main()
