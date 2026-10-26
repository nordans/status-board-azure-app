import secrets

from fastapi.testclient import TestClient
from prometheus_client.parser import text_string_to_metric_families

from app.config import Settings
from app.main import create_app


def test_metrics_bound_labels_and_do_not_expose_request_data(tmp_path):
    token = secrets.token_urlsafe(32)
    token_file = tmp_path / "token"
    token_file.write_text(token)
    app = create_app(Settings(token_file=token_file))
    with TestClient(app) as client:
        for suffix in ("first", "second"):
            client.put(
                f"/api/services/{suffix}/status?private=query-value",
                json={"status": "outage", "message": "private-message"},
                headers={"Authorization": f"Bearer {token}"},
            )
            client.get(f"/unknown-{suffix}")
        result = client.get("/metrics")
        assert result.status_code == 200
        assert "text/plain" in result.headers["content-type"]
        for private in (
            token,
            "query-value",
            "private-message",
            "unknown-first",
            "/services/first",
        ):
            assert private not in result.text
        counter = next(
            item
            for item in text_string_to_metric_families(result.text)
            if item.name == "status_board_http_requests"
        )
        samples = [item for item in counter.samples if item.name.endswith("_total")]
        assert len(samples) == 2
        assert {item.labels["route"] for item in samples} == {
            "/api/services/{service_id}/status",
            "unmatched",
        }
        assert all(item.value == 2 for item in samples)
        assert "/metrics" not in result.text
        assert "status_board_ready 1.0" in result.text
        token_file.unlink()
        assert "status_board_ready 0.0" in client.get("/metrics").text


def test_unhandled_failure_is_counted_and_each_app_has_its_own_registry(tmp_path):
    token_file = tmp_path / "token"
    token_file.write_text(secrets.token_urlsafe(32))
    settings = Settings(token_file=token_file)
    first = create_app(settings)

    @first.get("/failure")
    def failure():
        raise RuntimeError("test failure")

    with TestClient(first, raise_server_exceptions=False) as client:
        assert client.get("/failure").status_code == 500
        assert 'route="/failure",status="500"} 1.0' in client.get("/metrics").text
    with TestClient(create_app(settings)) as client:
        assert "/failure" not in client.get("/metrics").text
