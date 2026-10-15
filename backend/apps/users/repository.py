"""
Firestore persistence for users, their profile, and API tokens.

Layout:
    users/{doc_id(username)}   account + profile fields (the old User and UserProfile)
    auth_tokens/{key}          token -> user lookup (the old AuthToken)
"""
import secrets
from dataclasses import asdict, dataclass, fields
from typing import Optional

from django.contrib.auth.hashers import check_password, make_password
from google.cloud import firestore

from services.firestore import allocate_id, doc_id, get_client

USERS = "users"
AUTH_TOKENS = "auth_tokens"


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

    @classmethod
    def from_dict(cls, data: dict) -> "User":
        names = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in data.items() if k in names})


def _users():
    return get_client().collection(USERS)


def _tokens():
    return get_client().collection(AUTH_TOKENS)


def get_user(username: str) -> Optional[User]:
    snapshot = _users().document(doc_id(username)).get()
    return User.from_dict(snapshot.to_dict()) if snapshot.exists else None


def create_user(username: str, password: Optional[str] = None, **extra) -> Optional[User]:
    """Create a user. Returns None if the username is already taken."""
    user, created = _get_or_create_user(username, password, extra)
    return user if created else None


def get_or_create_user(username: str, **defaults):
    """Returns (user, created). `defaults` are only applied when the user is created."""
    return _get_or_create_user(username, None, defaults)


def _get_or_create_user(username, password, extra):
    client = get_client()
    ref = _users().document(doc_id(username))

    @firestore.transactional
    def get_or_create(transaction):
        snapshot = ref.get(transaction=transaction)
        if snapshot.exists:
            return User.from_dict(snapshot.to_dict()), False

        user = User(
            id=allocate_id(transaction, USERS),
            username=username,
            password=make_password(password),
            **extra,
        )
        transaction.set(ref, {**asdict(user), "created_at": firestore.SERVER_TIMESTAMP})
        return user, True

    return get_or_create(client.transaction())


# Identity and credential fields are only written on creation / token issue, never by save_user().
_PROTECTED_FIELDS = ("id", "username", "password", "token")


def save_user(user: User):
    """Persist `user`'s account and profile fields."""
    data = {k: v for k, v in asdict(user).items() if k not in _PROTECTED_FIELDS}
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
        transaction.set(_tokens().document(key), {"username": user.username, "created_at": firestore.SERVER_TIMESTAMP})
        transaction.update(user_ref, {"token": key})
        return key

    user.token = get_or_create(client.transaction())
    return user.token


def get_user_by_token(key: str) -> Optional[User]:
    if not key:
        return None
    snapshot = _tokens().document(doc_id(key)).get()
    if not snapshot.exists:
        return None
    return get_user(snapshot.get("username"))
