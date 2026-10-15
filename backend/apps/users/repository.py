"""
Firestore persistence for users, their profile, and API tokens.

Layout:
    users/{doc_id(username)}   account + profile fields (the old User and UserProfile), plus the
                               API token (the old AuthToken), looked up with an equality query

Lookups by username or token return None for keys that can't be stored (see
services.firestore.doc_id); create_user() raises InvalidDocumentKey for them.
"""
import secrets
from dataclasses import asdict, dataclass, fields
from typing import Optional

from django.contrib.auth.hashers import check_password, is_password_usable, make_password
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from services.firestore import InvalidDocumentKey, allocate_id, doc_id, get_client

USERS = "users"


@dataclass
class User:
    id: int
    username: str
    email: str = ""
    first_name: str = ""
    last_name: str = ""
    password: str = ""
    token: Optional[str] = None

    home_address: str = ""
    home_street: str = ""
    home_city: str = ""
    home_state: str = ""
    home_zip: str = ""
    home_lat: Optional[float] = None
    home_lng: Optional[float] = None

    work_address: str = ""
    work_street: str = ""
    work_city: str = ""
    work_state: str = ""
    work_zip: str = ""
    work_lat: Optional[float] = None
    work_lng: Optional[float] = None

    use_current_location: bool = False
    calendar_subscription_url: str = ""

    @property
    def doc_id(self) -> str:
        return doc_id(self.username)

    def check_password(self, raw_password: str) -> bool:
        return check_password(raw_password, self.password)

    def has_usable_password(self) -> bool:
        """False for accounts created by Auth0 sign-in, which can't log in with a password."""
        return is_password_usable(self.password)

    @classmethod
    def from_dict(cls, data: dict) -> "User":
        names = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in data.items() if k in names})


def _users():
    return get_client().collection(USERS)


def user_document(user: User, created_at=firestore.SERVER_TIMESTAMP) -> dict:
    """The users/{doc} document for `user`. Shared with the Postgres import so the shapes match."""
    return {**asdict(user), "created_at": created_at}


def get_user(username: str) -> Optional[User]:
    try:
        ref = _users().document(doc_id(username))
    except InvalidDocumentKey:
        return None
    snapshot = ref.get()
    return User.from_dict(snapshot.to_dict()) if snapshot.exists else None


def create_user(username: str, password: Optional[str] = None, **extra) -> Optional[User]:
    """
    Create a user. Returns None if the username is already taken.
    Raises InvalidDocumentKey if the username can't be stored.
    """
    user, created = _get_or_create_user(username, password, extra)
    return user if created else None


def get_or_create_user(username: str, **defaults):
    """
    Returns (user, created). `defaults` are only applied when the user is created.
    Raises InvalidDocumentKey if the username can't be stored.
    """
    return _get_or_create_user(username, None, defaults)


def _get_or_create_user(username, password, extra):
    client = get_client()
    ref = _users().document(doc_id(username))

    # Almost every call (e.g. each Auth0-authenticated request) is for an existing user, so try a
    # plain read first and only pay for a transaction when the user may need creating.
    snapshot = ref.get()
    if snapshot.exists:
        return User.from_dict(snapshot.to_dict()), False

    @firestore.transactional
    def get_or_create(transaction):
        snapshot = ref.get(transaction=transaction)
        if snapshot.exists:
            return User.from_dict(snapshot.to_dict()), False

        user = User(
            id=allocate_id(USERS),
            username=username,
            password=make_password(password),
            **extra,
        )
        transaction.set(ref, user_document(user))
        return user, True

    return get_or_create(client.transaction())


# Firestore's limit on an indexed (and so queried) string value, in UTF-8 bytes. Tokens are 40 hex
# characters (Postgres-era ones included).
_MAX_TOKEN_BYTES = 1500

# Identity and credential fields are only written on creation / token issue, never by save_user().
_PROTECTED_FIELDS = ("id", "username", "password", "token")


def save_user(user: User, field_names=None):
    """
    Persist `user`'s account and profile fields, or only those in `field_names`. Passing just the
    fields a request changed keeps concurrent requests that change other fields from undoing
    each other's writes with stale values.
    """
    data = {k: v for k, v in asdict(user).items() if k not in _PROTECTED_FIELDS}
    if field_names is not None:
        unknown = set(field_names) - set(data)
        if unknown:
            raise ValueError(f"Not saveable user fields: {sorted(unknown)}")
        data = {k: data[k] for k in field_names}
    if data:
        _users().document(user.doc_id).update(data)


def authenticate(username: str, password: str) -> Optional[User]:
    user = get_user(username)
    if user and user.check_password(password):
        return user
    return None


def get_or_create_token(user: User) -> str:
    """Return the user's API token, creating one if they don't have one yet."""
    if user.token:
        return user.token

    client = get_client()
    user_ref = _users().document(user.doc_id)

    @firestore.transactional
    def get_or_create(transaction):
        existing = user_ref.get(transaction=transaction).get("token")
        if existing:
            return existing
        key = secrets.token_hex(20)
        transaction.update(user_ref, {"token": key})
        return key

    user.token = get_or_create(client.transaction())
    return user.token


def get_user_by_token(key: str) -> Optional[User]:
    """
    One equality query on `token` (served by the automatic single-field index), so a
    token-authenticated request costs a single round trip.
    """
    if not isinstance(key, str) or not key:
        return None
    try:
        size = len(key.encode("utf-8"))
    except UnicodeEncodeError:
        return None
    if size > _MAX_TOKEN_BYTES:  # Firestore rejects larger query values; no stored token is one
        return None
    query = _users().where(filter=FieldFilter("token", "==", key)).limit(1)
    for snapshot in query.stream():
        return User.from_dict(snapshot.to_dict())
    return None
