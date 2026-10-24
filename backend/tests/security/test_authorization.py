"""
Authorization: who may call each operation, and that one user can never read or change another's
data. Bookmarks live under the user's own document (users/{user}/saved_places), and the profile
routes act on the token's user, so every check here is "Bob's data is unchanged and unseen".

The operation lists are checked against the served OpenAPI schema, so a new route fails here until
it's classified (public or signed-in) and, if it touches a user's data, added to the cross-user
checks.
"""

import pytest
from django.test import Client

from apps.places import repository as places
from apps.users import repository as users
from tests.conftest import ApiClient

# Operations anyone may call. Every other operation needs a signed-in user.
PUBLIC_OPERATIONS = {
    ("post", "/api/auth/login"),
    ("post", "/api/auth/register"),
}

# Operations that read or change the signed-in user's own data, each with a valid request. The
# cross-user tests below run every one of them as Alice against data Bob also has.
USER_DATA_OPERATIONS = {
    ("get", "/api/auth/me"): None,
    ("put", "/api/auth/me"): {"first_name": "Mallory", "home_address": "1 Evil St", "calendar_subscription_url": ""},
    ("post", "/api/places/bookmark"): {"tomtom_id": "shared", "custom_name": "Alice's name"},
    ("get", "/api/places/bookmarks"): None,
    ("delete", "/api/places/bookmarks/{tomtom_id}"): None,
    ("patch", "/api/places/bookmarks/{tomtom_id}/pin"): {"is_pinned": True},
    ("patch", "/api/places/bookmarks/{tomtom_id}/check-it-out"): {"is_check_it_out": True},
    ("patch", "/api/places/bookmarks/{tomtom_id}/graphic"): {"icon": "skull", "color": "#000000", "custom_name": "X"},
    ("patch", "/api/places/bookmarks/{tomtom_id}/visit-length"): {"visit_length": 999},
}

BOB_PROFILE = {
    "first_name": "Bob",
    "home_address": "2 Bob Rd",
    "home_lat": 51.5,
    "home_lng": -0.12,
    "calendar_subscription_url": "https://calendar.example.com/bob-private.ics",
}


def _operations():
    schema = Client().get("/api/openapi.json").json()
    return {(method, path): op for path, ops in schema["paths"].items() for method, op in ops.items()}


def _call(client: ApiClient, method: str, path: str, payload, tomtom_id="shared"):
    path = path.removeprefix("/api").replace("{tomtom_id}", tomtom_id)
    if method == "get":
        return client.get(path)
    if method == "delete":
        return client.delete(path)
    return getattr(client, method)(path, payload)


# --- Which operations need a signed-in user ---


def test_every_operation_is_classified():
    operations = set(_operations())

    assert operations >= PUBLIC_OPERATIONS
    assert set(USER_DATA_OPERATIONS) <= operations


def test_only_login_and_register_are_public():
    for (method, path), operation in _operations().items():
        if (method, path) in PUBLIC_OPERATIONS:
            assert "security" not in operation, f"{method.upper()} {path}"
        else:
            assert operation.get("security") == [{"GlobalAuth": []}], f"{method.upper()} {path} has no auth"


@pytest.mark.parametrize("token", [None, "not-a-real-token"], ids=["no-credentials", "unknown-token"])
def test_every_signed_in_operation_rejects_anonymous_callers(firestore_db, http_mock, token):
    """Without a valid token, each one is 401 before it reads its input or calls out."""
    for method, path in set(_operations()) - PUBLIC_OPERATIONS:
        response = _call(ApiClient(token), method, path, payload={})

        assert response.status_code == 401, f"{method.upper()} {path}: {response.status_code}"
    assert len(http_mock.calls) == 0


# --- One user can't reach another's data ---


@pytest.fixture
def alice(make_user):
    user = make_user("alice")
    return ApiClient(users.get_or_create_token(user), user)


@pytest.fixture
def bob(make_user, make_place, make_bookmark):
    """Bob, with a profile, a bookmark of a place Alice also saved ("shared") and one she didn't."""
    user = make_user("bob", email="bob@example.com")
    for field, value in BOB_PROFILE.items():
        setattr(user, field, value)
    users.save_user(user)
    users.get_or_create_token(user)
    for tomtom_id in ("shared", "bobs-only"):
        make_bookmark(
            user,
            make_place(tomtom_id),
            custom_name="Bob's name",
            is_pinned=False,
            icon="star",
            color="#FF0000",
            average_visit_length=30,
        )
    return users.get_user("bob")


@pytest.fixture
def alice_shares_a_place(alice, bob, make_bookmark):
    make_bookmark(alice.user, places.get_place("shared"))


def _bobs_data(bob) -> dict:
    """Everything Bob has: his profile and his bookmarks."""
    user = users.get_user("bob")
    profile = {field: getattr(user, field) for field in (*BOB_PROFILE, "email", "token", "password")}
    bookmarks = {b["place"]["tomtom_id"]: b for b in places.list_saved_places(bob)}
    return {"profile": profile, "bookmarks": bookmarks}


def _leaks(response, bob) -> list[str]:
    """Bob's values that appear anywhere in a response to Alice."""
    secrets = [bob.token, bob.email, "Bob's name", *(str(v) for v in BOB_PROFILE.values())]
    body = response.content.decode()
    return [value for value in secrets if value in body]


OPERATION_IDS = [f"{m.upper()} {p.removeprefix('/api')}" for m, p in USER_DATA_OPERATIONS]


@pytest.mark.usefixtures("alice_shares_a_place")
@pytest.mark.parametrize("method, path", USER_DATA_OPERATIONS, ids=OPERATION_IDS)
def test_acting_on_a_place_both_saved_leaves_bobs_data_alone(http_mock, alice, bob, method, path):
    before = _bobs_data(bob)

    response = _call(alice, method, path, USER_DATA_OPERATIONS[method, path])

    assert response.status_code in (200, 204), response.content
    assert _bobs_data(bob) == before
    assert _leaks(response, bob) == []


@pytest.mark.parametrize(
    "method, path", [k for k in USER_DATA_OPERATIONS if "{tomtom_id}" in k[1]], ids=lambda v: str(v)
)
def test_bobs_bookmark_is_not_found_for_alice(http_mock, alice, bob, method, path):
    before = _bobs_data(bob)

    response = _call(alice, method, path, USER_DATA_OPERATIONS[method, path], tomtom_id="bobs-only")

    assert response.status_code == 404
    assert _bobs_data(bob) == before
    assert places.get_saved_place(alice.user, places.get_place("bobs-only")) is None


def test_bookmark_routes_are_all_covered():
    """Every route that takes a bookmark's place ID is in the cross-user checks."""
    routes = {k for k in _operations() if k[1].startswith("/api/places/bookmark")}

    assert routes <= set(USER_DATA_OPERATIONS)


def test_profile_reads_only_the_callers_account(alice, bob):
    data = alice.get("/auth/me").json()

    assert (data["username"], data["token"]) == ("alice", alice.token)
    assert _leaks(alice.get("/auth/me"), bob) == []


@pytest.mark.parametrize("field", ["username", "id", "token", "email", "password"])
def test_profile_update_cannot_pick_another_account(alice, bob, field):
    """No body field picks the account or changes credentials: unknown fields are ignored."""
    before = _bobs_data(bob)
    value = {"username": "bob", "id": bob.id, "token": bob.token, "email": bob.email, "password": "pw"}[field]

    response = alice.put("/auth/me", {field: value, "first_name": "Mallory"})

    assert response.status_code == 200
    assert response.json()["username"] == "alice"
    assert _bobs_data(bob) == before
    after = users.get_user("alice")
    assert (after.first_name, after.id, after.token, after.email) == ("Mallory", alice.user.id, alice.token, "")
    assert not after.check_password("pw")


def test_bookmark_list_only_has_the_callers_bookmarks(alice, bob, alice_shares_a_place):
    response = alice.get("/places/bookmarks")

    assert [b["place"]["tomtom_id"] for b in response.json()] == ["shared"]
    assert _leaks(response, bob) == []


def test_a_bookmark_of_the_same_place_is_separate(alice, bob, alice_shares_a_place):
    alice.patch("/places/bookmarks/shared/graphic", {"custom_name": "Alice's"})
    alice.delete("/places/bookmarks/shared")

    assert _bobs_data(bob)["bookmarks"]["shared"]["custom_name"] == "Bob's name"


def test_bobs_token_only_opens_bobs_account(alice, bob):
    assert ApiClient(bob.token).get("/auth/me").json()["username"] == "bob"
    assert ApiClient(bob.token[:-1]).get("/auth/me").status_code == 401
    assert ApiClient(bob.token.upper()).get("/auth/me").status_code == 401
