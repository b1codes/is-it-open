"""
Forged and invalid Auth0 tokens, sent to the API with real verification on (`auth0_tenant`): each
is a 401, creates no account, and makes no outbound request beyond the tenant's own JWKS.
tests/auth/test_global_auth.py covers the same cases at the GlobalAuth level.
"""

import base64
import datetime
import hashlib
import hmac
import json

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from apps.users import repository as users
from tests.conftest import ApiClient, public_jwk

ATTACKER_JWKS = "https://attacker.example/jwks.json"


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _hs256(header: dict, claims: dict, secret: bytes) -> str:
    """An HS256 token signed by hand; PyJWT refuses to use a public key as an HMAC secret."""
    signing_input = f"{_b64(json.dumps(header).encode())}.{_b64(json.dumps(claims).encode())}"
    signature = hmac.new(secret, signing_input.encode(), hashlib.sha256).digest()
    return f"{signing_input}.{_b64(signature)}"


@pytest.fixture(scope="module")
def attacker_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _epoch(**delta) -> int:
    return int((datetime.datetime.now(datetime.UTC) + datetime.timedelta(**delta)).timestamp())


def forged_tokens(tenant, tenant_key, attacker_key) -> dict[str, str]:
    # Numeric dates, as in a real token, so the hand-built ones below differ from a valid token only where intended.
    claims = tenant.claims("auth0|victim", iat=_epoch(), exp=_epoch(hours=1))
    header, payload, signature = tenant.token("auth0|victim").split(".")
    public_pem = tenant_key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    attacker_jwk = public_jwk(attacker_key, tenant.kid)
    return {
        "alg-none": jwt.encode(claims, "", algorithm="none", headers={"kid": tenant.kid}),
        "alg-none-uppercase": f"{_b64(json.dumps({'alg': 'NONE', 'kid': tenant.kid}).encode())}.{payload}.",
        "signature-stripped": f"{header}.{payload}.",
        "wrong-signature": tenant.token("auth0|victim", key=attacker_key),
        # Algorithm confusion: HMAC with the tenant's public key, which the attacker knows.
        "hs256-with-public-key": _hs256({"alg": "HS256", "kid": tenant.kid}, claims, public_pem),
        "hs256-mock-style": jwt.encode(claims, "not-auth0s-secret-but-long-enough-for-hs", algorithm="HS256"),
        "tampered-payload": f"{header}.{_b64(json.dumps({**claims, 'sub': 'auth0|admin'}).encode())}.{signature}",
        # Key-injection headers: the key must come from the tenant's JWKS, never from the token.
        "embedded-jwk": jwt.encode(
            claims, attacker_key, algorithm="RS256", headers={"kid": tenant.kid, "jwk": attacker_jwk}
        ),
        "jku-header": jwt.encode(
            claims, attacker_key, algorithm="RS256", headers={"kid": tenant.kid, "jku": ATTACKER_JWKS}
        ),
        "x5u-header": jwt.encode(
            claims, attacker_key, algorithm="RS256", headers={"kid": tenant.kid, "x5u": ATTACKER_JWKS}
        ),
        "kid-path-traversal": tenant.token("auth0|victim", key=attacker_key, kid="../../../dev/null"),
        "wrong-issuer": tenant.token("auth0|victim", iss="https://attacker.example/"),
        "wrong-audience": tenant.token("auth0|victim", aud="https://some-other-api.example"),
        "expired": tenant.token("auth0|victim", iat=_epoch(hours=-2), exp=_epoch(hours=-1)),
        "not-yet-valid": tenant.token("auth0|victim", nbf=_epoch(minutes=10)),
        "no-expiry": tenant.token("auth0|victim", exp=None),
        "no-subject": tenant.token(sub=None),
        "empty-subject": tenant.token(sub=""),
    }


TOKEN_CASES = [
    "alg-none",
    "alg-none-uppercase",
    "signature-stripped",
    "wrong-signature",
    "hs256-with-public-key",
    "hs256-mock-style",
    "tampered-payload",
    "embedded-jwk",
    "jku-header",
    "x5u-header",
    "kid-path-traversal",
    "wrong-issuer",
    "wrong-audience",
    "expired",
    "not-yet-valid",
    "no-expiry",
    "no-subject",
    "empty-subject",
]


@pytest.mark.parametrize("case", TOKEN_CASES)
@pytest.mark.parametrize("route", ["/auth/me", "/places/bookmarks"])
def test_forged_or_invalid_token_is_401(
    firestore_db, auth0_tenant, rsa_private_key, attacker_key, http_mock, case, route
):
    token = forged_tokens(auth0_tenant, rsa_private_key, attacker_key)[case]

    response = ApiClient(token).get(route)

    assert response.status_code == 401
    assert response.json() == {"detail": "Unauthorized"}
    assert users.get_user("auth0|victim") is None
    assert users.get_user("auth0|admin") is None
    assert {call.request.url for call in http_mock.calls} <= {auth0_tenant.jwks_url}


def test_every_case_is_checked(auth0_tenant, rsa_private_key, attacker_key):
    assert set(forged_tokens(auth0_tenant, rsa_private_key, attacker_key)) == set(TOKEN_CASES)


def test_the_genuine_token_is_accepted(firestore_db, auth0_tenant):
    """The control: the cases above differ from this token in one way each."""
    response = ApiClient(auth0_tenant.token("auth0|victim")).get("/auth/me")

    assert response.status_code == 200
    assert response.json()["username"] == "auth0|victim"
