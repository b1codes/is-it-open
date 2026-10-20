"""
Auth configuration: settings that leave AUTH0_MOCK out get real verification, and mock mode (which
accepts unsigned tokens) can't be turned on outside DEBUG. Each case imports config.settings in a
fresh interpreter, with only the given environment: no developer .env, and no pytest overrides.
"""

import os
import subprocess
import sys
from pathlib import Path

import jwt
import pytest

from tests.conftest import ApiClient

BACKEND_DIR = Path(__file__).resolve().parents[2]


def load_settings(tmp_path, **env) -> subprocess.CompletedProcess:
    """Imports config.settings with `env` alone and prints AUTH0_MOCK."""
    (tmp_path / ".env").write_text("")  # decouple reads this empty file instead of searching for one
    code = (
        "import decouple; "
        f"decouple.config = decouple.AutoConfig(search_path={str(tmp_path)!r}); "
        "from config import settings; print(settings.AUTH0_MOCK)"
    )
    return subprocess.run(
        [sys.executable, "-c", code],
        cwd=BACKEND_DIR,
        env={"PATH": os.environ["PATH"], "SECRET_KEY": "test-only", **env},
        capture_output=True,
        text=True,
        timeout=60,
    )


@pytest.mark.parametrize(
    "env, expected",
    [
        ({}, "False"),
        ({"DEBUG": "1"}, "False"),
        ({"AUTH0_MOCK": "0"}, "False"),
        ({"AUTH0_MOCK": "1", "DEBUG": "1"}, "True"),
    ],
    ids=["unset", "unset-with-debug", "off", "on-with-debug"],
)
def test_mock_mode_is_off_unless_turned_on(tmp_path, env, expected):
    result = load_settings(tmp_path, **env)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == expected


@pytest.mark.parametrize("debug", [None, "0"], ids=["debug-unset", "debug-off"])
def test_mock_mode_without_debug_refuses_to_start(tmp_path, debug):
    result = load_settings(tmp_path, AUTH0_MOCK="1", **({"DEBUG": debug} if debug else {}))

    assert result.returncode != 0
    assert "ImproperlyConfigured: AUTH0_MOCK accepts unsigned tokens" in result.stderr


def test_production_settings_reject_unsigned_tokens(firestore_db, auth0_tenant):
    """With the tenant configured and mock mode left at its default, a token Auth0 didn't sign is refused."""
    forged = jwt.encode(auth0_tenant.claims("auth0|victim"), None, algorithm="none", headers={"kid": auth0_tenant.kid})
    mock_style = jwt.encode({"sub": "auth0|victim"}, "not-auth0s-key-but-long-enough-for-hs256", algorithm="HS256")

    for token in (forged, mock_style):
        assert ApiClient(token).get("/auth/me").status_code == 401
    assert ApiClient(auth0_tenant.token("auth0|victim")).get("/auth/me").status_code == 200


def test_without_a_tenant_auth0_tokens_are_refused_but_passwords_work(settings, firestore_db, make_user, http_mock):
    settings.AUTH0_DOMAIN = ""
    make_user("alice", password="pw")
    unsigned = jwt.encode({"sub": "auth0|victim"}, None, algorithm="none")

    assert ApiClient(unsigned).get("/auth/me").status_code == 401
    token = ApiClient().post("/auth/login", {"username": "alice", "password": "pw"}).json()["token"]
    assert ApiClient(token).get("/auth/me").status_code == 200
