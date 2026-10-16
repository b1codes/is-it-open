"""/api/calendar/proxy: fetches an iCal feed for the web app, which can't fetch it cross-origin."""

import pytest
import requests

from tests.conftest import ApiClient

FEED_URL = "https://calendar.example.com/feed.ics"
ICS = b"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n"


def test_returns_the_feed_as_text_calendar(any_auth_client, http_mock):
    http_mock.get(FEED_URL, body=ICS, content_type="text/plain")

    response = any_auth_client.get("/calendar/proxy", url=FEED_URL)

    assert response.status_code == 200
    assert response.content == ICS
    assert response["Content-Type"] == "text/calendar"


def test_query_string_of_the_feed_url_is_kept(auth_client, http_mock):
    http_mock.get(f"{FEED_URL}?token=abc&x=1", body=ICS)

    response = auth_client.get("/calendar/proxy", url=f"{FEED_URL}?token=abc&x=1")

    assert response.status_code == 200
    assert http_mock.calls[0].request.url == f"{FEED_URL}?token=abc&x=1"


@pytest.mark.parametrize(
    "upstream",
    [
        {"status": 404},
        {"status": 500},
        {"body": requests.ConnectTimeout("timed out")},
        {"body": requests.ConnectionError("refused")},
    ],
    ids=["upstream-404", "upstream-500", "timeout", "connection-error"],
)
def test_upstream_failure_is_400(auth_client, http_mock, upstream):
    http_mock.get(FEED_URL, **upstream)

    response = auth_client.get("/calendar/proxy", url=FEED_URL)

    assert response.status_code == 400
    assert response.json()["detail"].startswith("Failed to fetch calendar")


@pytest.mark.parametrize("url", ["not a url", "ftp://example.com/cal.ics", ""])
def test_unfetchable_url_is_400(auth_client, http_mock, url):
    assert auth_client.get("/calendar/proxy", url=url).status_code == 400


def test_missing_url_is_422(auth_client):
    response = auth_client.get("/calendar/proxy")

    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"][-1] == "url"


def test_requires_sign_in(firestore_db, http_mock):
    response = ApiClient().get("/calendar/proxy", url=FEED_URL)

    assert response.status_code == 401
    assert len(http_mock.calls) == 0
