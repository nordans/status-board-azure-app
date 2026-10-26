import argparse
import json
import subprocess
import time
from pathlib import Path
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import urlopen


def get_json(url: str):
    with urlopen(url, timeout=10) as response:
        return json.load(response)


def wait_for(description, check, timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if check():
                print(description, flush=True)
                return
        except (URLError, ConnectionError, TimeoutError):
            pass
        time.sleep(3)
    raise RuntimeError(f"Timed out: {description}")


def query(expression):
    result = get_json("http://127.0.0.1:9090/api/v1/query?" + urlencode({"query": expression}))
    if result["status"] != "success":
        raise RuntimeError("Prometheus query failed")
    return result["data"]["result"]


def alert_firing():
    return bool(query('ALERTS{alertname="StatusBoardDown",alertstate="firing"}'))


def alert_received():
    return any(
        item["labels"].get("alertname") == "StatusBoardDown"
        for item in get_json("http://127.0.0.1:9093/api/v2/alerts")
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exercise-outage", action="store_true")
    parser.add_argument("--project", default="status-board-observability")
    arguments = parser.parse_args()
    wait_for("Application is being scraped", lambda: bool(query('up{job="status-board"} == 1')))
    wait_for("Readiness gauge is healthy", lambda: bool(query("status_board_ready == 1")))
    wait_for(
        "Grafana is healthy",
        lambda: get_json("http://127.0.0.1:3000/api/health")["database"] == "ok",
    )
    get_json("http://127.0.0.1:3000/api/dashboards/uid/status-board")
    print("Provisioned Grafana dashboard is available", flush=True)
    wait_for(
        "Grafana can query its Prometheus datasource",
        lambda: bool(
            get_json(
                "http://127.0.0.1:3000/api/datasources/proxy/uid/prometheus/api/v1/query?"
                + urlencode({"query": 'up{job="status-board"} == 1'})
            )["data"]["result"]
        ),
    )
    if not arguments.exercise_outage:
        return
    compose = [
        "docker",
        "compose",
        "-p",
        arguments.project,
        "-f",
        "compose.yaml",
        "-f",
        "compose.monitoring.yaml",
    ]
    root = Path(__file__).resolve().parents[1]
    try:
        subprocess.run([*compose, "stop", "--timeout", "10", "status-board"], cwd=root, check=True)
        wait_for("StatusBoardDown is firing", alert_firing, timeout=210)
        wait_for("Alertmanager received StatusBoardDown", alert_received)
    finally:
        subprocess.run([*compose, "start", "status-board"], cwd=root, check=True)
    wait_for("Application recovered", lambda: bool(query('up{job="status-board"} == 1')))
    wait_for("StatusBoardDown resolved in Prometheus", lambda: not alert_firing())
    wait_for("StatusBoardDown resolved in Alertmanager", lambda: not alert_received(), timeout=90)


if __name__ == "__main__":
    main()
