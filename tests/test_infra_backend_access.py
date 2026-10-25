import json
import subprocess

import pytest

from scripts import infra_backend_access as backend


def account_config(ip_rules=None):
    return json.dumps(
        {
            "publicNetworkAccess": "Enabled",
            "networkRuleSet": {"defaultAction": "Deny", "ipRules": ip_rules or []},
        }
    )


def test_temporary_rule_is_recorded_and_removed(tmp_path, monkeypatch):
    calls = []
    state = tmp_path / "access.json"

    def az(*arguments):
        calls.append(arguments)
        if "show" in arguments:
            return account_config()
        if "add" in arguments:
            assert json.loads(state.read_text())["added"]
        return '{"exists": true}'

    monkeypatch.setattr(backend, "run_az", az)
    backend.open_access(state, "rg-state", "stateaccount", "tfstate", "8.8.8.8")
    backend.close_access(state, "rg-state", "stateaccount")
    assert any("add" in arguments for arguments in calls)
    assert any("remove" in arguments for arguments in calls)
    assert not state.exists()


def test_permanent_allowlist_is_preserved(tmp_path, monkeypatch):
    calls = []

    def az(*arguments):
        calls.append(arguments)
        if "show" in arguments:
            return account_config([{"ipAddressOrRange": "8.8.8.0/24", "action": "Allow"}])
        return '{"exists": true}'

    monkeypatch.setattr(backend, "run_az", az)
    state = tmp_path / "access.json"
    backend.open_access(state, "rg-state", "stateaccount", "tfstate", "8.8.8.8")
    backend.close_access(state, "rg-state", "stateaccount")
    assert not any("add" in arguments or "remove" in arguments for arguments in calls)


def test_cleanup_remains_possible_when_open_fails(tmp_path, monkeypatch):
    calls = []

    def az(*arguments):
        calls.append(arguments)
        if "show" in arguments:
            return account_config()
        if "add" in arguments:
            raise subprocess.CalledProcessError(1, "az")
        return ""

    monkeypatch.setattr(backend, "run_az", az)
    state = tmp_path / "access.json"
    with pytest.raises(subprocess.CalledProcessError):
        backend.open_access(state, "rg-state", "stateaccount", "tfstate", "8.8.8.8")
    backend.close_access(state, "rg-state", "stateaccount")
    assert any("remove" in arguments for arguments in calls)


@pytest.mark.parametrize("address", ["127.0.0.1", "10.0.0.1", "::1", "not-an-address"])
def test_nonpublic_addresses_are_rejected(address):
    with pytest.raises(ValueError):
        backend.public_ipv4(address)


def test_cleanup_does_not_touch_an_unrelated_account(tmp_path):
    state = tmp_path / "access.json"
    state.write_text(json.dumps({"account": "other", "resource_group": "rg-other"}))
    with pytest.raises(RuntimeError, match="does not match"):
        backend.close_access(state, "rg-state", "stateaccount")
    assert state.exists()


def test_cleanup_without_a_record_is_safe(tmp_path):
    backend.close_access(tmp_path / "missing.json", "rg-state", "stateaccount")
