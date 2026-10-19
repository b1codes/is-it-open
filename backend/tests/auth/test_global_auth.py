"""
apps/users/auth.py: bearer authentication with local API tokens and Auth0 JWTs.

Real verification (AUTH0_MOCK=False) runs against `auth0_tenant`, which signs RS256 tokens and
serves its JWKS through `http_mock`. tests/test_auth0.py covers mock mode.
"""

import datetime
from types import SimpleNamespace

import jwt
import pytest
import requests
from cryptography.hazmat.primitives.asymmetric import rsa
from freezegun import freeze_time

from apps.users import auth as auth_module
from apps.users import repository as users
from apps.users.auth import GlobalAuth
from tests.conftest import ApiClient, public_jwk


@pytest.fixture
def authenticate(firestore_db):
    """GlobalAuth().authenticate with a stand-in request; returns (user, request)."""

    def run(token):
        request = SimpleNamespace()
        return GlobalAuth().authenticate(request, token), request

    return run


@pytest.fixture(scope="module")
def other_private_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


# --- Local API tokens ---


class TestLocalTokens:
    def test_valid_token(self, authenticate, user):
        token = users.get_or_create_token(user)

        authed, request = authenticate(token)

        assert authed == users.get_user("alice")
        assert request.auth_token == token

    @pytest.mark.parametrize("token", ["", "nope", "0" * 40, "eyJonly.two"])
    def test_unknown_token(self, authenticate, user, token):
        users.get_or_create_token(user)

        authed, request = authenticate(token)

        assert authed is None
        assert not hasattr(request, "auth_token")

    def test_without_a_request(self, firestore_db, user):
        assert GlobalAuth().authenticate(None, users.get_or_create_token(user)) == users.get_user("alice")


# --- Auth0, verified against the tenant's JWKS ---


class TestAuth0Verification:
    def test_valid_token_signs_in_and_creates_the_user(self, authenticate, auth0_tenant):
        token = auth0_tenant.token("auth0|bob", email="bob@example.com", given_name="Bob", family_name="Smith")

        user, request = authenticate(token)

        assert user is not None
        assert (user.username, user.email, user.first_name, user.last_name) == (
            "auth0|bob",
            "bob@example.com",
            "Bob",
            "Smith",
        )
        assert not user.has_usable_password()
        assert request.auth_token == token
        assert users.get_user("auth0|bob") == user

    def test_returning_user_keeps_their_account(self, authenticate, auth0_tenant):
        first, _ = authenticate(auth0_tenant.token("auth0|bob", given_name="Bob"))
        again, _ = authenticate(auth0_tenant.token("auth0|bob", given_name="Changed"))

        assert again == first
        assert again.first_name == "Bob"  # profile claims only fill a new account

    @pytest.mark.parametrize(
        "claims, expected_first_name",
        [
            ({"given_name": "Given", "nickname": "Nick", "name": "Full"}, "Given"),
            ({"given_name": None, "nickname": "Nick", "name": "Full"}, "Nick"),
            ({"given_name": None, "name": "Full Name"}, "Full Name"),
            ({"given_name": None}, ""),
        ],
    )
    def test_first_name_falls_back_through_the_profile_claims(
        self, authenticate, auth0_tenant, claims, expected_first_name
    ):
        user, _ = authenticate(auth0_tenant.token("auth0|bob", **claims))

        assert user.first_name == expected_first_name

    def test_missing_email_is_stored_empty(self, authenticate, auth0_tenant):
        user, _ = authenticate(auth0_tenant.token("auth0|bob", email=None))

        assert user.email == ""

    def test_works_through_the_api(self, firestore_db, auth0_tenant):
        token = auth0_tenant.token("auth0|bob")

        response = ApiClient(token).get("/auth/me")

        assert response.status_code == 200
        assert response.json()["username"] == "auth0|bob"
        assert response.json()["token"] == token

    def test_expired_token(self, authenticate, auth0_tenant):
        with freeze_time("2025-01-15 12:00:00"):
            token = auth0_tenant.token()  # expires an hour later

        # Only the verification step runs on the frozen clock: the Firestore (gRPC) client hangs on one.
        with freeze_time("2025-01-15 12:59:59"):
            assert GlobalAuth().verify_auth0_token(token)["sub"] == "auth0|alice"
        with freeze_time("2025-01-15 13:00:01"):
            assert GlobalAuth().verify_auth0_token(token) is None
        assert authenticate(token)[0] is None  # now, long after it expired

    def test_token_not_valid_yet(self, authenticate, auth0_tenant):
        not_before = datetime.datetime.now(datetime.UTC) + datetime.timedelta(minutes=5)

        assert authenticate(auth0_tenant.token(nbf=not_before))[0] is None

    @pytest.mark.parametrize(
        "claims",
        [
            {"aud": "https://some-other-api.example"},
            {"aud": ["https://some-other-api.example", "https://another.example"]},
            {"aud": None},
        ],
        ids=["wrong", "wrong-list", "missing"],
    )
    def test_wrong_audience(self, authenticate, auth0_tenant, claims):
        assert authenticate(auth0_tenant.token(**claims))[0] is None

    def test_audience_list_including_ours(self, authenticate, auth0_tenant):
        token = auth0_tenant.token(aud=[auth0_tenant.audience, f"https://{auth0_tenant.domain}/userinfo"])

        assert authenticate(token)[0] is not None

    @pytest.mark.parametrize(
        "issuer",
        ["https://evil.example/", "https://is-it-open-test.us.auth0.com", None],
        ids=["other", "no-slash", "missing"],
    )
    def test_wrong_issuer(self, authenticate, auth0_tenant, issuer):
        assert authenticate(auth0_tenant.token(iss=issuer))[0] is None

    def test_missing_sub(self, authenticate, auth0_tenant):
        assert authenticate(auth0_tenant.token(sub=None))[0] is None

    def test_missing_kid_is_rejected_without_fetching_keys(self, authenticate, auth0_tenant):
        assert authenticate(auth0_tenant.token(kid=None))[0] is None
        assert auth0_tenant.jwks_response.call_count == 0

    def test_unknown_kid(self, authenticate, auth0_tenant):
        assert authenticate(auth0_tenant.token(kid="some-other-key"))[0] is None

    def test_signed_by_another_key(self, authenticate, auth0_tenant, other_private_key):
        assert authenticate(auth0_tenant.token(key=other_private_key))[0] is None

    def test_tampered_payload(self, authenticate, auth0_tenant):
        header, _, signature = auth0_tenant.token("auth0|bob").split(".")
        forged_payload = jwt.utils.base64url_encode(b'{"sub": "auth0|admin"}').decode()

        assert authenticate(f"{header}.{forged_payload}.{signature}")[0] is None

    def test_hmac_signed_token_is_rejected(self, authenticate, auth0_tenant):
        token = auth0_tenant.token(key="a-shared-secret-of-sufficient-length!!", algorithm="HS256")

        assert authenticate(token)[0] is None

    def test_unsigned_token_is_rejected(self, authenticate, auth0_tenant):
        token = jwt.encode(auth0_tenant.claims(), None, algorithm="none", headers={"kid": auth0_tenant.kid})

        assert authenticate(token)[0] is None

    def test_non_rsa_key_in_jwks(self, authenticate, auth0_tenant, http_mock):
        http_mock.replace(
            "GET", auth0_tenant.jwks_url, json={"keys": [{"kty": "EC", "kid": auth0_tenant.kid, "crv": "P-256"}]}
        )

        assert authenticate(auth0_tenant.token())[0] is None

    def test_garbage_that_looks_like_a_jwt(self, authenticate, auth0_tenant):
        assert authenticate("eyJhbGciOi.not-base64!.sig")[0] is None


class TestJwksCache:
    def test_fetched_once_and_shared_across_instances(self, authenticate, auth0_tenant):
        for sub in ("auth0|a", "auth0|b", "auth0|a"):
            assert authenticate(auth0_tenant.token(sub))[0] is not None

        assert auth0_tenant.jwks_response.call_count == 1

    def test_fetch_uses_a_timeout(self, authenticate, auth0_tenant, http_mock):
        authenticate(auth0_tenant.token())

        (call,) = http_mock.calls
        assert call.request.url == auth0_tenant.jwks_url
        assert call.request.req_kwargs["timeout"] == 5

    @pytest.mark.parametrize(
        "failure",
        [
            {"status": 500},
            {"status": 404},
            {"body": requests.Timeout("timed out")},
            {"body": requests.ConnectionError("refused")},
            {"body": "not json"},
        ],
        ids=["500", "404", "timeout", "connection-error", "malformed"],
    )
    def test_failed_fetch_rejects_the_token_and_is_retried_next_time(
        self, authenticate, auth0_tenant, http_mock, rsa_private_key, failure
    ):
        http_mock.replace("GET", auth0_tenant.jwks_url, **failure)
        assert authenticate(auth0_tenant.token())[0] is None
        assert auth0_tenant.domain not in auth_module._jwks_cache

        http_mock.replace("GET", auth0_tenant.jwks_url, json={"keys": [public_jwk(rsa_private_key, auth0_tenant.kid)]})
        assert authenticate(auth0_tenant.token())[0] is not None

    def test_cached_per_domain(self, settings, authenticate, auth0_tenant, http_mock, rsa_private_key):
        authenticate(auth0_tenant.token())

        other_domain = "other-tenant.eu.auth0.com"
        other_jwks = http_mock.get(
            f"https://{other_domain}/.well-known/jwks.json",
            json={"keys": [public_jwk(rsa_private_key, auth0_tenant.kid)]},
        )
        settings.AUTH0_DOMAIN = other_domain
        authenticate(auth0_tenant.token(iss=f"https://{other_domain}/"))

        assert (auth0_tenant.jwks_response.call_count, other_jwks.call_count) == (1, 1)
        assert set(auth_module._jwks_cache) == {auth0_tenant.domain, other_domain}

    @pytest.mark.xfail(
        strict=True,
        reason="The JWKS is cached for the life of the process, so after Auth0 rotates its signing key, "
        "tokens with the new kid are rejected until the server restarts.",
    )
    def test_rotated_signing_key_is_picked_up(self, authenticate, auth0_tenant, http_mock, other_private_key):
        assert authenticate(auth0_tenant.token())[0] is not None  # caches the current JWKS

        http_mock.replace("GET", auth0_tenant.jwks_url, json={"keys": [public_jwk(other_private_key, "rotated-key")]})

        assert authenticate(auth0_tenant.token(key=other_private_key, kid="rotated-key"))[0] is not None


# --- Mock mode (local development) ---


class TestMockMode:
    def test_unsigned_claims_are_trusted(self, authenticate, make_auth0_token):
        user, _ = authenticate(make_auth0_token("auth0|dev", email="dev@example.com"))

        assert (user.username, user.email) == ("auth0|dev", "dev@example.com")

    def test_without_a_domain_mock_mode_is_used_even_if_disabled(self, settings, authenticate, make_auth0_token):
        # Documented in README_DEPLOY.md: production must set AUTH0_DOMAIN and AUTH0_MOCK=0.
        settings.AUTH0_MOCK = False
        settings.AUTH0_DOMAIN = ""

        assert authenticate(make_auth0_token("auth0|dev"))[0] is not None

    def test_mock_mode_off_rejects_unsigned_tokens(self, authenticate, auth0_tenant, make_auth0_token, settings):
        token = make_auth0_token("auth0|dev")
        settings.AUTH0_MOCK = False  # make_auth0_token turned it on

        assert authenticate(token)[0] is None


# --- Local accounts vs. Auth0 subs ---


class TestAccountCollision:
    def test_auth0_token_cannot_open_a_locally_registered_account(self, authenticate, auth0_tenant):
        # An account registered with a password under what is (or later becomes) an Auth0 sub.
        squatter = users.create_user("auth0|victim", "attacker-password")

        user, request = authenticate(auth0_tenant.token("auth0|victim"))

        assert user is None
        assert not hasattr(request, "auth_token")
        assert users.get_user("auth0|victim") == squatter

    def test_rejected_through_the_api_too(self, firestore_db, auth0_tenant):
        users.create_user("auth0|victim", "attacker-password")

        assert ApiClient(auth0_tenant.token("auth0|victim")).get("/auth/me").status_code == 401

    def test_auth0_account_cannot_be_used_with_a_password(self, firestore_db, auth0_tenant, authenticate):
        user, _ = authenticate(auth0_tenant.token("auth0|bob"))

        response = ApiClient().post("/auth/login", {"username": "auth0|bob", "password": ""})

        assert user is not None
        assert response.status_code == 401

    def test_local_registration_cannot_claim_an_auth0_sub(self, firestore_db, auth0_tenant):
        response = ApiClient().post("/auth/register", {"username": "auth0|bob", "password": "pw"})

        assert response.status_code == 422
        assert users.get_user("auth0|bob") is None
