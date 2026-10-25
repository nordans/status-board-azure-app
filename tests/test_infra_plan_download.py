import hashlib
import subprocess
from pathlib import Path

import pytest

from scripts import infra_plan_download as download

PLAN = b"reviewed binary Terraform plan"
DIGEST = hashlib.sha256(PLAN).hexdigest()


@pytest.mark.parametrize(
    "detail",
    [
        "ERROR: The request may be blocked by network rules of storage account.",
        "ERROR: (AuthorizationFailure) This request is not authorized.",
    ],
)
def test_download_retries_network_denial_and_verifies_complete_plan(tmp_path, monkeypatch, detail):
    attempts = []
    waits = []
    destination = tmp_path / "dev.tfplan"

    def az(*arguments):
        temporary = Path(arguments[arguments.index("--file") + 1])
        assert not destination.exists()
        assert not temporary.exists()
        assert arguments[arguments.index("--name") + 1] == "123/1/deploy.tfplan"
        assert arguments[arguments.index("--auth-mode") + 1] == "login"
        attempts.append(arguments)
        if len(attempts) == 1:
            temporary.write_bytes(b"partial download")
            raise subprocess.CalledProcessError(1, "az", stderr=detail)
        temporary.write_bytes(PLAN)
        return ""

    monkeypatch.setattr(download, "run_az", az)
    monkeypatch.setattr(download.time, "sleep", waits.append)
    download.download_plan("account", "tfplans", "123/1/deploy.tfplan", destination, DIGEST)
    assert destination.read_bytes() == PLAN
    assert len(attempts) == 2
    assert waits == [5]
    assert list(tmp_path.iterdir()) == [destination]


@pytest.mark.parametrize(
    "detail",
    [
        "AuthorizationPermissionMismatch",
        "AuthenticationFailed",
        "BlobNotFound",
        "ContainerNotFound",
        "Unrecognized CLI argument",
        "AuthorizationPermissionMismatch: The request may be blocked by network rules",
    ],
)
def test_permanent_download_errors_fail_without_retry(tmp_path, monkeypatch, detail):
    waits = []

    def az(*arguments):
        Path(arguments[arguments.index("--file") + 1]).write_bytes(b"partial")
        raise subprocess.CalledProcessError(1, "az", stderr=detail)

    monkeypatch.setattr(download, "run_az", az)
    monkeypatch.setattr(download.time, "sleep", waits.append)
    with pytest.raises(RuntimeError, match=detail):
        download.download_plan("account", "tfplans", "plan", tmp_path / "dev.tfplan", DIGEST)
    assert not waits
    assert not list(tmp_path.iterdir())


def test_persistent_network_denial_times_out_and_removes_partial_plan(tmp_path, monkeypatch):
    clock = iter([0, 301])

    def az(*arguments):
        Path(arguments[arguments.index("--file") + 1]).write_bytes(b"partial")
        raise subprocess.CalledProcessError(1, "az", stderr="AuthorizationFailure")

    monkeypatch.setattr(download, "run_az", az)
    monkeypatch.setattr(download.time, "monotonic", lambda: next(clock))
    with pytest.raises(RuntimeError, match="five minutes: AuthorizationFailure"):
        download.download_plan("account", "tfplans", "plan", tmp_path / "dev.tfplan", DIGEST)
    assert not list(tmp_path.iterdir())


def test_hash_mismatch_never_publishes_or_retries_plan(tmp_path, monkeypatch):
    attempts = []

    def az(*arguments):
        attempts.append(arguments)
        Path(arguments[arguments.index("--file") + 1]).write_bytes(b"different plan")

    monkeypatch.setattr(download, "run_az", az)
    with pytest.raises(RuntimeError, match="SHA256 does not match"):
        download.download_plan("account", "tfplans", "plan", tmp_path / "dev.tfplan", DIGEST)
    assert len(attempts) == 1
    assert not list(tmp_path.iterdir())


@pytest.mark.parametrize("digest", ["", "a" * 63, "G" * 64, "A" * 64])
def test_invalid_expected_digest_is_rejected_before_download(tmp_path, monkeypatch, digest):
    attempts = []
    monkeypatch.setattr(download, "run_az", lambda *arguments: attempts.append(arguments))
    with pytest.raises(ValueError, match="SHA256 digest"):
        download.download_plan("account", "tfplans", "plan", tmp_path / "dev.tfplan", digest)
    assert not attempts
    assert not list(tmp_path.iterdir())


def test_existing_destination_is_preserved_without_download(tmp_path, monkeypatch):
    destination = tmp_path / "dev.tfplan"
    destination.write_bytes(b"previous plan")
    attempts = []
    monkeypatch.setattr(download, "run_az", lambda *arguments: attempts.append(arguments))
    with pytest.raises(FileExistsError):
        download.download_plan("account", "tfplans", "plan", destination, DIGEST)
    assert not attempts
    assert destination.read_bytes() == b"previous plan"
