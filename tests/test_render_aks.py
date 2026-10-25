import subprocess

import pytest

from scripts.render_aks import render


@pytest.mark.parametrize(
    "key,value",
    [
        ("IMAGE_REPOSITORY", "attacker.example/status-board"),
        ("IMAGE_DIGEST", "latest"),
        ("APP_VERSION", "main\nkind: Secret"),
    ],
)
def test_application_values_cannot_inject_yaml_or_mutable_images(key, value):
    values = {
        "IMAGE_REPOSITORY": "example.azurecr.io/status-board",
        "IMAGE_DIGEST": "sha256:" + "a" * 64,
        "APP_VERSION": "b" * 40,
    }
    values[key] = value
    with pytest.raises(ValueError, match=key):
        render("application", "kubectl", **values)


def test_bootstrap_rejects_injected_identity():
    with pytest.raises(ValueError, match="APP_CLIENT_ID"):
        render("bootstrap", "kubectl", APP_CLIENT_ID="id\nkind: Secret")


def test_unresolved_manifest_values_fail_closed(monkeypatch):
    monkeypatch.setattr(
        subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(args, 0, "__UNKNOWN__"),
    )
    with pytest.raises(RuntimeError, match="unresolved"):
        render(
            "application",
            "kubectl",
            IMAGE_REPOSITORY="example.azurecr.io/status-board",
            IMAGE_DIGEST="sha256:" + "a" * 64,
            APP_VERSION="b" * 40,
        )


def test_numeric_commit_is_rendered_as_a_string(monkeypatch):
    monkeypatch.setattr(
        subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args, 0, "APP_VERSION: __APP_VERSION__"
        ),
    )
    result = render(
        "application",
        "kubectl",
        IMAGE_REPOSITORY="example.azurecr.io/status-board",
        IMAGE_DIGEST="sha256:" + "a" * 64,
        APP_VERSION="0" * 40,
    )
    assert result == 'APP_VERSION: "' + "0" * 40 + '"'
