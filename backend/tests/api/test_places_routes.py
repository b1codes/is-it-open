"""/api/places: search, create, bookmarks (and their pin/check-it-out/graphic/visit-length), nearby,
suggestions, and place details."""

import re

import pytest
from responses import matchers

from apps.places import repository as places
from services.firestore import doc_id, get_client
from tests import factories
from tests.conftest import TOMTOM_BASE, TOMTOM_KEY, ApiClient

POI_SEARCH_URL = re.compile(rf"{re.escape(TOMTOM_BASE)}/poiSearch/.+\.json")
NEARBY_SEARCH_URL = f"{TOMTOM_BASE}/nearbySearch/.json"
PLACE_DETAILS_URL = f"{TOMTOM_BASE}/place.json"

# Every route under /places, with a valid request for each. All need a signed-in user.
PROTECTED_ROUTES = [
    ("get", "/places/search", {"query": "pizza"}),
    ("post", "/places/", factories.place_data("p")),
    ("post", "/places/bookmark", {"tomtom_id": "place-1"}),
    ("get", "/places/bookmarks", None),
    ("delete", "/places/bookmarks/place-1", None),
    ("patch", "/places/bookmarks/place-1/pin", {"is_pinned": True}),
    ("patch", "/places/bookmarks/place-1/check-it-out", {"is_check_it_out": True}),
    ("patch", "/places/bookmarks/place-1/graphic", {"icon": "star"}),
    ("patch", "/places/bookmarks/place-1/visit-length", {"visit_length": 30}),
    ("get", "/places/nearby", {"lat": 40.7, "lng": -74.0}),
    ("get", "/places/suggestions", None),
    ("get", "/places/place-1", None),
    ("get", "/calendar/proxy", {"url": "https://example.com/cal.ics"}),
]


def _call(client, method, path, payload):
    if method == "get":
        return client.get(path, **(payload or {}))
    if method == "delete":
        return client.delete(path)
    return getattr(client, method)(path, payload)


def _field_errors(response):
    assert response.status_code == 422, response.content
    return {err["loc"][-1] for err in response.json()["detail"]}


@pytest.mark.parametrize("method, path, payload", PROTECTED_ROUTES, ids=[f"{m} {p}" for m, p, _ in PROTECTED_ROUTES])
@pytest.mark.parametrize(
    "token",
    [None, "not-a-real-token", "eyJhbGciOiJIUzI1NiJ9.bm90IGpzb24.sig"],
    ids=["no-credentials", "unknown-token", "malformed-jwt"],
)
def test_protected_routes_reject_missing_or_invalid_credentials(
    firestore_db, place, http_mock, method, path, payload, token
):
    response = _call(ApiClient(token), method, path, payload)

    assert response.status_code == 401
    assert response.json() == {"detail": "Unauthorized"}
    assert len(http_mock.calls) == 0  # rejected before any outbound request


# --- GET /places/search ---


class TestSearch:
    def test_merges_tomtom_results_with_local_places(self, auth_client, make_place, tomtom):
        tomtom.get(
            POI_SEARCH_URL,
            json=factories.tomtom_response(
                factories.tomtom_result("tt-1", "Pizza Palace"), factories.tomtom_result("shared", "Pizza Shared")
            ),
            match=[matchers.query_param_matcher({"key": TOMTOM_KEY, "limit": "10", "openingHours": "nextSevenDays"})],
        )
        make_place("shared", name="Pizza Shared")  # also returned by TomTom: listed once
        make_place("local-only", name="Local Pizza")
        make_place("unrelated", name="Burger Barn")

        response = auth_client.get("/places/search", query="pizza")

        assert response.status_code == 200
        assert [p["tomtom_id"] for p in response.json()] == ["tt-1", "shared", "local-only"]

    def test_returns_tomtom_fields(self, auth_client, tomtom):
        result = factories.tomtom_result(
            "tt-1", "Pizza Palace", time_ranges=[factories.tomtom_time_range("2026-10-12", (11, 30), (22, 0))]
        )
        tomtom.get(POI_SEARCH_URL, json=factories.tomtom_response(result))

        (found,) = auth_client.get("/places/search", query="pizza").json()

        assert found == {
            "tomtom_id": "tt-1",
            "name": "Pizza Palace",
            "address": "123 Test St, Testville",
            "location": {"lat": 10.0, "lng": 20.0},
            "phone": "+1 555-0100",
            "website": "https://example.com",
            "categories": ["Restaurant"],
            "hours": [{"day_of_week": 0, "open_time": "11:30", "close_time": "22:00"}],
        }

    def test_tomtom_outage_still_returns_local_places(self, auth_client, make_place, tomtom):
        tomtom.get(POI_SEARCH_URL, status=503)
        make_place("local", name="Pizza Place")

        response = auth_client.get("/places/search", query="pizza")

        assert response.status_code == 200
        assert [p["tomtom_id"] for p in response.json()] == ["local"]

    def test_a_malformed_tomtom_result_is_skipped(self, auth_client, tomtom):
        bad = {**factories.tomtom_result("bad", "Pizza Bad"), "address": "7 Carmine St", "poi": ["Pizza"]}
        tomtom.get(POI_SEARCH_URL, json=factories.tomtom_response(bad, factories.tomtom_result("good", "Pizza Good")))

        response = auth_client.get("/places/search", query="pizza")

        assert response.status_code == 200
        assert [p["tomtom_id"] for p in response.json()] == ["good"]

    @pytest.mark.parametrize(
        "body", [["results"], "results", {"results": "tt-1"}], ids=["list", "string", "results-string"]
    )
    def test_a_tomtom_body_of_the_wrong_type_still_returns_local_places(self, auth_client, make_place, tomtom, body):
        tomtom.get(POI_SEARCH_URL, json=body)
        make_place("local", name="Pizza Place")

        response = auth_client.get("/places/search", query="pizza")

        assert response.status_code == 200
        assert [p["tomtom_id"] for p in response.json()] == ["local"]

    def test_without_a_tomtom_key_only_local_places_are_searched(self, auth_client, make_place, http_mock):
        make_place("local", name="Pizza Place")

        response = auth_client.get("/places/search", query="PIZZA")

        assert [p["tomtom_id"] for p in response.json()] == ["local"]
        assert len(http_mock.calls) == 0

    def test_no_matches_is_empty(self, auth_client, make_place):
        make_place(name="Burger Barn")

        response = auth_client.get("/places/search", query="sushi")

        assert response.status_code == 200
        assert response.json() == []

    def test_missing_query_is_422(self, auth_client):
        assert _field_errors(auth_client.get("/places/search")) == {"query"}


# --- POST /places/ ---


class TestCreatePlace:
    def test_creates_place(self, auth_client):
        payload = factories.place_data(
            "new-1",
            name="New Place",
            lat=10.0,
            lng=20.0,
            phone="555",
            website="https://new.example",
            categories=["Cafe"],
            hours=factories.hours((2, "08:00", "12:00"), (1, "09:00:00", "17:00:00")),
        )

        response = auth_client.post("/places/", payload)

        assert response.status_code == 200
        data = response.json()
        assert data == places.get_place("new-1")
        assert isinstance(data["id"], int)
        assert data["location"] == {"lat": 10.0, "lng": 20.0}
        # Hours are sorted by day and trimmed to HH:MM.
        assert data["hours"] == factories.hours((1, "09:00", "17:00"), (2, "08:00", "12:00"))

    def test_posting_again_updates_the_same_place(self, auth_client):
        first = auth_client.post("/places/", factories.place_data("p", name="Old")).json()

        second = auth_client.post("/places/", factories.place_data("p", name="New", lat=1.0, lng=2.0)).json()

        assert second["id"] == first["id"]
        assert second["name"] == "New"
        assert second["location"] == {"lat": 1.0, "lng": 2.0}

    def test_empty_tomtom_id_is_422(self, auth_client):
        response = auth_client.post("/places/", factories.place_data(tomtom_id=None) | {"tomtom_id": ""})

        assert _field_errors(response) == {"tomtom_id"}

    @pytest.mark.parametrize(
        "change, fields",
        [
            ({"location": {"lat": 1.0}}, {"lng"}),
            ({"location": {"lat": "north", "lng": 0}}, {"lat"}),
            ({"name": None}, {"name"}),
            ({"hours": [{"day_of_week": "Mon", "open_time": "09:00", "close_time": "17:00"}]}, {"day_of_week"}),
            ({"hours": [{"day_of_week": 1}]}, {"open_time", "close_time"}),
            ({"categories": "Cafe"}, {"categories"}),
            # Hours the app couldn't read back (it parses HH:MM) were stored as sent.
            ({"hours": [{"day_of_week": 1, "open_time": "", "close_time": "17:00"}]}, {"open_time"}),
            ({"hours": [{"day_of_week": 1, "open_time": "9am", "close_time": "24:00"}]}, {"open_time", "close_time"}),
            ({"hours": [{"day_of_week": 1, "open_time": "9:00", "close_time": "5:30pm"}]}, {"open_time", "close_time"}),
            ({"hours": [{"day_of_week": 7, "open_time": "09:00", "close_time": "17:00"}]}, {"day_of_week"}),
            ({"hours": [{"day_of_week": -1, "open_time": "09:00", "close_time": "17:00"}]}, {"day_of_week"}),
            # Values of the wrong JSON type used to be coerced (false -> 0, "1" -> 1).
            ({"hours": [{"day_of_week": False, "open_time": "09:00", "close_time": "17:00"}]}, {"day_of_week"}),
            ({"hours": [{"day_of_week": "1", "open_time": "09:00", "close_time": "17:00"}]}, {"day_of_week"}),
            ({"location": {"lat": "40.7", "lng": 0}}, {"lat"}),
            ({"location": {"lat": 90.5, "lng": 0}}, {"lat"}),
            ({"location": {"lat": 0, "lng": -180.5}}, {"lng"}),
        ],
    )
    def test_invalid_body_is_422(self, auth_client, change, fields):
        payload = factories.place_data("bad") | change

        assert _field_errors(auth_client.post("/places/", payload)) == fields
        assert places.get_place("bad") is None

    def test_whole_number_floats_are_integers(self, auth_client):
        payload = factories.place_data("p") | {
            "hours": [{"day_of_week": 2.0, "open_time": "09:00", "close_time": "17:00"}]
        }

        response = auth_client.post("/places/", payload)

        assert response.status_code == 200, response.content
        assert response.json()["hours"][0]["day_of_week"] == 2


# --- POST /places/bookmark and GET /places/bookmarks ---


class TestBookmark:
    def test_bookmarks_a_place(self, auth_client, place):
        response = auth_client.post("/places/bookmark", {"tomtom_id": "place-1", "custom_name": "Fave"})

        assert response.status_code == 200
        data = response.json()
        assert data["place"] == place
        assert data["custom_name"] == "Fave"
        assert (data["is_pinned"], data["is_check_it_out"]) == (False, False)
        assert (data["icon"], data["color"], data["average_visit_length"]) == (None, None, None)

    def test_bookmarking_twice_keeps_one_bookmark(self, auth_client, place):
        first = auth_client.post("/places/bookmark", {"tomtom_id": "place-1"}).json()
        second = auth_client.post("/places/bookmark", {"tomtom_id": "place-1", "custom_name": "Renamed"}).json()
        third = auth_client.post("/places/bookmark", {"tomtom_id": "place-1"}).json()

        assert first["id"] == second["id"] == third["id"]
        assert third["custom_name"] == "Renamed"  # not cleared by a bookmark without a name
        assert len(auth_client.get("/places/bookmarks").json()) == 1

    def test_unknown_place_is_404(self, auth_client):
        response = auth_client.post("/places/bookmark", {"tomtom_id": "nope"})

        assert response.status_code == 404

    def test_missing_tomtom_id_is_422(self, auth_client):
        assert _field_errors(auth_client.post("/places/bookmark", {"custom_name": "x"})) == {"tomtom_id"}


class TestListBookmarks:
    def test_lists_bookmarks_oldest_first_with_their_places(self, any_auth_client, make_place, make_bookmark):
        user = any_auth_client.user
        older = make_place("older", name="Older")
        newer = make_place("newer", name="Newer")
        make_bookmark(user, older, is_pinned=True)
        make_bookmark(user, newer, custom_name="Mine")

        response = any_auth_client.get("/places/bookmarks")

        assert response.status_code == 200
        data = response.json()
        assert [b["place"]["tomtom_id"] for b in data] == ["older", "newer"]
        assert data[0]["is_pinned"] is True
        assert data[1]["custom_name"] == "Mine"
        assert data[0]["place"] == older

    def test_empty(self, auth_client):
        assert auth_client.get("/places/bookmarks").json() == []

    def test_only_the_users_own_bookmarks(self, auth_client, make_user, place, make_bookmark):
        make_bookmark(make_user("bob"), place)

        assert auth_client.get("/places/bookmarks").json() == []


# --- DELETE /places/bookmarks/{tomtom_id} ---


class TestDeleteBookmark:
    def test_deletes_bookmark(self, auth_client, place, make_bookmark):
        make_bookmark(auth_client.user, place)

        response = auth_client.delete("/places/bookmarks/place-1")

        assert response.status_code == 204
        assert response.content == b""
        assert places.get_saved_place(auth_client.user, place) is None
        assert places.get_place("place-1") == place  # the place itself stays

    def test_unknown_bookmark_is_404(self, auth_client, place):
        response = auth_client.delete("/places/bookmarks/place-1")

        assert response.status_code == 404
        assert response.json() == {"detail": "Bookmark not found"}

    def test_cannot_delete_another_users_bookmark(self, auth_client, make_user, place, make_bookmark):
        bob = make_user("bob")
        make_bookmark(bob, place)

        response = auth_client.delete("/places/bookmarks/place-1")

        assert response.status_code == 404
        assert places.get_saved_place(bob, place) is not None


# --- PATCH /places/bookmarks/{tomtom_id}/... ---

# (path suffix, valid payload, field it sets, expected value, invalid payload, invalid field)
BOOKMARK_UPDATES = [
    ("pin", {"is_pinned": True}, "is_pinned", True, {"is_pinned": 1}, "is_pinned"),
    (
        "check-it-out",
        {"is_check_it_out": True},
        "is_check_it_out",
        True,
        {"is_check_it_out": "true"},
        "is_check_it_out",
    ),
    ("graphic", {"icon": "star"}, "icon", "star", {"icon": 5}, "icon"),
    ("visit-length", {"visit_length": 45}, "average_visit_length", 45, {"visit_length": "long"}, "visit_length"),
]
_UPDATE_IDS = [u[0] for u in BOOKMARK_UPDATES]


class TestBookmarkUpdates:
    @pytest.mark.parametrize("suffix, payload, field, expected, _bad, _bad_field", BOOKMARK_UPDATES, ids=_UPDATE_IDS)
    def test_updates_the_field(
        self, any_auth_client, place, make_bookmark, suffix, payload, field, expected, _bad, _bad_field
    ):
        user = any_auth_client.user
        saved = make_bookmark(user, place, custom_name="Keep")

        response = any_auth_client.patch(f"/places/bookmarks/place-1/{suffix}", payload)

        assert response.status_code == 200
        data = response.json()
        assert data[field] == expected
        assert data["id"] == saved["id"]
        assert data["custom_name"] == "Keep"
        assert data["place"] == place
        assert places.get_saved_place(user, place)[field] == expected

    @pytest.mark.parametrize("suffix, payload, _f, _e, _bad, _bad_field", BOOKMARK_UPDATES, ids=_UPDATE_IDS)
    def test_unknown_place_is_404(self, auth_client, suffix, payload, _f, _e, _bad, _bad_field):
        response = auth_client.patch(f"/places/bookmarks/nope/{suffix}", payload)

        assert response.status_code == 404

    @pytest.mark.parametrize("suffix, payload, _f, _e, _bad, _bad_field", BOOKMARK_UPDATES, ids=_UPDATE_IDS)
    def test_place_not_bookmarked_is_404(self, auth_client, place, suffix, payload, _f, _e, _bad, _bad_field):
        response = auth_client.patch(f"/places/bookmarks/place-1/{suffix}", payload)

        assert response.status_code == 404
        assert places.get_saved_place(auth_client.user, place) is None  # not created by the update

    @pytest.mark.parametrize("suffix, payload, field, _e, _bad, _bad_field", BOOKMARK_UPDATES, ids=_UPDATE_IDS)
    def test_another_users_bookmark_is_404(
        self, auth_client, make_user, place, make_bookmark, suffix, payload, field, _e, _bad, _bad_field
    ):
        bob = make_user("bob")
        before = make_bookmark(bob, place)

        response = auth_client.patch(f"/places/bookmarks/place-1/{suffix}", payload)

        assert response.status_code == 404
        assert places.get_saved_place(bob, place)[field] == before[field]

    @pytest.mark.parametrize("suffix, _p, field, _e, bad, bad_field", BOOKMARK_UPDATES, ids=_UPDATE_IDS)
    def test_invalid_body_is_422(self, auth_client, place, make_bookmark, suffix, _p, field, _e, bad, bad_field):
        before = make_bookmark(auth_client.user, place)

        assert _field_errors(auth_client.patch(f"/places/bookmarks/place-1/{suffix}", bad)) == {bad_field}
        assert places.get_saved_place(auth_client.user, place)[field] == before[field]

    @pytest.mark.parametrize("suffix, field", [("pin", "is_pinned"), ("check-it-out", "is_check_it_out")])
    def test_toggles_can_be_turned_off(self, auth_client, place, make_bookmark, suffix, field):
        make_bookmark(auth_client.user, place, **{field: True})

        response = auth_client.patch(f"/places/bookmarks/place-1/{suffix}", {field: False})

        assert response.json()[field] is False

    @pytest.mark.parametrize("suffix", ["pin", "check-it-out"])
    def test_toggles_require_a_value(self, auth_client, place, make_bookmark, suffix):
        make_bookmark(auth_client.user, place)

        assert auth_client.patch(f"/places/bookmarks/place-1/{suffix}", {}).status_code == 422

    def test_graphic_only_changes_the_fields_sent(self, auth_client, place, make_bookmark):
        make_bookmark(auth_client.user, place, custom_name="Name", icon="star", color="#ff0000")

        data = auth_client.patch("/places/bookmarks/place-1/graphic", {"color": "#00ff00"}).json()

        assert (data["custom_name"], data["icon"], data["color"]) == ("Name", "star", "#00ff00")

    def test_graphic_null_clears_a_field(self, auth_client, place, make_bookmark):
        make_bookmark(auth_client.user, place, icon="star", color="#ff0000")

        data = auth_client.patch("/places/bookmarks/place-1/graphic", {"icon": None}).json()

        assert (data["icon"], data["color"]) == (None, "#ff0000")

    @pytest.mark.parametrize("custom_name, expected", [("  ", None), ("", None), (None, None), ("Fave", "Fave")])
    def test_graphic_blank_custom_name_clears_it(self, auth_client, place, make_bookmark, custom_name, expected):
        make_bookmark(auth_client.user, place, custom_name="Old")

        data = auth_client.patch("/places/bookmarks/place-1/graphic", {"custom_name": custom_name}).json()

        assert data["custom_name"] == expected

    def test_graphic_with_empty_body_changes_nothing(self, auth_client, place, make_bookmark):
        before = make_bookmark(auth_client.user, place, icon="star")

        response = auth_client.patch("/places/bookmarks/place-1/graphic", {})

        assert response.status_code == 200
        assert response.json() == before

    @pytest.mark.parametrize("payload", [{"visit_length": None}, {}])
    def test_visit_length_can_be_cleared(self, auth_client, place, make_bookmark, payload):
        make_bookmark(auth_client.user, place, average_visit_length=30)

        data = auth_client.patch("/places/bookmarks/place-1/visit-length", payload).json()

        assert data["average_visit_length"] is None

    # Negative lengths meant nothing, and huge ones overflowed Firestore's 64-bit integers (a 500).
    @pytest.mark.parametrize("visit_length", [0, -30, 24 * 60 + 1, 2**63])
    def test_visit_length_out_of_range_is_422(self, auth_client, place, make_bookmark, visit_length):
        make_bookmark(auth_client.user, place, average_visit_length=30)

        response = auth_client.patch("/places/bookmarks/place-1/visit-length", {"visit_length": visit_length})

        assert _field_errors(response) == {"visit_length"}
        assert places.get_saved_place(auth_client.user, place)["average_visit_length"] == 30

    @pytest.mark.parametrize("suffix", ["pin", "check-it-out", "graphic", "visit-length"])
    @pytest.mark.parametrize("body", ["[]", "null", '"star"', "[null, null]"])
    def test_body_that_is_not_an_object_is_400(self, auth_client, place, make_bookmark, suffix, body):
        make_bookmark(auth_client.user, place)

        response = auth_client.patch(f"/places/bookmarks/place-1/{suffix}", body)

        assert response.status_code == 400
        assert response.json() == {"detail": "Cannot parse request body"}


# --- GET /places/nearby ---


class TestNearby:
    @pytest.fixture
    def nyc_places(self, make_place):
        return [
            make_place("city-hall", name="City Hall", lat=40.7128, lng=-74.0060),
            make_place("bk-park", name="Brooklyn Bridge Park", lat=40.7003, lng=-73.9967),  # ~1.6 km
            make_place("newark", name="Newark", lat=40.7357, lng=-74.1724),  # ~14 km
        ]

    def test_places_within_the_default_5km(self, auth_client, nyc_places):
        response = auth_client.get("/places/nearby", lat=40.7128, lng=-74.0060)

        assert response.status_code == 200
        assert {p["tomtom_id"] for p in response.json()} == {"city-hall", "bk-park"}

    def test_custom_radius(self, auth_client, nyc_places):
        response = auth_client.get("/places/nearby", lat=40.7128, lng=-74.0060, radius_km=20)

        assert [p["tomtom_id"] for p in response.json()] == [p["tomtom_id"] for p in nyc_places]  # ordered by id

    def test_nothing_nearby(self, auth_client, nyc_places):
        assert auth_client.get("/places/nearby", lat=-33.86, lng=151.21).json() == []

    @pytest.mark.parametrize(
        "params, field",
        [
            ({"lng": -74.0}, "lat"),
            ({"lat": 40.7}, "lng"),
            ({"lat": 90.1, "lng": 0}, "lat"),
            ({"lat": -90.1, "lng": 0}, "lat"),
            ({"lat": 0, "lng": 180.1}, "lng"),
            ({"lat": 0, "lng": -180.1}, "lng"),
            ({"lat": "north", "lng": 0}, "lat"),
            ({"lat": 0, "lng": 0, "radius_km": 0}, "radius_km"),
            ({"lat": 0, "lng": 0, "radius_km": -1}, "radius_km"),
            ({"lat": 0, "lng": 0, "radius_km": places.MAX_NEARBY_RADIUS_KM + 0.1}, "radius_km"),
        ],
    )
    def test_out_of_range_params_are_422(self, auth_client, params, field):
        assert _field_errors(auth_client.get("/places/nearby", **params)) == {field}

    @pytest.mark.parametrize("lat, lng", [(90, 0), (-90, 0), (0, 180), (0, -180)])
    def test_boundary_params_are_accepted(self, auth_client, lat, lng):
        response = auth_client.get("/places/nearby", lat=lat, lng=lng, radius_km=places.MAX_NEARBY_RADIUS_KM)

        assert response.status_code == 200


# --- GET /places/suggestions ---


class TestSuggestions:
    def test_with_a_location_returns_tomtom_nearby_results(self, auth_client, tomtom):
        tomtom.get(
            NEARBY_SEARCH_URL,
            json=factories.tomtom_response(factories.tomtom_result("near-1", "Corner Cafe")),
            match=[
                matchers.query_param_matcher(
                    {
                        "key": TOMTOM_KEY,
                        "lat": "40.7",
                        "lon": "-74.0",
                        "radius": "5000",
                        "limit": "10",
                        "openingHours": "nextSevenDays",
                    }
                )
            ],
        )

        response = auth_client.get("/places/suggestions", lat=40.7, lng=-74.0)

        assert response.status_code == 200
        assert [p["tomtom_id"] for p in response.json()] == ["near-1"]

    def test_with_a_location_and_tomtom_down_is_empty(self, auth_client, tomtom):
        tomtom.get(NEARBY_SEARCH_URL, status=500)

        response = auth_client.get("/places/suggestions", lat=40.7, lng=-74.0)

        assert response.status_code == 200
        assert response.json() == []

    @pytest.mark.parametrize("params", [{}, {"lat": 40.7}, {"lng": -74.0}], ids=["none", "lat-only", "lng-only"])
    def test_without_a_location_returns_recent_places(self, auth_client, make_place, http_mock, params):
        created = [make_place(f"p{i}", name=f"Place {i}") for i in range(12)]

        response = auth_client.get("/places/suggestions", **params)

        assert response.status_code == 200
        assert [p["tomtom_id"] for p in response.json()] == [p["tomtom_id"] for p in reversed(created)][:10]
        assert len(http_mock.calls) == 0

    def test_invalid_coordinates_are_422(self, auth_client):
        assert _field_errors(auth_client.get("/places/suggestions", lat="north", lng=0)) == {"lat"}


# --- GET /places/{tomtom_id} ---


class TestPlaceDetails:
    def test_returns_a_stored_place_without_calling_tomtom(self, auth_client, place, tomtom):
        response = auth_client.get("/places/place-1")

        assert response.status_code == 200
        assert response.json() == place
        assert len(tomtom.calls) == 0

    def test_fetches_an_unknown_place_from_tomtom_and_stores_it(self, auth_client, tomtom):
        tomtom.get(
            PLACE_DETAILS_URL,
            json=factories.tomtom_response(
                factories.tomtom_result(
                    "tt-9", "Remote Place", lat=1.0, lon=2.0, time_ranges=[factories.tomtom_time_range("2026-10-13")]
                )
            ),
            match=[
                matchers.query_param_matcher({"key": TOMTOM_KEY, "entityId": "tt-9", "openingHours": "nextSevenDays"})
            ],
        )

        response = auth_client.get("/places/tt-9")

        assert response.status_code == 200
        data = response.json()
        assert data == places.get_place("tt-9")
        assert (data["name"], data["location"]) == ("Remote Place", {"lat": 1.0, "lng": 2.0})
        assert data["hours"] == factories.hours((1, "09:00", "17:00"))

        # Served from Firestore from now on.
        assert auth_client.get("/places/tt-9").json() == data
        assert len(tomtom.calls) == 1

    @pytest.mark.parametrize(
        "tomtom_reply",
        [{"json": {"results": []}}, {"status": 404}, {"status": 500}, {"body": "<html>"}],
        ids=["no-results", "tomtom-404", "tomtom-500", "malformed"],
    )
    def test_place_unknown_to_tomtom_is_404(self, auth_client, tomtom, tomtom_reply):
        tomtom.get(PLACE_DETAILS_URL, **tomtom_reply)

        response = auth_client.get("/places/nope")

        assert response.status_code == 404
        assert places.get_place("nope") is None

    def test_without_a_tomtom_key_unknown_place_is_404(self, auth_client, http_mock):
        assert auth_client.get("/places/nope").status_code == 404
        assert len(http_mock.calls) == 0


# --- Hours stored before the API checked them ---

# Any string was stored (cut to 5 characters) before this PR, e.g. by a client calling the API directly.
LEGACY_HOURS = [
    {"day_of_week": 0, "open_time": "9:00", "close_time": "5:30p"},
    {"day_of_week": 1, "open_time": "9am", "close_time": "24:00"},
    {"day_of_week": 2, "open_time": "noon", "close_time": "17:00"},  # can't be read, so left out
    {"day_of_week": 9, "open_time": "09:00", "close_time": "17:00"},
]
LEGACY_HOURS_AS_RETURNED = factories.hours((0, "09:00", "17:30"), (1, "09:00", "00:00"))


class TestHoursStoredBeforeTheyWereChecked:
    @pytest.fixture
    def legacy_place(self, make_place):
        make_place("legacy", name="Old Diner")
        get_client().collection(places.PLACES).document(doc_id("legacy")).update({"hours": LEGACY_HOURS})
        return "legacy"

    def test_bookmarks(self, auth_client, legacy_place, make_place, make_bookmark):
        make_bookmark(auth_client.user, places.get_place(legacy_place))
        make_bookmark(auth_client.user, make_place("current"))

        response = auth_client.get("/places/bookmarks")

        assert response.status_code == 200
        assert [b["place"]["hours"] for b in response.json()] == [LEGACY_HOURS_AS_RETURNED, []]

    def test_search(self, auth_client, legacy_place, http_mock):
        response = auth_client.get("/places/search", query="diner")

        assert response.status_code == 200
        assert [p["hours"] for p in response.json()] == [LEGACY_HOURS_AS_RETURNED]

    def test_suggestions(self, auth_client, legacy_place, http_mock):
        response = auth_client.get("/places/suggestions")

        assert response.status_code == 200
        assert [p["hours"] for p in response.json()] == [LEGACY_HOURS_AS_RETURNED]

    def test_place_details_and_nearby(self, auth_client, legacy_place, http_mock):
        details = auth_client.get(f"/places/{legacy_place}")
        nearby = auth_client.get("/places/nearby", lat=40.7128, lng=-74.0060)

        assert (details.status_code, nearby.status_code) == (200, 200)
        assert details.json()["hours"] == LEGACY_HOURS_AS_RETURNED
        assert [p["hours"] for p in nearby.json()] == [LEGACY_HOURS_AS_RETURNED]

    def test_the_same_hours_are_still_refused_as_input(self, auth_client):
        payload = factories.place_data("new") | {"hours": LEGACY_HOURS[:2]}

        response = auth_client.post("/places/", payload)

        assert response.status_code == 422
        assert places.get_place("new") is None
