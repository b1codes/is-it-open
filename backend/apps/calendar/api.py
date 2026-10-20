from django.http import HttpResponse
from ninja import Query, Router
from ninja.errors import HttpError

from config.schemas import ErrorSchema
from services import safe_fetch

router = Router()

# The view returns the calendar as is rather than a schema, so its 200 is documented by hand.
ICAL_RESPONSE = {
    "responses": {
        200: {
            "description": "The calendar at `url`, unchanged",
            "content": {"text/calendar": {"schema": {"type": "string"}}},
        }
    }
}

MAX_CALENDAR_BYTES = 10 * 2**20


def _is_icalendar(body: bytes) -> bool:
    return body.removeprefix(b"\xef\xbb\xbf").lstrip()[:15].upper() == b"BEGIN:VCALENDAR"


@router.get("/proxy", response={400: ErrorSchema}, openapi_extra=ICAL_RESPONSE)
def proxy_ical(request, url: str = Query(..., pattern=r"^https?://")):
    # `url` is the user's, so it's only fetched from public hosts (see services/safe_fetch.py).
    try:
        body = safe_fetch.fetch(url, max_bytes=MAX_CALENDAR_BYTES)
    except safe_fetch.FetchError as e:
        raise HttpError(400, f"Failed to fetch calendar: {e}") from e
    if not _is_icalendar(body):
        raise HttpError(400, "Failed to fetch calendar: it isn't an iCalendar file")

    response = HttpResponse(body, content_type="text/calendar")
    response["Cache-Control"] = "no-store"  # feed URLs are often secret links to someone's calendar
    return response
