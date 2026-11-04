"""
The TomTom contract: the parts of TomTom's Search API responses that services/tomtom.py relies on.

contracts/tomtom/ holds a JSON Schema of that shape and recorded responses (fixtures/) that the
tests below serve to TomTomClient. Every fixture and every response the test factories build must
match the schema, and parsing a fixture must give valid PlaceCreateSchema data.

The `live` tests send the same requests to the real API and check its responses still match the
schema. They need TOMTOM_LIVE_API_KEY and run nightly. To re-record the fixtures from the live API:

    TOMTOM_LIVE_API_KEY=... UPDATE_CONTRACTS=1 uv run pytest tests/contracts/test_tomtom_contract.py -k live
"""

import json
import os
import re
from collections.abc import Callable
from typing import Any

import jsonschema_rs
import pytest
import requests

from apps.places.api import PlaceCreateSchema
from services import tomtom as tomtom_module
from services.tomtom import TomTomClient
from tests import factories
from tests.conftest import TOMTOM_BASE
from tests.contracts.test_openapi_snapshot import SNAPSHOT

TOMTOM_DIR = SNAPSHOT.parent / "tomtom"
LIVE_KEY = os.environ.get("TOMTOM_LIVE_API_KEY", "")


def _load(name: str) -> dict:
    return json.loads((TOMTOM_DIR / name).read_text())


SEARCH_SHAPE = jsonschema_rs.validator_for(_load("search.schema.json"))
GEOCODE_SHAPE = jsonschema_rs.validator_for(_load("geocode.schema.json"))


def shape_errors(validator, response: dict) -> list[str]:
    return [f"{'/'.join(map(str, e.instance_path)) or '$'}: {e.message}" for e in validator.iter_errors(response)]


# Each fixture: the request that recorded it, the URL TomTomClient sends it to, and its shape.
Request = Callable[[TomTomClient], Any]
RECORDINGS: dict[str, tuple[Request, re.Pattern, Any]] = {
    "poi_search": (
        lambda client: client.search_place("joe's pizza"),
        re.compile(rf"{re.escape(TOMTOM_BASE)}/poiSearch/.+\.json"),
        SEARCH_SHAPE,
    ),
    "nearby_search": (
        lambda client: client.nearby_search(40.7306, -74.0021, radius=500),
        re.compile(rf"{re.escape(TOMTOM_BASE)}/nearbySearch/\.json"),
        SEARCH_SHAPE,
    ),
    "place_by_id": (
        # Joe's Pizza, 7 Carmine St, New York.
        lambda client: client.get_place_details("Tu4lEjRtadpLbiAPajPyOQ"),
        re.compile(rf"{re.escape(TOMTOM_BASE)}/place\.json"),
        SEARCH_SHAPE,
    ),
    "geocode": (
        lambda client: client.geocode_address("1 Main St, Springfield, IL"),
        re.compile(rf"{re.escape(TOMTOM_BASE)}/geocode/.+\.json"),
        GEOCODE_SHAPE,
    ),
}


def _places(parsed) -> list[dict]:
    """TomTomClient's result as a list of places (place details give one, geocoding none)."""
    if isinstance(parsed, list):
        return parsed
    return [parsed] if parsed and "tomtom_id" in parsed else []


# --- Recorded responses ---


@pytest.mark.parametrize("name", RECORDINGS)
def test_fixture_matches_the_shape(name):
    _, _, shape = RECORDINGS[name]

    assert shape_errors(shape, _load(f"fixtures/{name}.json")) == []


@pytest.mark.parametrize("name", RECORDINGS)
def test_client_parses_every_fixture_result_into_a_valid_place(name, tomtom):
    request, url, _ = RECORDINGS[name]
    fixture = _load(f"fixtures/{name}.json")
    tomtom.get(url, json=fixture)

    parsed = request(TomTomClient())

    assert parsed, "the client returned nothing from the fixture"
    places = _places(parsed)
    if name != "geocode":
        # place.json is fetched for one place, so only its first result is used.
        assert len(places) == (1 if name == "place_by_id" else len(fixture["results"]))
    for place in places:
        PlaceCreateSchema.model_validate(place)


def test_client_reads_every_field_of_a_recorded_place(tomtom):
    request, url, _ = RECORDINGS["poi_search"]
    tomtom.get(url, json=_load("fixtures/poi_search.json"))

    joes, corner = request(TomTomClient())

    assert joes == {
        "tomtom_id": "Tu4lEjRtadpLbiAPajPyOQ",
        "name": "Joe's Pizza",
        "address": "7 Carmine Street, New York, NY 10014",
        "location": {"lat": 40.730599, "lng": -74.002139},
        "phone": "+1 212-366-1182",
        "website": "www.joespizzanyc.com",
        "categories": ["pizza", "restaurant"],
        # 2026-10-19 is a Monday; Friday and Saturday close at 02:00 the next day.
        "hours": [{"day_of_week": d, "open_time": "10:00", "close_time": "23:00"} for d in range(4)]
        + [{"day_of_week": d, "open_time": "10:00", "close_time": "02:00"} for d in (4, 5)]
        + [{"day_of_week": 6, "open_time": "10:00", "close_time": "23:00"}],
    }
    # A result with no phone, website or opening hours.
    assert (corner["phone"], corner["website"], corner["hours"]) == (None, None, [])


def test_geocode_fixture_gives_coordinates(tomtom):
    request, url, _ = RECORDINGS["geocode"]
    tomtom.get(url, json=_load("fixtures/geocode.json"))

    assert request(TomTomClient()) == {"lat": 39.80178, "lon": -89.64352}


@pytest.mark.parametrize(
    "result",
    [
        factories.tomtom_result(),
        factories.tomtom_result(
            "tt-2", categories=("Pizza", "Restaurant"), time_ranges=[factories.tomtom_time_range("2026-10-14")]
        ),
    ],
    ids=["default", "with-hours"],
)
def test_factory_results_match_the_shape(result):
    """The hand-built responses the unit tests use must look like TomTom's."""
    assert shape_errors(SEARCH_SHAPE, factories.tomtom_response(result)) == []


# --- The live API (nightly) ---


@pytest.fixture
def live_responses(settings, monkeypatch):
    """Points TomTomClient at the live API and records every raw response it gets."""
    settings.TOMTOM_API_KEY = LIVE_KEY
    responses: list[requests.Response] = []
    real_get = requests.get

    def get(*args, **kwargs):
        response = real_get(*args, **kwargs)
        responses.append(response)
        return response

    monkeypatch.setattr(tomtom_module.requests, "get", get)
    return responses


@pytest.mark.skipif(not LIVE_KEY, reason="needs TOMTOM_LIVE_API_KEY (runs nightly)")
@pytest.mark.parametrize("name", RECORDINGS)
def test_live_api_still_matches_the_shape(name, live_responses):
    request, _, shape = RECORDINGS[name]

    parsed = request(TomTomClient())

    (response,) = live_responses
    assert response.status_code == 200, response.text[:500]
    body = response.json()
    assert shape_errors(shape, body) == []
    assert parsed, f"TomTom returned no usable results: {json.dumps(body)[:500]}"
    for place in _places(parsed):
        PlaceCreateSchema.model_validate(place)

    if os.environ.get("UPDATE_CONTRACTS") == "1":
        (TOMTOM_DIR / f"fixtures/{name}.json").write_text(json.dumps(body, indent=2, ensure_ascii=False) + "\n")
