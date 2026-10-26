from urllib.error import HTTPError

import pytest

from scripts import verify_azure_monitoring as monitoring

ENDPOINT = "https://example.northeurope.prometheus.monitor.azure.com"
WORKSPACE = (
    "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/"
    "providers/Microsoft.OperationalInsights/workspaces/law-statusboard-dev"
)
VERSION = "a" * 40


@pytest.mark.parametrize(
    "endpoint",
    [
        "http://example.northeurope.prometheus.monitor.azure.com",
        "https://attacker.example",
        ENDPOINT + ".attacker.example",
        "https://user:password@example.prometheus.monitor.azure.com",
        ENDPOINT + "/redirect",
        ENDPOINT + "?query=redirect",
    ],
)
def test_cloud_probe_rejects_destinations_before_requesting_credentials(monkeypatch, endpoint):
    def unexpected(*args):
        pytest.fail("Credentials must not be requested for an invalid endpoint")

    monkeypatch.setattr(monitoring, "az_json", unexpected)
    with pytest.raises(ValueError):
        monitoring.verify(endpoint, WORKSPACE, VERSION)


def test_missing_telemetry_does_not_pass_and_authorization_errors_are_not_hidden(monkeypatch):
    def az_json(*args):
        if args[0] == "rest":
            return {"properties": {"customerId": "workspace-guid"}}
        return {"accessToken": "test-token"}

    monkeypatch.setattr(monitoring, "az_json", az_json)
    with pytest.raises(RuntimeError, match="Missing telemetry"):
        monitoring.verify(ENDPOINT, WORKSPACE, VERSION, timeout=0)

    def forbidden(*args):
        raise HTTPError(ENDPOINT, 403, "Forbidden", {}, None)

    monkeypatch.setattr(monitoring, "fetch_json", forbidden)
    with pytest.raises(HTTPError) as error:
        monitoring.verify(ENDPOINT, WORKSPACE, VERSION)
    assert error.value.code == 403
