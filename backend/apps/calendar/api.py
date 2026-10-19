import requests
from django.http import HttpResponse
from ninja import Router
from ninja.errors import HttpError

from config.schemas import ErrorSchema

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


@router.get("/proxy", response={400: ErrorSchema}, openapi_extra=ICAL_RESPONSE)
def proxy_ical(request, url: str):
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        return HttpResponse(response.content, content_type="text/calendar")
    except requests.RequestException as e:
        raise HttpError(400, f"Failed to fetch calendar: {e!s}") from e
