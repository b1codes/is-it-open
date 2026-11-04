"""
Provider verification: the backend honors its contract (contracts/openapi.json).

Schemathesis generates requests for every operation in the contract, both valid ones and ones
that break it, sends them to the app in-process, and checks each response:
- no 5xx;
- the status code, content type, headers and body are the ones the contract documents;
- invalid input is rejected (4xx) and valid input isn't;
- routes that need auth reject requests without it.

TomTom is mocked, and Firestore is the emulator, seeded with a signed-in user and a bookmarked
place so that routes taking a `tomtom_id` sometimes find one. SCHEMATHESIS_MAX_EXAMPLES sets how
many requests each operation gets (the nightly run sends many more).
"""

import os
import re

import pytest
import schemathesis
from django.core.wsgi import get_wsgi_application
from hypothesis import HealthCheck, settings
from hypothesis import strategies as st
from schemathesis.specs.openapi.checks import positive_data_acceptance

from apps.users import repository as users
from tests import factories
from tests.conftest import TOMTOM_BASE
from tests.contracts.test_openapi_snapshot import SNAPSHOT

MAX_EXAMPLES = int(os.environ.get("SCHEMATHESIS_MAX_EXAMPLES", "50"))
SEEDED_PLACE = "place-1"

schema = schemathesis.openapi.from_path(SNAPSHOT)
schema.app = get_wsgi_application()

# The `signed_in` fixture's API token, sent on every request except those testing a missing one.
_signed_in: dict[str, str] = {}


@schema.auth(refresh_interval=None)  # each test signs in a new user, so never reuse a token
class _SignedInUser:
    def get(self, case, ctx):
        return _signed_in.get("token")

    def set(self, case, data, ctx):
        case.headers = {**(case.headers or {}), "Authorization": f"Bearer {data}"}


@schema.hook("flatmap_path_parameters")
def _sometimes_a_seeded_place(ctx, path_parameters):
    """Generated IDs almost never exist, so also try the seeded place to reach the success paths."""
    if path_parameters and "tomtom_id" in path_parameters:
        return st.sampled_from([path_parameters, {**path_parameters, "tomtom_id": SEEDED_PLACE}])
    return st.just(path_parameters)


@pytest.fixture
def signed_in(make_user, make_place, make_bookmark, tomtom):
    user = make_user("alice", home_street="1 Main St", home_city="Springfield")
    place = make_place(SEEDED_PLACE, name="Joe's Pizza", hours=factories.hours((0, "09:00", "17:00")))
    make_bookmark(user, place)

    result = factories.tomtom_result(
        "tt-1", "Pizza Place", time_ranges=[factories.tomtom_time_range("2026-10-14", (11, 0), (23, 30))]
    )
    tomtom.get(
        re.compile(rf"{re.escape(TOMTOM_BASE)}/(poiSearch/.+|nearbySearch/)\.json"),
        json=factories.tomtom_response(result),
    )
    tomtom.get(f"{TOMTOM_BASE}/place.json", json=factories.tomtom_response(result))
    tomtom.get(
        re.compile(rf"{re.escape(TOMTOM_BASE)}/geocode/.+\.json"),
        json={"results": [{"position": {"lat": 1.5, "lon": 2.5}}]},
    )
    # Any other URL is a calendar, so the proxy's success path is reached too. (Excluding the hosts
    # above: `responses` misbehaves when two registered URLs match one request.)
    tomtom.get(
        re.compile(r"https?://(?!api\.tomtom\.com|localhost|127\.0\.0\.1).+"),
        body="BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n",
        content_type="text/calendar",
    )

    _signed_in["token"] = users.get_or_create_token(user)
    yield
    _signed_in.clear()


# The proxy only finds out whether a URL works by fetching it, so a schema-valid URL ("http://",
# "http://a:b") can still be rejected with a 400.
EXCLUDED_CHECKS = {"GET /api/calendar/proxy": [positive_data_acceptance]}


@schema.parametrize()
@settings(max_examples=MAX_EXAMPLES, suppress_health_check=[HealthCheck.function_scoped_fixture, HealthCheck.too_slow])
def test_api_honors_its_contract(case, signed_in):
    case.call_and_validate(excluded_checks=EXCLUDED_CHECKS.get(case.operation.label, []))
