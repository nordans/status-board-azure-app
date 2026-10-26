import argparse
import json
import re
import shutil
import subprocess
import time
from urllib.error import HTTPError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen


def az_json(*arguments):
    executable = shutil.which("az")
    if executable is None:
        raise RuntimeError("Azure CLI is required")
    result = subprocess.run(
        [executable, *arguments, "--output", "json", "--only-show-errors"],
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    return json.loads(result.stdout)


def fetch_json(url, token, body=None):
    headers = {"Authorization": f"Bearer {token}"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = Request(
        url, data=None if body is None else json.dumps(body).encode(), headers=headers
    )
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def verify(query_endpoint, workspace_resource_id, expected_version, timeout=900):
    endpoint = urlparse(query_endpoint)
    if (
        endpoint.scheme != "https"
        or not endpoint.hostname
        or not endpoint.hostname.endswith(".prometheus.monitor.azure.com")
        or endpoint.username
        or endpoint.password
        or endpoint.port
        or endpoint.path not in {"", "/"}
        or endpoint.query
        or endpoint.fragment
    ):
        raise ValueError("Expected an Azure managed Prometheus query endpoint")
    if not re.fullmatch(
        r"/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[\w.-]+/providers/"
        r"Microsoft.OperationalInsights/workspaces/[\w-]+",
        workspace_resource_id,
    ):
        raise ValueError("Expected a Log Analytics workspace resource ID")
    if not re.fullmatch(r"[0-9a-f]{40}", expected_version):
        raise ValueError("Expected a full commit SHA")
    workspace = az_json(
        "rest",
        "--method",
        "get",
        "--url",
        f"https://management.azure.com{workspace_resource_id}?api-version=2023-09-01",
    )["properties"]["customerId"]
    metrics_token = az_json(
        "account", "get-access-token", "--resource", "https://prometheus.monitor.azure.com"
    )["accessToken"]
    logs_token = az_json(
        "account", "get-access-token", "--resource", "https://api.loganalytics.io"
    )["accessToken"]
    expressions = {
        "application metrics": 'up{job="status-board"} == 1 and (time() - timestamp(up{job="status-board"}) < 120)',
        "readiness metric": 'status_board_ready{job="status-board"} == 1 and (time() - timestamp(status_board_ready{job="status-board"}) < 120)',
        "Kubernetes metrics": 'kube_node_status_condition{condition="Ready",status="true"} == 1 and (time() - timestamp(kube_node_status_condition{condition="Ready",status="true"}) < 120)',
    }
    pending = set(expressions) | {"application logs"}
    deadline = time.monotonic() + timeout
    while pending and time.monotonic() < deadline:
        for name in list(pending):
            try:
                if name == "application logs":
                    result = fetch_json(
                        f"https://api.loganalytics.azure.com/v1/workspaces/{workspace}/query",
                        logs_token,
                        {
                            "query": "ContainerLogV2 | where TimeGenerated > ago(30m) "
                            '| where PodNamespace == "status-board" '
                            "| extend entry=parse_json(LogMessage) "
                            f'| where tostring(entry.version) == "{expected_version}" '
                            '| where tostring(entry.event) == "application_started" | count'
                        },
                    )
                    ready = result["tables"][0]["rows"][0][0] > 0
                else:
                    result = fetch_json(
                        query_endpoint.rstrip("/")
                        + "/api/v1/query?"
                        + urlencode({"query": expressions[name]}),
                        metrics_token,
                    )
                    ready = result["status"] == "success" and bool(result["data"]["result"])
                if ready:
                    pending.remove(name)
                    print(f"Verified {name}", flush=True)
            except HTTPError as error:
                if error.code not in {400, 404, 429, 500, 502, 503, 504}:
                    raise
        if pending:
            time.sleep(15)
    if pending:
        raise RuntimeError("Missing telemetry: " + ", ".join(sorted(pending)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--query-endpoint", required=True)
    parser.add_argument("--workspace-resource-id", required=True)
    parser.add_argument("--expected-version", required=True)
    arguments = parser.parse_args()
    verify(arguments.query_endpoint, arguments.workspace_resource_id, arguments.expected_version)


if __name__ == "__main__":
    main()
