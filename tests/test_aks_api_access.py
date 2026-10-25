import json
import subprocess

import pytest

from scripts import aks_api_access as access


def config(ranges, state="Succeeded"):
    return {"provisioningState": state, "apiServerAccessProfile": {"authorizedIpRanges": ranges}}


def test_cleanup_removes_only_own_rule_and_preserves_concurrent_changes(tmp_path, monkeypatch):
    record = tmp_path / "access.json"
    configs = iter(
        [
            config(["1.1.1.1/32"]),
            config(["1.1.1.1/32", "8.8.8.8/32", "9.9.9.9/32"]),
        ]
    )
    updates = []
    monkeypatch.setattr(access, "cluster_config", lambda *_: next(configs))

    def update(group, cluster, ranges):
        assert record.exists()
        updates.append(ranges)

    monkeypatch.setattr(access, "update_ranges", update)
    access.open_access(record, "rg", "aks", "8.8.8.8")
    access.close_access(record, "rg", "aks")
    assert updates == [["1.1.1.1/32", "8.8.8.8/32"], ["1.1.1.1/32", "9.9.9.9/32"]]
    assert not record.exists()


def test_existing_allowlist_range_is_never_removed(tmp_path, monkeypatch):
    monkeypatch.setattr(access, "cluster_config", lambda *_: config(["8.8.8.0/24"]))
    updates = []
    monkeypatch.setattr(access, "update_ranges", lambda *args: updates.append(args))
    record = tmp_path / "access.json"
    access.open_access(record, "rg", "aks", "8.8.8.8")
    access.close_access(record, "rg", "aks")
    assert not updates
    assert not record.exists()


def test_failed_open_leaves_cleanup_record(tmp_path, monkeypatch):
    monkeypatch.setattr(access, "cluster_config", lambda *_: config(["1.1.1.1/32"]))

    def fail(*_):
        raise subprocess.CalledProcessError(1, "az")

    monkeypatch.setattr(access, "update_ranges", fail)
    record = tmp_path / "access.json"
    with pytest.raises(subprocess.CalledProcessError):
        access.open_access(record, "rg", "aks", "8.8.8.8")
    assert json.loads(record.read_text())["added"]
    access.close_access(record, "rg", "aks")
    assert not record.exists()


@pytest.mark.parametrize("ranges", [[], ["0.0.0.0/0"]])
def test_unrestricted_api_is_rejected(tmp_path, monkeypatch, ranges):
    monkeypatch.setattr(access, "cluster_config", lambda *_: config(ranges))
    with pytest.raises(RuntimeError, match="restricted API"):
        access.open_access(tmp_path / "access.json", "rg", "aks", "8.8.8.8")


def test_wrong_cleanup_target_is_rejected(tmp_path):
    record = tmp_path / "access.json"
    record.write_text(json.dumps({"group": "other", "cluster": "aks"}))
    with pytest.raises(RuntimeError, match="does not match"):
        access.close_access(record, "rg", "aks")
    assert record.exists()


def test_cleanup_never_empties_allowlist(tmp_path, monkeypatch):
    record = tmp_path / "access.json"
    record.write_text(
        json.dumps({"group": "rg", "cluster": "aks", "cidr": "8.8.8.8/32", "added": True})
    )
    monkeypatch.setattr(access, "cluster_config", lambda *_: config(["8.8.8.8/32"]))
    with pytest.raises(RuntimeError, match="last API rule"):
        access.close_access(record, "rg", "aks")
    assert record.exists()


def test_cleanup_waits_for_inflight_update(tmp_path, monkeypatch):
    configs = iter(
        [config(["1.1.1.1/32"]), config([], "Updating"), config(["1.1.1.1/32", "8.8.8.8/32"])]
    )
    monkeypatch.setattr(access, "cluster_config", lambda *_: next(configs))
    monkeypatch.setattr(access, "update_ranges", lambda *_: None)
    waits = []
    monkeypatch.setattr(access.time, "sleep", waits.append)
    record = tmp_path / "access.json"
    access.open_access(record, "rg", "aks", "8.8.8.8")
    access.close_access(record, "rg", "aks")
    assert waits == [10]
    assert not record.exists()


def test_missing_cleanup_record_is_safe(tmp_path):
    access.close_access(tmp_path / "missing.json", "rg", "aks")


def test_failed_rule_removal_preserves_cleanup_record(tmp_path, monkeypatch):
    record = tmp_path / "access.json"
    record.write_text(
        json.dumps({"group": "rg", "cluster": "aks", "cidr": "8.8.8.8/32", "added": True})
    )
    monkeypatch.setattr(access, "cluster_config", lambda *_: config(["1.1.1.1/32", "8.8.8.8/32"]))

    def fail(*_):
        raise subprocess.CalledProcessError(1, "az")

    monkeypatch.setattr(access, "update_ranges", fail)
    with pytest.raises(subprocess.CalledProcessError):
        access.close_access(record, "rg", "aks")
    assert record.exists()


def test_busy_cluster_cleanup_timeout_retains_record(tmp_path, monkeypatch):
    record = tmp_path / "access.json"
    record.write_text(
        json.dumps({"group": "rg", "cluster": "aks", "cidr": "8.8.8.8/32", "added": True})
    )
    monkeypatch.setattr(access, "cluster_config", lambda *_: config([], "Updating"))
    clock = iter([0, 901])
    monkeypatch.setattr(access.time, "monotonic", lambda: next(clock))
    with pytest.raises(RuntimeError, match="still busy"):
        access.close_access(record, "rg", "aks")
    assert record.exists()
