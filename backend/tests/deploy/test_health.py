"""GET /health (config/health.py): the liveness check Docker, load balancers and the smoke test use."""

import pytest
from django.test import Client

from services import firestore


@pytest.fixture
def no_firestore(monkeypatch):
    """Fails the test if anything opens a Firestore client."""

    def fail(*args, **kwargs):
        raise AssertionError("/health must not touch Firestore")

    monkeypatch.setattr(firestore, "_clients", {})
    monkeypatch.setattr(firestore.firestore, "Client", fail)


@pytest.mark.parametrize("method", ["get", "head"])
def test_answers_ok_without_touching_firestore(no_firestore, method):
    response = getattr(Client(), method)("/health")

    assert response.status_code == 200
    assert response["Content-Type"] == "application/json"
    if method == "get":
        assert response.json() == {"status": "ok"}


def test_answers_probes_addressed_by_ip_whatever_allowed_hosts_says(settings):
    """Probes reach the container as localhost or by IP, which ALLOWED_HOSTS doesn't list in production."""
    settings.ALLOWED_HOSTS = ["api.example.com"]

    for host in ("localhost:8000", "10.0.0.5", "127.0.0.1:8000"):
        assert Client(HTTP_HOST=host).get("/health").status_code == 200
        assert Client(HTTP_HOST=host).get("/api/openapi.json").status_code == 400


def test_only_get_and_head(no_firestore):
    assert Client().post("/health").status_code == 404


def test_only_the_exact_path():
    assert Client().get("/health/").status_code == 404
    assert Client().get("/api/health").status_code == 404
