import logging
import secrets
import pytest
from fastapi.testclient import TestClient

from app.config import Settings, load_services
from app.main import create_app
from app.security import TokenUnavailable, verify_token


@pytest.fixture
def environment(tmp_path):
    token = secrets.token_urlsafe(32)
    token_file = tmp_path / "admin-token"
    token_file.write_text(token, encoding="ascii")
    settings = Settings(token_file=token_file, version="test-sha", environment="test")
    return settings, token


@pytest.fixture
def running(environment):
    settings, token = environment
    with TestClient(create_app(settings)) as client:
        yield client, settings, {"Authorization": f"Bearer {token}"}


def test_public_board_starts_unknown_and_exposes_no_secret(running, environment):
    client, _, _ = running
    response = client.get("/api/status")
    assert response.status_code == 200
    data = response.json()
    assert data["version"] == "test-sha"
    assert len(data["services"]) == 3
    assert all(item["status"] == "unknown" and item["updated_at"] is None for item in data["services"])
    assert data["events"] == []
    assert environment[1] not in response.text
    assert "token_file" not in response.text


@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer incorrect"}, {"Authorization": "Basic incorrect"}])
def test_writes_require_a_valid_bearer_token(running, headers):
    client, _, _ = running
    response = client.put("/api/services/public-api/status", json={"status": "outage"}, headers=headers)
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert client.get("/api/status").json()["events"] == []


def test_valid_update_changes_public_state_and_records_event(running):
    client, _, headers = running
    response = client.put("/api/services/public-api/status", headers=headers, json={
        "status": "degraded", "message": "Investigating elevated latency", "response_time_ms": 240,
    })
    assert response.status_code == 200
    snapshot = client.get("/api/status").json()
    assert snapshot["services"][0]["status"] == "degraded"
    assert snapshot["services"][0]["response_time_ms"] == 240
    assert snapshot["services"][0]["updated_at"] is not None
    assert snapshot["events"][0]["service_id"] == "public-api"
    assert snapshot["events"][0]["message"] == "Investigating elevated latency"


def test_atomic_token_rotation_rejects_old_and_accepts_new_token(running, tmp_path):
    client, settings, old_headers = running
    new_token = secrets.token_urlsafe(32)
    replacement = tmp_path / "new-token"
    replacement.write_text(new_token + "\n", encoding="ascii")
    replacement.replace(settings.token_file)
    endpoint = "/api/services/public-api/status"
    assert client.put(endpoint, headers=old_headers, json={"status": "operational"}).status_code == 401
    assert client.put(endpoint, headers={"Authorization": f"Bearer {new_token}"}, json={"status": "operational"}).status_code == 200


@pytest.mark.parametrize("file_state", ["missing", "empty", "invalid", "oversized"])
def test_unavailable_secret_fails_closed_but_process_remains_alive(running, file_state):
    client, settings, headers = running
    if file_state == "missing":
        settings.token_file.unlink()
    else:
        settings.token_file.write_text({"empty": "", "invalid": "short", "oversized": "x" * 1025}[file_state], encoding="ascii")
    assert client.get("/health/live").status_code == 200
    assert client.get("/health/ready").status_code == 503
    assert client.get("/api/status").status_code == 200
    response = client.put("/api/services/public-api/status", headers=headers, json={"status": "operational"})
    assert response.status_code == 503
    assert str(settings.token_file) not in response.text


@pytest.mark.parametrize("value", [None, "", "too-short", "a" * 1025])
def test_invalid_or_missing_initial_secret_prevents_startup(environment, value):
    settings, _ = environment
    if value is None:
        settings.token_file.unlink()
    else:
        settings.token_file.write_text(value, encoding="ascii")
    with pytest.raises(TokenUnavailable):
        with TestClient(create_app(settings)):
            pass


@pytest.mark.parametrize("payload", [
    {"status": "broken"},
    {"status": "operational", "response_time_ms": -1},
    {"status": "operational", "response_time_ms": 1.5},
    {"status": "operational", "response_time_ms": True},
    {"status": "operational", "message": "x" * 241},
    {"status": "operational", "unexpected": "field"},
])
def test_invalid_report_is_rejected_without_changing_state(running, payload):
    client, _, headers = running
    assert client.put("/api/services/public-api/status", headers=headers, json=payload).status_code == 422
    assert client.get("/api/status").json()["events"] == []


def test_unknown_component_returns_404(running):
    client, _, headers = running
    assert client.put("/api/services/does-not-exist/status", headers=headers, json={"status": "operational"}).status_code == 404


def test_event_history_is_bounded_and_newest_first(running):
    client, _, headers = running
    for index in range(55):
        client.put("/api/services/public-api/status", headers=headers, json={"status": "operational", "message": f"Report {index}"})
    events = client.get("/api/status").json()["events"]
    assert len(events) == 50
    assert events[0]["message"] == "Report 54"
    assert events[-1]["message"] == "Report 5"


def test_readiness_is_independent_of_reported_service_outages(running):
    client, _, headers = running
    client.put("/api/services/public-api/status", headers=headers, json={"status": "outage"})
    assert client.get("/health/ready").status_code == 200


def test_process_restart_resets_state(environment):
    settings, token = environment
    with TestClient(create_app(settings)) as client:
        client.put("/api/services/public-api/status", headers={"Authorization": f"Bearer {token}"}, json={"status": "outage"})
    with TestClient(create_app(settings)) as client:
        assert client.get("/api/status").json()["services"][0]["status"] == "unknown"


def test_requests_do_not_log_headers_body_or_query_values(running, caplog, environment):
    client, _, headers = running
    with caplog.at_level(logging.INFO, logger="status_board"):
        client.put("/api/services/public-api/status?do_not_log=query-marker", headers=headers, json={"status": "operational", "message": "body-marker"})
    application_logs = "\n".join(record.message for record in caplog.records if record.name == "status_board")
    assert "http_request" in application_logs
    assert environment[1] not in application_logs
    assert "body-marker" not in application_logs
    assert "query-marker" not in application_logs


def test_dashboard_and_assets_are_served_with_security_headers(running):
    client, _, _ = running
    for path in ["/", "/static/app.js", "/static/styles.css", "/static/favicon.svg"]:
        response = client.get(path)
        assert response.status_code == 200
        assert response.headers["x-content-type-options"] == "nosniff"
        assert "frame-ancestors 'none'" in response.headers["content-security-policy"]
    assert client.get("/api/status").headers["cache-control"] == "no-store"


def test_unicode_credentials_are_rejected_without_crashing(environment):
    settings, _ = environment
    from fastapi import HTTPException
    with pytest.raises(HTTPException) as error:
        verify_token(settings.token_file, "zażółć")
    assert error.value.status_code == 401


def test_duplicate_service_configuration_is_rejected(tmp_path):
    config_file = tmp_path / "services.json"
    config_file.write_text('[{"id":"api","name":"API","description":""},{"id":"api","name":"Again","description":""}]', encoding="utf-8")
    with pytest.raises(ValueError, match="unique"):
        load_services(config_file)


def test_openapi_marks_update_as_authenticated(running):
    client, _, _ = running
    document = client.get("/openapi.json").json()
    operation = document["paths"]["/api/services/{service_id}/status"]["put"]
    assert operation["security"] == [{"HTTPBearer": []}]
