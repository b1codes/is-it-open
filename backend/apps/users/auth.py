import threading
import time
from dataclasses import dataclass

import jwt
import requests
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicKey
from django.conf import settings
from jwt.algorithms import RSAAlgorithm
from ninja.errors import HttpError
from ninja.security import HttpBearer

from services.firestore import InvalidDocumentKey

from . import repository

# Each Auth0 tenant's JWKS (its token signing keys), by domain, so it isn't fetched on every request.
# It's refetched when a token's `kid` isn't in it, since that's how a key Auth0 has rotated to first
# shows up, and once it's JWKS_MAX_AGE old, so a key Auth0 has revoked stops being trusted. Fetches
# happen at most once per JWKS_MIN_REFETCH_INTERVAL, also while the first one keeps failing, so tokens
# with made-up kids can't make the server hammer Auth0 or tie up its workers waiting on it.
JWKS_MAX_AGE = 60 * 60
JWKS_MIN_REFETCH_INTERVAL = 60
# Auth0 publishes a key before it signs with it, so a token issued before the cached JWKS was fetched
# was signed by a key in it, unless Auth0 has revoked that key since. Its unknown kid is rejected
# without a refetch. This margin allows for clock skew and a JWKS cached on Auth0's side; a token issued
# within it of the fetch, or after it, may have a key Auth0 has just rotated to.
JWKS_ISSUED_BEFORE_FETCH_MARGIN = 5 * 60


@dataclass
class _CachedJwks:
    jwks: dict
    fetched_at: float  # time.monotonic() of the fetch that returned `jwks`
    fetched_at_wall: float  # and its time.time(), to compare with tokens' `iat`
    refetched_at: float | None = None  # of the last refetch, whether or not it succeeded


class JwksUnavailable(Exception):
    """The tenant's JWKS can't be fetched, so a token can be neither accepted nor rejected."""


_jwks_cache: dict[str, _CachedJwks] = {}
# When a domain with no cached JWKS last failed to fetch it (or claimed the retry), by domain.
_jwks_failed_at: dict[str, float] = {}
_jwks_lock = threading.Lock()


def _find_key(jwks: dict, kid: str) -> dict | None:
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return key
    return None


class GlobalAuth(HttpBearer):
    def authenticate(self, request, token):
        if token.startswith("eyJ") and len(token.split(".")) == 3:
            # Validate via Auth0. If Auth0 can't be reached, the token may well be valid: a 401 would
            # tell the app to sign the user out, so this answers 503 and the app keeps its session.
            try:
                user_data = self.verify_auth0_token(token)
            except JwksUnavailable:
                raise HttpError(503, "Sign-in can't be checked right now. Try again shortly.") from None
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
            cached, fetched = self.get_jwks(domain)

            # 3. Find matching key. An unknown kid may be a key Auth0 rotated to since the JWKS was
            # fetched, unless it was fetched for this request or the token was issued before it was.
            # Rejecting those outright makes them a 401, not a 503 while the refetch is throttled or
            # failing, so the app signs out a token whose key Auth0 revoked, or that isn't Auth0's.
            key = _find_key(cached.jwks, kid)
            if key is None and not fetched and not _issued_before(token, cached.fetched_at_wall):
                key = _find_key(self.get_jwks(domain, refetch=True)[0].jwks, kid)
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
        except JwksUnavailable:
            raise
        except Exception:
            return None

    def get_jwks(self, domain, *, refetch=False) -> tuple[_CachedJwks, bool]:
        """
        The tenant's JWKS, and whether this call fetched it: the cached copy, unless `refetch` asks
        for a new one or it's JWKS_MAX_AGE old, and the last refetch was at least
        JWKS_MIN_REFETCH_INTERVAL ago.

        Raises JwksUnavailable if there's no cached copy and the fetch fails or failed within the
        interval, or if `refetch` asked for one and it fails or is throttled: the token's kid isn't
        cached, and it may be a key Auth0 rotated to after the last refetch, so it can't be rejected.
        """
        now, now_wall = time.monotonic(), time.time()
        with _jwks_lock:
            cached = _jwks_cache.get(domain)
            if cached is not None:
                wanted = refetch or now - cached.fetched_at >= JWKS_MAX_AGE
                too_soon = cached.refetched_at is not None and now - cached.refetched_at < JWKS_MIN_REFETCH_INTERVAL
                if not wanted:
                    return cached, False
                if too_soon:
                    if refetch:
                        raise JwksUnavailable(domain)
                    return cached, False
                # Claim the refetch, so requests meanwhile use the cached copy rather than fetching too.
                cached.refetched_at = now
            elif domain in _jwks_failed_at:
                if now - _jwks_failed_at[domain] < JWKS_MIN_REFETCH_INTERVAL:
                    raise JwksUnavailable(domain)
                # Claim the retry, so requests meanwhile answer 503 rather than waiting on Auth0 too.
                _jwks_failed_at[domain] = now

        jwks = _fetch_jwks(domain)
        if jwks is None:
            if cached is None:
                with _jwks_lock:
                    _jwks_failed_at[domain] = time.monotonic()
                raise JwksUnavailable(domain)
            # Past JWKS_MAX_AGE, keep using the keys we have until the tenant can be reached.
            if refetch:
                raise JwksUnavailable(domain)
            return cached, False
        with _jwks_lock:
            refetched_at = cached.refetched_at if cached is not None else None
            fresh = _CachedJwks(jwks, fetched_at=now, fetched_at_wall=now_wall, refetched_at=refetched_at)
            _jwks_cache[domain] = fresh
            _jwks_failed_at.pop(domain, None)
        return fresh, True


def _issued_before(token, fetched_at_wall: float) -> bool:
    """Whether the token's (unverified) `iat` is over JWKS_ISSUED_BEFORE_FETCH_MARGIN before the fetch.

    A forged `iat` gains nothing: a later one only turns a 401 into a 503, and an earlier one a 503
    into a 401. A token without one counts as issued now.
    """
    iat = jwt.decode(token, options={"verify_signature": False}).get("iat")
    if not isinstance(iat, int | float) or isinstance(iat, bool):
        return False
    return iat < fetched_at_wall - JWKS_ISSUED_BEFORE_FETCH_MARGIN


def _fetch_jwks(domain) -> dict | None:
    try:
        response = requests.get(f"https://{domain}/.well-known/jwks.json", timeout=5)
        if response.status_code == 200:
            jwks = response.json()
            if isinstance(jwks, dict):
                return jwks
    # An unreachable tenant is retried by the next request.
    except Exception:  # nosec B110
        pass
    return None
