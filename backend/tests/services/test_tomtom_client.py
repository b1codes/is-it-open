"""services/tomtom.py against recorded-shape TomTom responses served by `responses`."""

import datetime
import re
from urllib.parse import unquote, urlsplit

import pytest
import requests
from freezegun import freeze_time
from responses import matchers

from services.tomtom import TomTomClient
from tests import factories
from tests.conftest import TOMTOM_BASE, TOMTOM_KEY

POI_SEARCH_URL = re.compile(rf"{re.escape(TOMTOM_BASE)}/poiSearch/.+\.json")
NEARBY_SEARCH_URL = f"{TOMTOM_BASE}/nearbySearch/.json"
PLACE_DETAILS_URL = f"{TOMTOM_BASE}/place.json"
GEOCODE_URL = re.compile(rf"{re.escape(TOMTOM_BASE)}/geocode/.+\.json")

# Ways a TomTom call fails that the client turns into "no results".
FAILURES = [
    {"status": 400},
    {"status": 403, "json": {"errorText": "Developer Inactive"}},
    {"status": 429},
    {"status": 500},
    {"status": 503},
    {"body": requests.Timeout("read timed out")},
    {"body": requests.ConnectionError("connection refused")},
    {"body": "<html>not json</html>"},
]
FAILURE_IDS = ["400", "403-bad-key", "429-rate-limited", "500", "503", "timeout", "connection-error", "malformed-json"]


@pytest.fixture
def client(tomtom):
    return TomTomClient()


def _path(call) -> str:
    return unquote(urlsplit(call.request.url).path)


# --- search_place ---


class TestSearchPlace:
    def test_parses_results(self, client, tomtom):
        tomtom.get(
            POI_SEARCH_URL,
            json=factories.tomtom_response(
                factories.tomtom_result(
                    "tt-1",
                    "Joe's Pizza",
                    lat=40.73,
                    lon=-73.99,
                    categories=("Pizza", "Restaurant"),
                    time_ranges=[factories.tomtom_time_range("2026-10-14", (11, 0), (23, 30))],
                ),
                factories.tomtom_result("tt-2", "Pizza Hut"),
            ),
            match=[matchers.query_param_matcher({"key": TOMTOM_KEY, "limit": "10", "openingHours": "nextSevenDays"})],
        )

        results = client.search_place("pizza")

        assert results[0] == {
            "tomtom_id": "tt-1",
            "name": "Joe's Pizza",
            "address": "123 Test St, Testville",
            "location": {"lat": 40.73, "lng": -73.99},
            "phone": "+1 555-0100",
            "website": "https://example.com",
            "categories": ["Pizza", "Restaurant"],
            "hours": [{"day_of_week": 2, "open_time": "11:00", "close_time": "23:30"}],  # a Wednesday
        }
        assert [r["tomtom_id"] for r in results] == ["tt-1", "tt-2"]
        assert _path(tomtom.calls[0]) == "/search/2/poiSearch/pizza.json"

    @pytest.mark.parametrize("query", ["joe's #1 pizza", "a/b", "what?", "50% off", "café"])
    def test_query_is_one_path_segment(self, client, tomtom, query):
        tomtom.get(POI_SEARCH_URL, json=factories.tomtom_response())

        client.search_place(query)

        (call,) = tomtom.calls
        assert _path(call) == f"/search/2/poiSearch/{query}.json"
        assert urlsplit(call.request.url).path.count("/") == 4  # the query didn't add segments
        assert urlsplit(call.request.url).fragment == ""

    @pytest.mark.parametrize("body", [{"results": []}, {}, {"results": None}], ids=["empty", "no-key", "null"])
    def test_no_results(self, client, tomtom, body):
        tomtom.get(POI_SEARCH_URL, json=body)

        assert client.search_place("zzz") == []

    @pytest.mark.parametrize("failure", FAILURES, ids=FAILURE_IDS)
    def test_failure_returns_empty(self, client, tomtom, failure):
        tomtom.get(POI_SEARCH_URL, **failure)

        assert client.search_place("pizza") == []

    def test_uses_a_timeout(self, client, tomtom):
        tomtom.get(POI_SEARCH_URL, json=factories.tomtom_response())

        client.search_place("pizza")

        assert tomtom.calls[0].request.req_kwargs["timeout"] == 10

    def test_without_a_key_makes_no_request(self, settings, http_mock):
        settings.TOMTOM_API_KEY = ""

        assert TomTomClient().search_place("pizza") == []
        assert len(http_mock.calls) == 0

    def test_skips_results_a_place_cannot_be_made_from(self, client, tomtom):
        good = factories.tomtom_result("good", "Good")
        no_id = factories.tomtom_result(None, "No ID")
        no_name = factories.tomtom_result("no-name", None)
        no_position = {**factories.tomtom_result("no-pos", "No position"), "position": None}
        no_poi = {"id": "no-poi", "position": {"lat": 1, "lon": 2}}
        tomtom.get(POI_SEARCH_URL, json=factories.tomtom_response(no_id, good, no_name, no_position, no_poi, "junk"))

        assert [r["tomtom_id"] for r in client.search_place("x")] == ["good"]


# --- nearby_search ---


class TestNearbySearch:
    def test_sends_location_radius_and_limit(self, client, tomtom):
        tomtom.get(
            NEARBY_SEARCH_URL,
            json=factories.tomtom_response(factories.tomtom_result("near")),
            match=[
                matchers.query_param_matcher(
                    {
                        "key": TOMTOM_KEY,
                        "lat": "40.7",
                        "lon": "-74.0",
                        "radius": "1000",
                        "limit": "3",
                        "openingHours": "nextSevenDays",
                    }
                )
            ],
        )

        results = client.nearby_search(40.7, -74.0, radius=1000, limit=3)

        assert [r["tomtom_id"] for r in results] == ["near"]

    def test_empty(self, client, tomtom):
        tomtom.get(NEARBY_SEARCH_URL, json=factories.tomtom_response())

        assert client.nearby_search(0, 0) == []

    @pytest.mark.parametrize("failure", FAILURES, ids=FAILURE_IDS)
    def test_failure_returns_empty(self, client, tomtom, failure):
        tomtom.get(NEARBY_SEARCH_URL, **failure)

        assert client.nearby_search(40.7, -74.0) == []

    def test_without_a_key_makes_no_request(self, settings, http_mock):
        settings.TOMTOM_API_KEY = ""

        assert TomTomClient().nearby_search(40.7, -74.0) == []
        assert len(http_mock.calls) == 0


# --- get_place_details ---


class TestGetPlaceDetails:
    def test_returns_the_first_result(self, client, tomtom):
        tomtom.get(
            PLACE_DETAILS_URL,
            json=factories.tomtom_response(factories.tomtom_result("tt-1", "First"), factories.tomtom_result("tt-2")),
            match=[
                matchers.query_param_matcher({"key": TOMTOM_KEY, "entityId": "tt-1", "openingHours": "nextSevenDays"})
            ],
        )

        assert client.get_place_details("tt-1")["name"] == "First"

    def test_unknown_id(self, client, tomtom):
        tomtom.get(PLACE_DETAILS_URL, json=factories.tomtom_response())

        assert client.get_place_details("nope") is None

    def test_unusable_result(self, client, tomtom):
        tomtom.get(PLACE_DETAILS_URL, json=factories.tomtom_response(factories.tomtom_result("tt-1", name=None)))

        assert client.get_place_details("tt-1") is None

    @pytest.mark.parametrize("failure", FAILURES, ids=FAILURE_IDS)
    def test_failure_returns_none(self, client, tomtom, failure):
        tomtom.get(PLACE_DETAILS_URL, **failure)

        assert client.get_place_details("tt-1") is None

    @pytest.mark.parametrize("tomtom_id", ["", None])
    def test_empty_id_makes_no_request(self, client, tomtom, tomtom_id):
        assert client.get_place_details(tomtom_id) is None
        assert len(tomtom.calls) == 0

    def test_without_a_key_makes_no_request(self, settings, http_mock):
        settings.TOMTOM_API_KEY = ""

        assert TomTomClient().get_place_details("tt-1") is None
        assert len(http_mock.calls) == 0


# --- geocode_address ---


def _geocode_reply(lat=39.78, lon=-89.65):
    return {"results": [{"type": "Point Address", "position": {"lat": lat, "lon": lon}}]}


class TestGeocodeAddress:
    def test_returns_the_first_position(self, client, tomtom):
        tomtom.get(
            GEOCODE_URL,
            json=_geocode_reply(),
            match=[matchers.query_param_matcher({"key": TOMTOM_KEY, "limit": "1"})],
        )

        assert client.geocode_address("1 Main St, Springfield, IL") == {"lat": 39.78, "lon": -89.65}
        assert _path(tomtom.calls[0]) == "/search/2/geocode/1 Main St, Springfield, IL.json"

    @pytest.mark.parametrize("address", ["Apt #4, 1 Main St", "1/2 Main St", "1 Main St?"])
    def test_address_is_one_path_segment(self, client, tomtom, address):
        tomtom.get(GEOCODE_URL, json=_geocode_reply())

        client.geocode_address(address)

        assert _path(tomtom.calls[0]) == f"/search/2/geocode/{address}.json"
        assert urlsplit(tomtom.calls[0].request.url).fragment == ""

    def test_results_are_cached_by_normalized_address(self, client, tomtom):
        tomtom.get(GEOCODE_URL, json=_geocode_reply())

        first = client.geocode_address("1 Main St")
        again = TomTomClient().geocode_address("  1 MAIN st ")

        assert first == again == {"lat": 39.78, "lon": -89.65}
        assert len(tomtom.calls) == 1

    def test_cache_expires_after_a_day(self, client, tomtom):
        tomtom.get(GEOCODE_URL, json=_geocode_reply())

        with freeze_time("2026-10-15 12:00") as clock:
            client.geocode_address("1 Main St")
            clock.tick(datetime.timedelta(hours=23))
            client.geocode_address("1 Main St")
            assert len(tomtom.calls) == 1

            clock.tick(datetime.timedelta(hours=2))
            client.geocode_address("1 Main St")
            assert len(tomtom.calls) == 2

    @pytest.mark.parametrize(
        "body",
        [
            {"results": []},
            {},
            {"results": [{"position": {"lat": 1.0}}]},
            {"results": [{"position": None}]},
            {"results": [{}]},
        ],
        ids=["no-results", "no-results-key", "no-lon", "null-position", "no-position"],
    )
    def test_no_usable_position_returns_none(self, client, tomtom, body):
        tomtom.get(GEOCODE_URL, json=body)

        assert client.geocode_address("Nowhere") is None

    @pytest.mark.parametrize("failure", FAILURES, ids=FAILURE_IDS)
    def test_failure_returns_none_and_is_not_cached(self, client, tomtom, failure):
        tomtom.get(GEOCODE_URL, **failure)
        assert client.geocode_address("1 Main St") is None

        tomtom.replace("GET", GEOCODE_URL, json=_geocode_reply())
        assert client.geocode_address("1 Main St") == {"lat": 39.78, "lon": -89.65}

    def test_uses_a_timeout(self, client, tomtom):
        tomtom.get(GEOCODE_URL, json=_geocode_reply())

        client.geocode_address("1 Main St")

        assert tomtom.calls[0].request.req_kwargs["timeout"] == 5

    def test_empty_address_makes_no_request(self, client, tomtom):
        assert client.geocode_address("") is None
        assert len(tomtom.calls) == 0

    def test_without_a_key_makes_no_request(self, settings, http_mock):
        settings.TOMTOM_API_KEY = ""

        assert TomTomClient().geocode_address("1 Main St") is None
        assert len(http_mock.calls) == 0


# --- Parsing ---


class TestParsePlace:
    def test_builds_an_address_when_there_is_no_freeform_one(self):
        result = factories.tomtom_result()
        result["address"] = {"streetNumber": "12", "streetName": "Elm St", "municipality": "Springfield"}

        assert TomTomClient()._parse_place(result)["address"] == "12 Elm St, Springfield"

    def test_optional_fields_default(self):
        result = {"id": "tt-1", "poi": {"name": "Bare"}, "position": {"lat": 1, "lon": 2}}

        assert TomTomClient()._parse_place(result) == {
            "tomtom_id": "tt-1",
            "name": "Bare",
            "address": " , ",
            "location": {"lat": 1, "lng": 2},
            "phone": None,
            "website": None,
            "categories": [],
            "hours": [],
        }

    def test_skips_categories_without_names(self):
        result = factories.tomtom_result()
        result["poi"]["categorySet"] = [{"id": 1}, {"id": 2, "name": "Cafe"}, {"id": 3, "name": ""}, "junk"]

        assert TomTomClient()._parse_place(result)["categories"] == ["Cafe"]


class TestParseOpeningHours:
    parse = staticmethod(TomTomClient()._parse_opening_hours)

    def test_maps_dates_to_weekdays(self):
        # 2026-10-12 is a Monday.
        ranges = [factories.tomtom_time_range(f"2026-10-{12 + i}", (8 + i, 0), (17, 15)) for i in range(7)]

        assert self.parse({"timeRanges": ranges}) == [
            {"day_of_week": i, "open_time": f"{8 + i:02d}:00", "close_time": "17:15"} for i in range(7)
        ]

    def test_first_range_for_a_weekday_wins(self):
        # nextSevenDays can include the same weekday twice (today and a week from today), and
        # split days (lunch break) have two ranges on one date.
        ranges = [
            factories.tomtom_time_range("2026-10-12", (9, 0), (12, 0)),
            factories.tomtom_time_range("2026-10-12", (13, 0), (17, 0)),
            factories.tomtom_time_range("2026-10-19", (10, 0), (11, 0)),
        ]

        assert self.parse({"timeRanges": ranges}) == [{"day_of_week": 0, "open_time": "09:00", "close_time": "12:00"}]

    def test_missing_hour_or_minute_is_zero(self):
        ranges = [{"startTime": {"date": "2026-10-12", "hour": 9}, "endTime": {"date": "2026-10-12"}}]

        assert self.parse({"timeRanges": ranges}) == [{"day_of_week": 0, "open_time": "09:00", "close_time": "00:00"}]

    @pytest.mark.parametrize("data", [None, {}, {"mode": "nextSevenDays"}, {"timeRanges": []}, {"timeRanges": None}])
    def test_no_hours(self, data):
        assert self.parse(data) == []

    @pytest.mark.parametrize(
        "bad_range",
        [
            {"startTime": {"hour": 9}, "endTime": {"hour": 17}},
            {"startTime": {"date": "", "hour": 9}, "endTime": {}},
            {"startTime": {"date": "2026-13-45", "hour": 9}, "endTime": {}},
            {"startTime": {"date": "Monday", "hour": 9}, "endTime": {}},
            {"startTime": {"date": "2026-10-12", "hour": None}, "endTime": {}},
            {"startTime": {"date": "2026-10-12", "hour": "9"}, "endTime": {}},
            {"startTime": {"date": "2026-10-12", "hour": 9.5}, "endTime": {}},
            {"startTime": {"date": "2026-10-12", "hour": 9}, "endTime": {"hour": None}},
            {"startTime": None, "endTime": None},
            {"startTime": {"date": "2026-10-12"}, "endTime": None},
            "junk",
            None,
            # Out of range: "24:00" or "09:60" would break the API contract and the app.
            {"startTime": {"date": "2026-10-12", "hour": 9}, "endTime": {"hour": 24}},
            {"startTime": {"date": "2026-10-12", "hour": 9, "minute": 60}, "endTime": {"hour": 17}},
            {"startTime": {"date": "2026-10-12", "hour": -1}, "endTime": {"hour": 17}},
        ],
        ids=[
            "no-date",
            "empty-date",
            "impossible-date",
            "non-iso-date",
            "null-hour",
            "string-hour",
            "float-hour",
            "null-close-hour",
            "null-times",
            "null-end-time",
            "string-range",
            "null-range",
            "hour-24",
            "minute-60",
            "negative-hour",
        ],
    )
    def test_malformed_ranges_are_skipped(self, bad_range):
        good = factories.tomtom_time_range("2026-10-13")  # a Tuesday

        assert self.parse({"timeRanges": [bad_range, good]}) == [
            {"day_of_week": 1, "open_time": "09:00", "close_time": "17:00"}
        ]

    def test_malformed_range_does_not_hide_a_later_good_one_for_the_same_day(self):
        bad = {"startTime": {"date": "2026-10-12", "hour": None}, "endTime": {}}
        good = factories.tomtom_time_range("2026-10-12")

        assert self.parse({"timeRanges": [bad, good]}) == [
            {"day_of_week": 0, "open_time": "09:00", "close_time": "17:00"}
        ]
