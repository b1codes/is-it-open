"""
The post-deploy smoke test (smoke/smoke.py), run against a fake backend: what it reports when a check
fails. CI's E2E job runs it against a real stack, where every check passes.

The dev container mounts smoke/ at /smoke, which is where the repository root resolves to there.
"""

import importlib.util
from pathlib import Path

import pytest

SMOKE_PATH = Path(__file__).resolve().parents[3] / "smoke" / "smoke.py"


@pytest.fixture(scope="module")
def smoke():
    spec = importlib.util.spec_from_file_location("smoke", SMOKE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PLACE = {"tomtom_id": "tt-1", "name": "Test Pizza"}
BOOKMARK = "/api/places/bookmarks/tt-1"


@pytest.fixture
def backend(smoke, monkeypatch):
    """
    A backend that passes every check, as {(method, path): (status, body)}; change an entry to fail
    one. GET /api/places/bookmarks answers from `bookmarked`, which saving and deleting update.
    """
    bookmarked: list[dict] = []
    routes = {
        ("GET", "/health"): (200, {"status": "ok"}),
        ("POST", "/api/auth/login"): (200, {"token": "t"}),
        ("GET", "/api/auth/me"): (200, {"username": "smoke"}),
        ("GET", "/api/places/search"): (200, [PLACE]),
        ("POST", "/api/places/"): (200, PLACE),
        ("POST", "/api/places/bookmark"): (200, {"place": PLACE}),
        ("DELETE", BOOKMARK): (204, None),
    }
    sent = []

    def request(api, method, path, body=None, **params):
        sent.append((method, path))
        if (method, path) == ("GET", "/api/places/bookmarks"):
            return 200, list(bookmarked)
        status, data = routes[method, path]
        if status < 300 and (method, path) == ("POST", "/api/places/bookmark"):
            bookmarked.append(data)
        if status < 300 and method == "DELETE":
            bookmarked.clear()
        return status, data

    monkeypatch.setattr(smoke.Api, "request", request)
    return routes, sent


def run(smoke):
    return smoke.main(["smoke.py", "https://api.example.com"])


@pytest.fixture(autouse=True)
def account(monkeypatch):
    monkeypatch.setenv("SMOKE_USERNAME", "smoke")
    monkeypatch.setenv("SMOKE_PASSWORD", "pw")


def test_every_check_passes(smoke, backend, capsys):
    assert run(smoke) == 0
    assert "All checks passed." in capsys.readouterr().out


def test_a_failed_check_after_saving_still_deletes_the_bookmark_and_is_reported(smoke, backend, capsys, monkeypatch):
    _, sent = backend
    # The bookmark is saved, but the list doesn't show it.
    monkeypatch.setattr(smoke, "bookmarked_ids", lambda api: set())

    assert run(smoke) == 1
    assert ("DELETE", BOOKMARK) in sent
    assert capsys.readouterr().out.splitlines()[-1] == (
        "FAIL  bookmark round trip: GET /api/places/bookmarks doesn't list tt-1 after saving it"
    )


def test_a_failed_delete_does_not_hide_the_check_that_failed_first(smoke, backend, capsys, monkeypatch):
    # The smoke-failure issue is opened from this output, so it has to name the first failure.
    routes, sent = backend
    monkeypatch.setattr(smoke, "bookmarked_ids", lambda api: set())
    routes["DELETE", BOOKMARK] = (500, {"detail": "Internal Server Error"})

    assert run(smoke) == 1
    assert ("DELETE", BOOKMARK) in sent
    assert capsys.readouterr().out.splitlines()[-2:] == [
        "FAIL  bookmark round trip: GET /api/places/bookmarks doesn't list tt-1 after saving it",
        "      Deleting the bookmark afterwards failed too: DELETE /api/places/bookmarks/tt-1: expected 204, got 500: "
        '{"detail": "Internal Server Error"}',
    ]


def test_a_failed_delete_alone_fails_the_check(smoke, backend, capsys):
    routes, _ = backend
    routes["DELETE", BOOKMARK] = (500, {"detail": "Internal Server Error"})

    assert run(smoke) == 1
    assert capsys.readouterr().out.splitlines()[-1] == (
        "FAIL  bookmark round trip: DELETE /api/places/bookmarks/tt-1: expected 204, got 500: "
        '{"detail": "Internal Server Error"}'
    )
