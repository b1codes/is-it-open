import threading
import time
from dataclasses import dataclass

import jwt
import requests
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicKey
from django.conf import settings
from jwt.algorithms import RSAAlgorithm
from ninja.security import HttpBearer

from services.firestore import InvalidDocumentKey

from . import repository

# Each Auth0 tenant's JWKS (its token signing keys), by domain, so it isn't fetched on every request.
# It's refetched when a token's `kid` isn't in it, since that's how a key Auth0 has rotated to first
# shows up, and once it's JWKS_MAX_AGE old, so a key Auth0 has revoked stops being trusted. Refetches
# happen at most once per JWKS_MIN_REFETCH_INTERVAL, so tokens with made-up kids can't make the
# server hammer Auth0.
JWKS_MAX_AGE = 60 * 60
JWKS_MIN_REFETCH_INTERVAL = 60


@dataclass
class _CachedJwks:
    jwks: dict
    fetched_at: float  # time.monotonic() of the fetch that returned `jwks`
    refetched_at: float | None = None  # of the last refetch, whether or not it succeeded


_jwks_cache: dict[str, _CachedJwks] = {}
_jwks_lock = threading.Lock()


def _find_key(jwks: dict, kid: str) -> dict | None:
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return key
    return None


class GlobalAuth(HttpBearer):
    def authenticate(self, request, token):
        if token.startswith("eyJ") and len(token.split(".")) == 3:
            # Validate via Auth0
            user_data = self.verify_auth0_token(token)
            if not user_data:
                return None

            sub = user_data.get("sub")
            if not sub:
                return None

            # Find or create user. Username will be set to Auth0 sub.
            # This is a plain read for existing users; a transaction only runs on first sign-in.
            try:
                user, _ = repository.get_or_create_user(
                    sub,
                    email=user_data.get("email") or "",
                    first_name=user_data.get("given_name") or user_data.get("nickname") or user_data.get("name") or "",
                    last_name=user_data.get("family_name") or "",
                )
            except InvalidDocumentKey:
                return None

            # Auth0 sign-in creates accounts without a password. One that has a password was
            # registered locally under this sub, so it belongs to whoever registered it, not to
            # the Auth0 user.
            if user.has_usable_password():
                return None

            # Store the token in the request object if request is present
            if request is not None:
                request.auth_token = token
            return user
        else:
            # Validate via local token store
            user = repository.get_user_by_token(token)
            if user and request is not None:
                request.auth_token = token
            return user

    def verify_auth0_token(self, token):
        domain = getattr(settings, "AUTH0_DOMAIN", "")
        audience = getattr(settings, "AUTH0_AUDIENCE", "")

        if getattr(settings, "AUTH0_MOCK", False):
            try:
                # In mock mode, we decode without verification
                payload = jwt.decode(token, options={"verify_signature": False})
                return payload
            except jwt.DecodeError:
                return None

        # Without a tenant to verify against, no Auth0 token is valid.
        if not domain:
            return None

        # Real verification using Auth0 JWKS
        try:
            # 1. Decode header to get kid
            unverified_header = jwt.get_unverified_header(token)
            kid = unverified_header.get("kid")
            if not kid:
                return None

            # 2. Get JWKS (from cache or API)
            jwks = self.get_jwks(domain)
            if not jwks:
                return None

            # 3. Find matching key. An unknown kid may be a key Auth0 rotated to since the JWKS was fetched.
            key = _find_key(jwks, kid)
            if key is None:
                key = _find_key(self.get_jwks(domain, refetch=True) or {}, kid)
            if key is None:
                return None
            rsa_key = {name: key.get(name) for name in ("kty", "kid", "use", "n", "e")}

            # 4. Construct public key and decode token
            public_key = RSAAlgorithm.from_jwk(rsa_key)
            if not isinstance(public_key, RSAPublicKey):
                return None
            # PyJWT only checks `exp` when it's there; a token without one would never expire.
            payload = jwt.decode(
                token,
                public_key,
                algorithms=["RS256"],
                audience=audience,
                issuer=f"https://{domain}/",
                options={"require": ["exp", "iss", "aud", "sub"]},
            )
            return payload
        except Exception:
            return None

    def get_jwks(self, domain, *, refetch=False):
        """
        The tenant's JWKS: the cached copy, unless `refetch` asks for a new one or it's JWKS_MAX_AGE
        old, and the last refetch was at least JWKS_MIN_REFETCH_INTERVAL ago. None if it has never
        been fetched and can't be.
        """
        now = time.monotonic()
        with _jwks_lock:
            cached = _jwks_cache.get(domain)
            if cached is not None:
                wanted = refetch or now - cached.fetched_at >= JWKS_MAX_AGE
                too_soon = cached.refetched_at is not None and now - cached.refetched_at < JWKS_MIN_REFETCH_INTERVAL
                if not wanted or too_soon:
                    return cached.jwks
                # Claim the refetch, so requests meanwhile use the cached copy rather than fetching too.
                cached.refetched_at = now

        jwks = _fetch_jwks(domain)
        if jwks is None:
            # Keep using the keys we have until the tenant can be reached; with none, the token is rejected.
            return cached.jwks if cached is not None else None
        with _jwks_lock:
            refetched_at = cached.refetched_at if cached is not None else None
            _jwks_cache[domain] = _CachedJwks(jwks, fetched_at=now, refetched_at=refetched_at)
        return jwks


def _fetch_jwks(domain) -> dict | None:
    try:
        response = requests.get(f"https://{domain}/.well-known/jwks.json", timeout=5)
        if response.status_code == 200:
            jwks = response.json()
            if isinstance(jwks, dict):
                return jwks
    # An unreachable tenant rejects the token; the next request tries again.
    except Exception:  # nosec B110
        pass
    return None
