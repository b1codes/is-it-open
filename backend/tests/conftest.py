"""
Shared pytest fixtures.

- `firestore_db`: an empty emulator project for the test (see tests/base.py for the unittest-style
  equivalent, FirestoreTestCase).
- Factories: `make_user`, `make_place`, `make_bookmark`.
- Clients: `api_client` (anonymous), `auth_client` (local API token), `auth0_client` (mock-mode
  Auth0 JWT), and `any_auth_client`, which runs the test once with each kind of credential.
- HTTP: `http_mock` fails any outbound request that isn't registered on it; `tomtom` and
  `auth0_tenant` register the TomTom API and an Auth0 tenant's JWKS on it.
- DNS: `dns` fakes name lookups for services/safe_fetch.py (the iCal proxy), so no test looks a
  name up.
"""

import datetime
import ipaddress
import json
import os
import socket
from dataclasses import dataclass, field
from typing import Any

import jwt
import pytest
import responses
from cryptography.hazmat.primitives.asymmetric import rsa
from django.core.cache import cache
from django.core.exceptions import ImproperlyConfigured
from django.test import Client
from hypothesis import settings as hypothesis_settings
from jwt.algorithms import RSAAlgorithm

from apps.places import repository as places
from apps.users import auth as auth_module
from apps.users import repository as users
from services import safe_fetch
from services.firestore import clear_emulator
from tests import factories
from tests.base import TEST_PROJECT

# Property-based tests: CI runs a fixed, reproducible set of examples (so a PR can't fail on a
# newly drawn one); locally each run draws new ones, and the nightly run draws many more. Pick
# with HYPOTHESIS_PROFILE.
hypothesis_settings.register_profile("dev", max_examples=100, deadline=None)
hypothesis_settings.register_profile("ci", max_examples=200, deadline=None, derandomize=True, print_blob=True)
hypothesis_settings.register_profile("nightly", max_examples=5000, deadline=None, print_blob=True)
hypothesis_settings.load_profile(os.environ.get("HYPOTHESIS_PROFILE", "dev"))


@pytest.fixture(autouse=True)
def _isolate(settings):
    """Keep a developer's .env and state left by earlier tests out of every test."""
    settings.TOMTOM_API_KEY = ""
    settings.TOMTOM_BASE_URL = TOMTOM_BASE
    settings.AUTH0_MOCK = False  # the default; make_auth0_token turns mock mode on
    settings.AUTH0_DOMAIN = ""
    settings.AUTH0_AUDIENCE = ""
    settings.SAFE_FETCH_PRIVATE_HOSTS = []
    cache.clear()
    auth_module._jwks_cache.clear()
    yield
    auth_module._jwks_cache.clear()


@pytest.fixture
def firestore_db(settings):
    """An empty Firestore emulator project, separate from local development data."""
    if not settings.FIRESTORE_EMULATOR_HOST:
        raise ImproperlyConfigured(
            "Tests need the Firestore emulator. Start it with `docker compose up -d firestore` "
            "and set FIRESTORE_EMULATOR_HOST (e.g. localhost:8080)."
        )
    settings.GOOGLE_CLOUD_PROJECT = TEST_PROJECT
    clear_emulator()


# --- Outbound HTTP ---

# What `dns` resolves an unknown name to: a public address (example.com's), so safe_fetch allows it.
PUBLIC_TEST_ADDRESS = "93.184.215.14"


def _is_ip_literal(host: str) -> bool:
    try:
        socket.getaddrinfo(host, None, flags=socket.AI_NUMERICHOST)  # local; also takes "127.1", "0x7f000001"
    except socket.gaierror:
        return False
    return True


@pytest.fixture(autouse=True)
def dns(monkeypatch):
    """
    Fake DNS for safe_fetch. A name in the returned dict resolves to its addresses; IP literals (in
    any form getaddrinfo takes) and localhost resolve as usual; any other name to PUBLIC_TEST_ADDRESS.
    """
    records: dict[str, list[str]] = {}
    real_resolve = safe_fetch.resolve

    def resolve(host, port):
        if host in records:
            return [ipaddress.ip_address(a) for a in records[host]]
        if host == "localhost" or _is_ip_literal(host):
            return real_resolve(host, port)
        return [ipaddress.ip_address(PUBLIC_TEST_ADDRESS)]

    monkeypatch.setattr(safe_fetch, "resolve", resolve)
    return records


@pytest.fixture
def http_mock(settings):
    """
    Intercepts `requests`. Unregistered URLs raise ConnectionError, so a test can never reach a
    real service; the emulator (used to reset Firestore) is let through.
    """
    with responses.RequestsMock(assert_all_requests_are_fired=False) as mock:
        if settings.FIRESTORE_EMULATOR_HOST:
            mock.add_passthru(f"http://{settings.FIRESTORE_EMULATOR_HOST}")
        yield mock


TOMTOM_KEY = "test-tomtom-key"
TOMTOM_BASE = "https://api.tomtom.com/search/2"


@pytest.fixture
def tomtom(settings, http_mock):
    """Enables TomTomClient with a test key. Register its endpoints on the returned mock."""
    settings.TOMTOM_API_KEY = TOMTOM_KEY
    return http_mock


# --- Factories ---


@pytest.fixture
def make_user(firestore_db):
    def make(username=None, password="password", **fields) -> users.User:
        user = users.create_user(username or factories.unique_id("user"), password, **fields)
        assert user is not None, "username already taken"
        return user

    return make


@pytest.fixture
def make_place(firestore_db):
    def make(tomtom_id=None, **data) -> dict:
        return places.update_or_create_place(factories.place_data(tomtom_id, **data))

    return make


@pytest.fixture
def make_bookmark(firestore_db):
    def make(user, place, custom_name=None, **fields) -> dict:
        saved = places.save_place(user, place, custom_name=custom_name)
        if fields:
            saved = places.update_saved_place(user, place, **fields)
        return saved

    return make


@pytest.fixture
def user(make_user):
    return make_user("alice", email="alice@example.com", first_name="Alice")


@pytest.fixture
def place(make_place):
    return make_place("place-1", name="Joe's Pizza", hours=factories.hours((0, "09:00", "17:00")))


# --- API clients ---


class ApiClient:
    """Django test client for the JSON API under /api, optionally sending a bearer token."""

    def __init__(self, token: str | None = None, user: users.User | None = None):
        self.token = token
        self.user = user
        self._client = Client()

    def _headers(self) -> dict:
        return {"Authorization": f"Bearer {self.token}"} if self.token else {}

    def _send(self, method: str, path: str, payload: Any = None, **params):
        url = f"/api{path}"
        send = getattr(self._client, method)
        if method == "get":
            return send(url, params, headers=self._headers())
        if payload is None:
            return send(url, headers=self._headers())
        # A str/bytes payload is sent as-is, e.g. to test malformed JSON.
        body = payload if isinstance(payload, str | bytes) else json.dumps(payload)
        return send(url, data=body, content_type="application/json", headers=self._headers())

    def get(self, path: str, **params):
        return self._send("get", path, **params)

    def post(self, path: str, payload: Any = None):
        return self._send("post", path, payload)

    def put(self, path: str, payload: Any = None):
        return self._send("put", path, payload)

    def patch(self, path: str, payload: Any = None):
        return self._send("patch", path, payload)

    def delete(self, path: str):
        return self._send("delete", path)


@pytest.fixture
def api_client(firestore_db):
    return ApiClient()


@pytest.fixture
def auth_client(user):
    """Signed in as `user` with a local API token (from /auth/login or /auth/register)."""
    return ApiClient(users.get_or_create_token(user), user)


# Long enough that PyJWT doesn't warn about a short HMAC key. Mock mode never checks it anyway.
_MOCK_SIGNING_KEY = "mock-mode-signing-key-not-verified"


@pytest.fixture
def make_auth0_token(settings):
    """Mock-mode Auth0 JWTs (AUTH0_MOCK=True, as in local development): decoded without verification."""
    settings.AUTH0_MOCK = True

    def make(sub="auth0|alice", **claims) -> str:
        return jwt.encode({"sub": sub, **claims}, _MOCK_SIGNING_KEY, algorithm="HS256")

    return make


@pytest.fixture
def auth0_client(firestore_db, make_auth0_token):
    """Signed in with a mock-mode Auth0 JWT; the user is created on the first request."""
    sub = "auth0|alice"
    token = make_auth0_token(sub, email="alice@example.com", given_name="Alice", family_name="Liddell")
    # Sign in once so the test can use the user.
    user = auth_module.GlobalAuth().authenticate(None, token)
    assert user is not None
    return ApiClient(token, user)


@pytest.fixture(params=["local-token", "auth0-jwt"])
def any_auth_client(request):
    """Runs the test once signed in with each kind of credential."""
    return request.getfixturevalue("auth_client" if request.param == "local-token" else "auth0_client")


# --- A real (non-mock) Auth0 tenant ---


@pytest.fixture(scope="session")
def rsa_private_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def public_jwk(private_key, kid: str) -> dict:
    jwk = json.loads(RSAAlgorithm.to_jwk(private_key.public_key()))
    return {**jwk, "kid": kid, "use": "sig", "alg": "RS256"}


@dataclass
class Auth0Tenant:
    """An Auth0 tenant whose JWKS is served by `http_mock`; signs RS256 tokens like Auth0 does."""

    private_key: Any
    domain: str = "is-it-open-test.us.auth0.com"
    audience: str = "https://api.is-it-open.test"
    kid: str = "test-key-1"
    jwks_response: Any = field(default=None, repr=False)

    @property
    def issuer(self) -> str:
        return f"https://{self.domain}/"

    @property
    def jwks_url(self) -> str:
        return f"https://{self.domain}/.well-known/jwks.json"

    def claims(self, sub="auth0|alice", **overrides) -> dict:
        """Auth0-style claims. An override of None leaves that claim out."""
        now = datetime.datetime.now(datetime.UTC)
        claims = {
            "sub": sub,
            "aud": self.audience,
            "iss": self.issuer,
            "iat": now,
            "exp": now + datetime.timedelta(hours=1),
            "email": "alice@example.com",
            "given_name": "Alice",
            **overrides,
        }
        return {k: v for k, v in claims.items() if v is not None}

    def token(self, sub="auth0|alice", *, key=None, kid: str | None = "default", algorithm="RS256", **claims) -> str:
        """A signed token. Pass kid=None to leave the `kid` header out."""
        headers = {} if kid is None else {"kid": self.kid if kid == "default" else kid}
        return jwt.encode(
            self.claims(sub, **claims), key or self.private_key, algorithm=algorithm, headers=headers or None
        )


@pytest.fixture
def auth0_tenant(settings, http_mock, rsa_private_key):
    """Real Auth0 verification (AUTH0_MOCK=False) against a test tenant's JWKS."""
    tenant = Auth0Tenant(rsa_private_key)
    settings.AUTH0_MOCK = False
    settings.AUTH0_DOMAIN = tenant.domain
    settings.AUTH0_AUDIENCE = tenant.audience
    tenant.jwks_response = http_mock.get(tenant.jwks_url, json={"keys": [public_jwk(rsa_private_key, tenant.kid)]})
    return tenant
