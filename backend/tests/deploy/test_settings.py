"""
Production configuration: what config.settings loads from backend/.env under docker-compose.prod.yml,
the checks the production entrypoint makes before starting, and the ALLOWED_HOSTS and CORS behavior
those settings produce.

Settings are imported in a fresh interpreter with only the given environment and .env file, so a
developer's .env and pytest's own settings stay out of it (as in tests/security/test_auth_config.py).
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest
import yaml
from django.test import Client

BACKEND_DIR = Path(__file__).resolve().parents[2]
REPO_DIR = BACKEND_DIR.parent
PROD_COMPOSE = yaml.safe_load((REPO_DIR / "docker-compose.prod.yml").read_text())["services"]["backend"]
# What docker-compose.prod.yml sets over backend/.env (Compose's `environment` wins over `env_file`).
PROD_OVERRIDES = PROD_COMPOSE["environment"]

REPORTED = ["DEBUG", "ALLOWED_HOSTS", "CORS_ALLOW_ALL_ORIGINS", "AUTH0_MOCK", "FIRESTORE_EMULATOR_HOST"]


def load_settings(tmp_path, dotenv: str = "", **env) -> subprocess.CompletedProcess:
    """Imports config.settings with `dotenv` as backend/.env and `env` as the environment."""
    (tmp_path / ".env").write_text(dotenv)
    code = (
        "import decouple, json; "
        f"decouple.config = decouple.AutoConfig(search_path={str(tmp_path)!r}); "
        "from config import settings; "
        f"print(json.dumps({{name: getattr(settings, name) for name in {REPORTED!r}}}))"
    )
    return subprocess.run(
        [sys.executable, "-c", code],
        cwd=BACKEND_DIR,
        env={"PATH": os.environ["PATH"], **env},
        capture_output=True,
        text=True,
        timeout=60,
    )


def loaded(result: subprocess.CompletedProcess) -> dict:
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


# --- config.settings ---


def test_sample_env_is_a_safe_production_config(tmp_path):
    """backend/sample.env, which README_DEPLOY.md says to copy, loads as a locked-down production config."""
    result = load_settings(tmp_path, (BACKEND_DIR / "sample.env").read_text(), **PROD_OVERRIDES)

    assert loaded(result) == {
        "DEBUG": False,
        "ALLOWED_HOSTS": ["yourdomain.com", "your-ec2-ip"],
        "CORS_ALLOW_ALL_ORIGINS": False,
        "AUTH0_MOCK": False,
        "FIRESTORE_EMULATOR_HOST": "",
    }


def test_compose_overrides_debug_and_the_emulator_whatever_env_says(tmp_path):
    dotenv = "SECRET_KEY=s\nDEBUG=1\nFIRESTORE_EMULATOR_HOST=firestore:8080\n"

    settings = loaded(load_settings(tmp_path, dotenv, **PROD_OVERRIDES))

    assert PROD_OVERRIDES == {"DEBUG": "0", "FIRESTORE_EMULATOR_HOST": ""}
    assert settings["DEBUG"] is False
    assert settings["FIRESTORE_EMULATOR_HOST"] == ""


def test_debug_is_off_unless_turned_on(tmp_path):
    assert loaded(load_settings(tmp_path, SECRET_KEY="s"))["DEBUG"] is False


def test_secret_key_is_required(tmp_path):
    result = load_settings(tmp_path)

    assert result.returncode != 0
    assert "SECRET_KEY not found" in result.stderr


@pytest.mark.parametrize(
    "value, expected",
    [
        ("api.example.com", ["api.example.com"]),
        (" api.example.com , 203.0.113.7 ,", ["api.example.com", "203.0.113.7"]),
    ],
)
def test_allowed_hosts_is_a_comma_separated_list(tmp_path, value, expected):
    assert loaded(load_settings(tmp_path, SECRET_KEY="s", ALLOWED_HOSTS=value))["ALLOWED_HOSTS"] == expected


# --- The production entrypoint's checks (docker-compose.prod.yml) ---

GOOD_ENV = {"SECRET_KEY": "s", "GOOGLE_CLOUD_PROJECT": "is-it-open-prod"}


def run_entrypoint(**env) -> subprocess.CompletedProcess:
    """Runs the backend's entrypoint script from docker-compose.prod.yml, with `true` as the command."""
    sh, flag, script, name = PROD_COMPOSE["entrypoint"]
    # Compose turns $$ into $ before handing the script to the container.
    return subprocess.run(
        [sh, flag, script.replace("$$", "$"), name, "true"],
        env={"PATH": os.environ["PATH"], **env},
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_entrypoint_starts_with_the_required_settings():
    result = run_entrypoint(**GOOD_ENV)

    assert result.returncode == 0, result.stderr


def test_entrypoint_accepts_a_key_file_that_exists(tmp_path):
    key = tmp_path / "key.json"
    key.write_text("{}")

    assert run_entrypoint(**GOOD_ENV, GOOGLE_APPLICATION_CREDENTIALS=str(key)).returncode == 0


@pytest.mark.parametrize(
    "env, message",
    [
        ({"SECRET_KEY": ""}, "SECRET_KEY is not set"),
        ({"SECRET_KEY": None}, "SECRET_KEY is not set"),
        ({"GOOGLE_CLOUD_PROJECT": ""}, "GOOGLE_CLOUD_PROJECT is not set"),
        ({"GOOGLE_CLOUD_PROJECT": None}, "GOOGLE_CLOUD_PROJECT is not set"),
        ({"GOOGLE_CLOUD_PROJECT": "demo-is-it-open"}, "only exists in the emulator"),
        ({"FIRESTORE_DATABASE": ""}, "FIRESTORE_DATABASE is empty"),
        ({"GOOGLE_APPLICATION_CREDENTIALS": "/missing/key.json"}, "is not a file in the container"),
    ],
    ids=[
        "empty-secret-key",
        "no-secret-key",
        "empty-project",
        "no-project",
        "emulator-project",
        "empty-database",
        "missing-key-file",
    ],
)
def test_entrypoint_refuses_settings_that_would_fail_silently(env, message):
    merged = {k: v for k, v in {**GOOD_ENV, **env}.items() if v is not None}

    result = run_entrypoint(**merged)

    assert result.returncode == 1
    assert result.stderr.startswith("backend/.env: ")
    assert message in result.stderr


# --- ALLOWED_HOSTS and CORS on requests ---

ORIGIN = "https://app.example.com"


def test_requests_for_other_hosts_are_refused(settings):
    settings.ALLOWED_HOSTS = ["api.example.com"]

    assert Client(HTTP_HOST="api.example.com").get("/api/openapi.json").status_code == 200
    assert Client(HTTP_HOST="evil.example.com").get("/api/openapi.json").status_code == 400


def preflight():
    return Client().options("/api/auth/login", HTTP_ORIGIN=ORIGIN, HTTP_ACCESS_CONTROL_REQUEST_METHOD="POST")


def test_cors_is_closed_when_allow_all_is_off(settings):
    """The production default in sample.env: browsers on other origins get no CORS headers."""
    settings.CORS_ALLOW_ALL_ORIGINS = False

    assert "Access-Control-Allow-Origin" not in preflight()
    assert "Access-Control-Allow-Origin" not in Client().get("/api/openapi.json", HTTP_ORIGIN=ORIGIN)


def test_cors_allows_any_origin_when_allow_all_is_on(settings):
    settings.CORS_ALLOW_ALL_ORIGINS = True

    response = preflight()

    assert response.status_code == 200
    assert response["Access-Control-Allow-Origin"] == "*"
    assert "authorization" in response["Access-Control-Allow-Headers"]
