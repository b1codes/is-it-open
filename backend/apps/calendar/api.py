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

# The proxy holds a calendar in memory, and the app downloads and parses all of it on the device, so
# there's a limit; without one, a URL could make the backend read without end. Subscription feeds
# are usually far smaller. One over it is refused with a 400 that names the limit.
MAX_CALENDAR_BYTES = 10 * 2**20


def _is_icalendar(body: bytes) -> bool:
    return body.removeprefix(b"\xef\xbb\xbf").lstrip()[:15].upper() == b"BEGIN:VCALENDAR"


# Pasted links can have surrounding spaces or an upper-case scheme, and calendar apps' "subscribe"
# links (Apple's, Google's) use webcal:// or webcals://. (Spelled out rather than with (?i), which
# isn't valid in the ECMAScript regexes that OpenAPI patterns use.)
URL_PATTERN = r"^\s*([Hh][Tt][Tt][Pp][Ss]?|[Ww][Ee][Bb][Cc][Aa][Ll][Ss]?)://"


def _feed_urls(url: str) -> list[str]:
    """
    The URLs to try for `url`, in order. webcal(s):// only marks a feed to subscribe to: webcals://
    is HTTPS, and webcal:// is HTTP by convention, though most feeds are served over HTTPS now. So
    webcal:// tries HTTPS first and, when nothing answers there, HTTP, as calendar apps do. Fetched
    over HTTPS only, a feed served only over HTTP (some self-hosted, school and sports calendars)
    couldn't be reached.
    """
    url = url.strip()
    scheme, _, rest = url.partition("://")
    if scheme.lower() == "webcal":
        return [f"https://{rest}", f"http://{rest}"]
    if scheme.lower() == "webcals":
        return [f"https://{rest}"]
    return [url]


def _fetch_feed(url: str) -> bytes:
    *fallbacks, last = _feed_urls(url)
    # The next URL is tried only when this one's server couldn't be reached at all. Any other answer
    # (an error status, a timeout, a blocked address) is the feed's, and trying again wouldn't change it.
    # A failed TLS handshake or a bad certificate isn't retried either: it can come from someone on the
    # path, who would then see the feed's secret URL, and could answer for it, over plain HTTP.
    for feed_url in fallbacks:
        try:
            return safe_fetch.fetch(feed_url, max_bytes=MAX_CALENDAR_BYTES)
        except safe_fetch.Unreachable:
            continue
    return safe_fetch.fetch(last, max_bytes=MAX_CALENDAR_BYTES)


@router.get("/proxy", response={400: ErrorSchema}, openapi_extra=ICAL_RESPONSE)
def proxy_ical(request, url: str = Query(..., pattern=URL_PATTERN)):
    # `url` is the user's, so it's only fetched from public hosts (see services/safe_fetch.py), over
    # HTTP as well as HTTPS.
    try:
        body = _fetch_feed(url)
    except safe_fetch.FetchError as e:
        raise HttpError(400, f"Failed to fetch calendar: {e}") from e
    if not _is_icalendar(body):
        raise HttpError(400, "Failed to fetch calendar: it isn't an iCalendar file")

    response = HttpResponse(body, content_type="text/calendar")
    response["Cache-Control"] = "no-store"  # feed URLs are often secret links to someone's calendar
    return response
