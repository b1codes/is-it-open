import requests
from django.http import HttpResponse
from ninja import Router
from ninja.errors import HttpError

router = Router()


@router.get("/proxy")
def proxy_ical(request, url: str):
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        return HttpResponse(response.content, content_type="text/calendar")
    except requests.RequestException as e:
        raise HttpError(400, f"Failed to fetch calendar: {e!s}") from e
