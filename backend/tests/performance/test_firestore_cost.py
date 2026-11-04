"""
Firestore cost per request: the document reads and writes each operation makes (what Firestore
bills) and its round trips (what the user waits for), counted by the `firestore_usage` fixture.

`EXPECTED_COSTS` pins the cost of one typical request to every operation in the served schema, so
a new route fails until it has an entry, and any change in what a route reads shows up here. The
scaling tests check that list routes make a fixed number of round trips however much data there is
(no N+1 reads), and that their cost guards hold.

When a change means a route really should cost more (or, better, less), update its entry.
"""

import re

import pytest
from django.test import Client

from apps.places import repository as places
from apps.users import repository as users
from tests import factories
from tests.conftest import TOMTOM_BASE, ApiClient
from tests.performance.conftest import Cost

POI_SEARCH_URL = re.compile(rf"{re.escape(TOMTOM_BASE)}/poiSearch/.+\.json")
CALENDAR_URL = "https://calendar.example.com/feed.ics"


@pytest.fixture
def seeded(make_user, make_place, make_bookmark, tomtom):
    """
    Alice, signed in with a local token and with two of the three places bookmarked. The places are
    all at the same spot. Creating them reserves each counter's first block of IDs, so the measured
    requests never pay for that (one write per ID_BLOCK_SIZE creates).
    """
    alice = make_user("alice")
    client = ApiClient(users.get_or_create_token(alice), alice)
    pizza = [make_place(f"pizza-{i}", name=f"Pizza {i}") for i in range(3)]
    for place in pizza[:2]:
        make_bookmark(alice, place)
    tomtom.get(POI_SEARCH_URL, json={"results": []})
    tomtom.get(CALENDAR_URL, body="BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n", content_type="text/calendar")
    return client


# One typical request to each operation, as Alice in `seeded`, and what it costs. Authenticating
# a request with a local token is one query (one read, one round trip), included in each.
EXPECTED_COSTS = {
    ("post", "/api/auth/login"): (
        {"username": "alice", "password": "password"},
        Cost(reads=1, round_trips=1),
    ),
    # Look up the name, create the account, then issue its token in a transaction.
    ("post", "/api/auth/register"): (
        {"username": "bob", "password": "bob-password"},
        Cost(reads=2, writes=2, round_trips=5),
    ),
    ("get", "/api/auth/me"): (None, Cost(reads=1, round_trips=1)),
    ("put", "/api/auth/me"): ({"first_name": "Al"}, Cost(reads=1, writes=1, round_trips=2)),
    # TomTom returns nothing here, so the reads are the three local matches.
    ("get", "/api/places/search"): ({"query": "pizza"}, Cost(reads=4, round_trips=2)),
    # An upsert in a transaction: begin, read, commit.
    ("post", "/api/places/"): (factories.place_data("new-place"), Cost(reads=2, writes=1, round_trips=4)),
    # Read the place, then get-or-create the bookmark in a transaction.
    ("post", "/api/places/bookmark"): ({"tomtom_id": "pizza-2"}, Cost(reads=3, writes=1, round_trips=5)),
    # The bookmarks, then their places in one batched lookup.
    ("get", "/api/places/bookmarks"): (None, Cost(reads=5, round_trips=3)),
    # A delete with an exists precondition: no read.
    ("delete", "/api/places/bookmarks/{tomtom_id}"): (None, Cost(reads=1, writes=1, round_trips=2)),
    ("patch", "/api/places/bookmarks/{tomtom_id}/pin"): ({"is_pinned": True}, Cost(reads=3, writes=1, round_trips=5)),
    ("patch", "/api/places/bookmarks/{tomtom_id}/check-it-out"): (
        {"is_check_it_out": True},
        Cost(reads=3, writes=1, round_trips=5),
    ),
    ("patch", "/api/places/bookmarks/{tomtom_id}/graphic"): ({"icon": "star"}, Cost(reads=3, writes=1, round_trips=5)),
    ("patch", "/api/places/bookmarks/{tomtom_id}/visit-length"): (
        {"visit_length": 30},
        Cost(reads=3, writes=1, round_trips=5),
    ),
    # A 5 km radius here is one geohash cell, so one query.
    ("get", "/api/places/nearby"): ({"lat": 40.7128, "lng": -74.0060}, Cost(reads=4, round_trips=2)),
    # Without a location: the most recent places, at most 10.
    ("get", "/api/places/suggestions"): (None, Cost(reads=4, round_trips=2)),
    ("get", "/api/places/{tomtom_id}"): (None, Cost(reads=2, round_trips=2)),
    ("get", "/api/calendar/proxy"): ({"url": CALENDAR_URL}, Cost(reads=1, round_trips=1)),
}


def _operations():
    schema = Client().get("/api/openapi.json").json()
    return {(method, path) for path, ops in schema["paths"].items() for method in ops}


def _call(client: ApiClient, method: str, path: str, payload, tomtom_id="pizza-0"):
    path = path.removeprefix("/api").replace("{tomtom_id}", tomtom_id)
    if method == "get":
        return client.get(path, **(payload or {}))
    if method == "delete":
        return client.delete(path)
    return getattr(client, method)(path, payload)


def test_every_operation_has_an_expected_cost():
    assert set(EXPECTED_COSTS) == _operations()


@pytest.mark.parametrize("operation", EXPECTED_COSTS, ids=[f"{m.upper()} {p}" for m, p in EXPECTED_COSTS])
def test_cost_per_request(seeded, firestore_usage, operation):
    method, path = operation
    payload, expected = EXPECTED_COSTS[operation]
    client = ApiClient() if path in ("/api/auth/login", "/api/auth/register") else seeded

    with firestore_usage.measure():
        response = _call(client, method, path, payload)

    assert response.status_code in (200, 204), response.content
    assert firestore_usage.cost == expected


def test_auth0_sign_in_costs_one_read_once_the_account_exists(auth0_client, firestore_usage):
    with firestore_usage.measure():
        response = auth0_client.get("/auth/me")

    assert response.status_code == 200
    assert firestore_usage.cost == Cost(reads=1, round_trips=1)


# --- Scaling: list routes make a fixed number of round trips (no N+1) ---


@pytest.mark.parametrize("count", [1, 12])
def test_bookmarks_read_each_bookmark_and_place_once_in_fixed_round_trips(
    make_user, make_place, make_bookmark, firestore_usage, count
):
    alice = make_user("alice")
    client = ApiClient(users.get_or_create_token(alice), alice)
    for i in range(count):
        make_bookmark(alice, make_place(f"place-{i}"))

    with firestore_usage.measure():
        response = client.get("/places/bookmarks")

    assert len(response.json()) == count
    # Auth, the bookmarks, and one batched lookup of their places.
    assert firestore_usage.cost == Cost(reads=1 + 2 * count, round_trips=3)


@pytest.mark.parametrize("count", [1, 12])
def test_nearby_round_trips_depend_on_the_radius_not_the_places(make_user, make_place, firestore_usage, count):
    alice = make_user("alice")
    client = ApiClient(users.get_or_create_token(alice), alice)
    for i in range(count):
        make_place(f"place-{i}", lat=40.7128 + i * 0.02, lng=-74.0060)

    with firestore_usage.measure():
        response = client.get("/places/nearby", lat=40.7128, lng=-74.0060, radius_km=50)

    assert len(response.json()) == count
    # Auth, then one query per geohash cell covering the circle (4 at this radius), run concurrently.
    assert firestore_usage.cost.round_trips == 1 + 4


def test_suggestions_without_a_location_read_at_most_ten_places(make_user, make_place, firestore_usage):
    alice = make_user("alice")
    client = ApiClient(users.get_or_create_token(alice), alice)
    for i in range(15):
        make_place(f"place-{i}")

    with firestore_usage.measure():
        response = client.get("/places/suggestions")

    assert len(response.json()) == 10
    assert firestore_usage.cost == Cost(reads=1 + 10, round_trips=2)


def test_search_stops_reading_at_the_candidate_limit(make_user, make_place, tomtom, firestore_usage, monkeypatch):
    # The real limits (100 a page, 2,000 in all) would need thousands of places; scale them down.
    monkeypatch.setattr(places, "_SEARCH_PAGE_SIZE", 5)
    monkeypatch.setattr(places, "_MAX_SEARCH_CANDIDATES", 12)
    alice = make_user("alice")
    client = ApiClient(users.get_or_create_token(alice), alice)
    for i in range(20):
        make_place(f"place-{i}", name=f"Pizza {i}")
    tomtom.get(POI_SEARCH_URL, json={"results": []})

    with firestore_usage.measure():
        response = client.get("/places/search", query="pizza")

    assert len(response.json()) == 12
    # Auth, then pages of 5, 5 and 2.
    assert firestore_usage.cost == Cost(reads=1 + 12, round_trips=1 + 3)
