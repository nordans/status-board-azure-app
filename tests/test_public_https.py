import hashlib
import io
import json
import ssl
from pathlib import Path

import pytest

from scripts import prepare_cert_manager, verify_public_endpoint
from scripts.render_aks import render

HOST = "statusboard-example.northeurope.cloudapp.azure.com"
VERSION = "a" * 40


@pytest.mark.parametrize(
    "hostname",
    ["localhost", "127.0.0.1", "attacker.example", HOST + "/path", HOST + "\nkind: Secret"],
)
def test_public_probe_rejects_unexpected_destinations(hostname):
    with pytest.raises(ValueError):
        verify_public_endpoint.verify(hostname, VERSION)


def public_response(url):
    if url.startswith("http:"):
        return 301, {"Location": f"https://{HOST}/api/status"}, b""
    body = json.dumps({"version": VERSION}).encode() if url.endswith("/api/status") else b"ok"
    return 200, {"Strict-Transport-Security": "max-age=86400"}, body


def test_public_probe_checks_redirect_and_served_commit_without_credentials(monkeypatch):
    calls = []

    def fetch(url):
        calls.append(url)
        return public_response(url)

    monkeypatch.setattr(verify_public_endpoint, "fetch", fetch)
    verify_public_endpoint.verify(HOST, VERSION)
    assert calls == [
        f"http://{HOST}/api/status",
        f"https://{HOST}/",
        f"https://{HOST}/health/ready",
        f"https://{HOST}/api/status",
    ]


@pytest.mark.parametrize("failure", ["redirect", "version", "readiness", "hsts"])
def test_public_probe_rejects_incorrect_routing_or_deployment(monkeypatch, failure):
    def fetch(url):
        code, headers, body = public_response(url)
        if failure == "redirect" and url.startswith("http:"):
            headers = {"Location": "https://attacker.example/api/status"}
        if failure == "version" and url.startswith("https:") and url.endswith("/api/status"):
            body = json.dumps({"version": "b" * 40}).encode()
        if failure == "readiness" and url.endswith("/health/ready"):
            code = 503
        if failure == "hsts":
            headers = {}
        return code, headers, body

    monkeypatch.setattr(verify_public_endpoint, "fetch", fetch)
    with pytest.raises(RuntimeError):
        verify_public_endpoint.verify(HOST, VERSION)


def test_tls_validation_failures_are_not_suppressed(monkeypatch):
    def fail(url):
        raise ssl.SSLCertVerificationError("untrusted certificate")

    monkeypatch.setattr(verify_public_endpoint, "fetch", fail)
    with pytest.raises(ssl.SSLCertVerificationError):
        verify_public_endpoint.verify(HOST, VERSION)


def test_no_redirect_handler_does_not_follow_location():
    assert (
        verify_public_endpoint.NoRedirect().redirect_request(
            None, None, 301, "redirect", {}, "https://attacker.example"
        )
        is None
    )


def test_cert_manager_download_integrity_is_checked_before_writing(monkeypatch, tmp_path):
    monkeypatch.setattr(prepare_cert_manager, "urlopen", lambda *a, **kw: io.BytesIO(b"tampered"))
    target = tmp_path / "manifests"
    with pytest.raises(RuntimeError, match="SHA-256"):
        prepare_cert_manager.prepare(target)
    assert not target.exists()


def test_verified_cert_manager_download_enables_gateway_support(monkeypatch, tmp_path):
    manifest = b"verified manifest"
    monkeypatch.setattr(prepare_cert_manager, "urlopen", lambda *a, **kw: io.BytesIO(manifest))
    monkeypatch.setattr(
        prepare_cert_manager, "MANIFEST_SHA256", hashlib.sha256(manifest).hexdigest()
    )
    prepare_cert_manager.prepare(tmp_path)
    assert (tmp_path / "cert-manager.yaml").read_bytes() == manifest
    assert "--enable-gateway-api" in (tmp_path / "kustomization.yaml").read_text()


@pytest.mark.parametrize(
    "changes",
    [
        {"PUBLIC_HOSTNAME": "attacker.example"},
        {"PUBLIC_HOSTNAME": "other-example.northeurope.cloudapp.azure.com"},
        {"PUBLIC_DNS_LABEL": "demo\nkind: Secret"},
        {"ACME_ENVIRONMENT": "https://attacker.example"},
    ],
)
def test_public_manifest_inputs_fail_closed(changes):
    values = {
        "PUBLIC_DNS_LABEL": "statusboard-example",
        "PUBLIC_HOSTNAME": HOST,
        "ACME_ENVIRONMENT": "staging",
    }
    with pytest.raises(ValueError):
        render("public", "kubectl", **(values | changes))


@pytest.mark.parametrize("environment", ["staging", "production"])
def test_public_render_uses_selected_acme_authority(monkeypatch, environment):
    import subprocess

    source = Path("k8s/bootstrap/public/issuer.yaml").read_text()
    monkeypatch.setattr(
        subprocess, "run", lambda *a, **kw: subprocess.CompletedProcess(a, 0, source)
    )
    result = render(
        "public",
        "kubectl",
        PUBLIC_DNS_LABEL="statusboard-example",
        PUBLIC_HOSTNAME=HOST,
        ACME_ENVIRONMENT=environment,
    )
    expected_server = (
        "acme-staging-v02.api.letsencrypt.org"
        if environment == "staging"
        else "acme-v02.api.letsencrypt.org"
    )
    assert expected_server in result
    assert f"letsencrypt-account-{environment}" in result
    assert "__" not in result
