import argparse
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def request(base_url: str, path: str, token: str | None = None, body: dict | None = None):
    headers = {}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    http_request = Request(
        f"{base_url}{path}",
        data=data,
        headers=headers,
        method="PUT" if body is not None else "GET",
    )
    try:
        with urlopen(http_request, timeout=5) as response:
            return response.status, json.load(response)
    except HTTPError as error:
        with error:
            return error.code, json.load(error)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--token-file", type=Path, default=Path(".secrets/admin_api_token"))
    args = parser.parse_args()
    token = args.token_file.read_text(encoding="ascii").strip()

    for endpoint in ("/health/live", "/health/ready"):
        status, _ = request(args.base_url, endpoint)
        require(status == 200, f"Health check failed: {endpoint}")

    status, board = request(args.base_url, "/api/status")
    require(status == 200 and bool(board["services"]), "Public status API unavailable")
    service_id = board["services"][0]["id"]
    endpoint = f"/api/services/{service_id}/status"
    payload = {"status": "operational", "message": "Container smoke test passed."}

    status, _ = request(args.base_url, endpoint, body=payload)
    require(status == 401, "Unauthenticated status update was not rejected")
    status, report = request(args.base_url, endpoint, token=token, body=payload)
    require(status == 200 and report["status"] == "operational", "Authenticated update failed")
    status, board = request(args.base_url, "/api/status")
    require(
        status == 200 and board["services"][0]["message"] == payload["message"],
        "Published report is missing from the public API",
    )
    print("Container smoke tests passed: health, public read, denied write, authenticated write.")


if __name__ == "__main__":
    main()
