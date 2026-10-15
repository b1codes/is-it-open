import jwt
import requests
from django.conf import settings
from ninja.security import HttpBearer
from jwt.algorithms import RSAAlgorithm

from . import repository

# A simple cache for JWKS to avoid fetching it on every request
_jwks_cache = {}

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
            user, _ = repository.get_or_create_user(
                sub,
                email=user_data.get("email") or "",
                first_name=user_data.get("given_name") or user_data.get("nickname") or user_data.get("name") or "",
                last_name=user_data.get("family_name") or "",
            )

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
        mock = getattr(settings, "AUTH0_MOCK", True) or not domain
        
        if mock:
            try:
                # In mock mode, we decode without verification
                payload = jwt.decode(token, options={"verify_signature": False})
                return payload
            except jwt.DecodeError:
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
                
            # 3. Find matching key
            rsa_key = {}
            for key in jwks.get("keys", []):
                if key.get("kid") == kid:
                    rsa_key = {
                        "kty": key.get("kty"),
                        "kid": key.get("kid"),
                        "use": key.get("use"),
                        "n": key.get("n"),
                        "e": key.get("e")
                    }
                    break
            
            if not rsa_key:
                return None
                
            # 4. Construct public key and decode token
            public_key = RSAAlgorithm.from_jwk(rsa_key)
            payload = jwt.decode(
                token,
                public_key,
                algorithms=["RS256"],
                audience=audience,
                issuer=f"https://{domain}/"
            )
            return payload
        except Exception:
            return None

    def get_jwks(self, domain):
        global _jwks_cache
        if domain in _jwks_cache:
            return _jwks_cache[domain]
            
        try:
            url = f"https://{domain}/.well-known/jwks.json"
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                jwks = response.json()
                _jwks_cache[domain] = jwks
                return jwks
        except Exception:
            pass
        return None
