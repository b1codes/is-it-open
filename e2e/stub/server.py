"""
Stands in for every external service the E2E stack would otherwise call (see e2e/README.md):

    /search/2/...         TomTom Search (TOMTOM_BASE_URL points here), built from the recorded
                          contract fixtures in contracts/tomtom/fixtures
    /calendar/e2e.ics     an iCal feed for the app to subscribe to through /calendar/proxy
    /tiles/{z}/{x}/{y}    blank map tiles (envs/e2e.json points the app's map here)
    /health               for the compose healthcheck

Standard library only, so the image is just python:3.11-slim.

TomTom's "nextSevenDays" opening hours are dated, so every response is shifted to start today.
Besides the fixture places, POI search knows two made-up places whose status doesn't depend on the
time of day: "All Day Diner" is open 24 hours and "Night Owl Bakery" is open only 03:00-03:01, so it
shows as closed (except during that one minute).

A query or address containing "outage" gets a 503, to drive the app's TomTom-failure path.
"""

import copy
import datetime
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

FIXTURES = Path(os.environ.get("FIXTURES_DIR", "/fixtures"))
PORT = int(os.environ.get("PORT", "8090"))

# A 1x1 transparent PNG.
BLANK_TILE = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
    "0000000b49444154789c6360000200000500017a5eab3f0000000049454e44ae426082"
)

ICAL_EVENT_TITLE = "E2E Dentist Appointment"


def _load(name: str) -> dict:
    return json.loads((FIXTURES / f"{name}.json").read_text())


def _today() -> datetime.date:
    return datetime.datetime.now(datetime.UTC).date()


def _shift_dates(value, days: int):
    """`value` with every "date" field moved by `days`."""
    if isinstance(value, dict):
        return {
            k: (_add_days(v, days) if k == "date" and isinstance(v, str) else _shift_dates(v, days))
            for k, v in value.items()
        }
    if isinstance(value, list):
        return [_shift_dates(v, days) for v in value]
    return value


def _add_days(date: str, days: int) -> str:
    return (datetime.date.fromisoformat(date) + datetime.timedelta(days=days)).isoformat()


def _first_date(value) -> datetime.date | None:
    dates = re.findall(r'"date": "(\d{4}-\d{2}-\d{2})"', json.dumps(value))
    return min(datetime.date.fromisoformat(d) for d in dates) if dates else None


def _starting_today(response: dict) -> dict:
    first = _first_date(response)
    return _shift_dates(response, (_today() - first).days) if first else response


def _time(day: datetime.date, hour: int, minute: int = 0) -> dict:
    return {"date": day.isoformat(), "hour": hour, "minute": minute}


def _week_of_hours(open_at: tuple[int, int], close_at: tuple[int, int], overnight=False) -> dict:
    days = [_today() + datetime.timedelta(days=i) for i in range(7)]
    return {
        "mode": "nextSevenDays",
        "timeRanges": [
            {
                "startTime": _time(day, *open_at),
                "endTime": _time(day + datetime.timedelta(days=1 if overnight else 0), *close_at),
            }
            for day in days
        ],
    }


def _made_up_place(template: dict, tomtom_id: str, name: str, category: str, street: str, lat: float, hours: dict):
    result = copy.deepcopy(template)
    result["id"] = tomtom_id
    result["position"] = {"lat": lat, "lon": template["position"]["lon"]}
    result["address"]["freeformAddress"] = f"{street}, New York, NY 10014"
    poi = result["poi"]
    poi.update(name=name, openingHours=hours, categories=[category], phone=None, url=None)
    poi["classifications"] = [{"code": category.upper(), "names": [{"nameLocale": "en-US", "name": category}]}]
    return result


def poi_results() -> list[dict]:
    """Every place POI search can return."""
    fixture = _starting_today(_load("poi_search"))["results"]
    template = fixture[0]
    return [
        *fixture,
        _made_up_place(
            template,
            "e2e-all-day-diner",
            "All Day Diner",
            "diner",
            "24 Bleecker Street",
            40.7316,
            # 00:00 to 00:00 the next day is open around the clock.
            _week_of_hours((0, 0), (0, 0), overnight=True),
        ),
        _made_up_place(
            template,
            "e2e-night-owl-bakery",
            "Night Owl Bakery",
            "bakery",
            "3 Owl Lane",
            40.7296,
            _week_of_hours((3, 0), (3, 1)),
        ),
    ]


def search_response(query: str) -> dict:
    words = query.lower().split()
    results = [r for r in poi_results() if all(w in r["poi"]["name"].lower() for w in words)]
    return {"summary": {"query": query, "numResults": len(results)}, "results": results}


def place_response(entity_id: str) -> dict:
    nearby = _starting_today(_load("nearby_search"))["results"]
    results = [r for r in [*poi_results(), *nearby] if r["id"] == entity_id][:1]
    return {"summary": {"numResults": len(results)}, "results": results}


def ical_feed() -> str:
    """One event a day from yesterday to tomorrow (UTC), so one always falls in the app's week."""
    stamp = datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%SZ")
    events = []
    for offset in (-1, 0, 1):
        day = (_today() + datetime.timedelta(days=offset)).strftime("%Y%m%d")
        events += [
            "BEGIN:VEVENT",
            f"UID:e2e-dentist-{day}@is-it-open.test",
            f"DTSTAMP:{stamp}",
            f"DTSTART:{day}T150000Z",
            f"DTEND:{day}T160000Z",
            f"SUMMARY:{ICAL_EVENT_TITLE}",
            "END:VEVENT",
        ]
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//is-it-open//e2e stub//EN", *events, "END:VCALENDAR"]
    return "\r\n".join(lines) + "\r\n"


class Server(ThreadingHTTPServer):
    # The map asks for a few dozen tiles at once. With the default backlog of 5, macOS drops the
    # extra connections (the iOS simulator saw connect timeouts); Linux happened to cope.
    request_queue_size = 128
    daemon_threads = True


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlsplit(self.path)
        path = unquote(url.path)
        query = parse_qs(url.query)

        if path == "/health":
            return self._send(200, "text/plain", b"ok")
        if path.startswith("/tiles/"):
            return self._send(200, "image/png", BLANK_TILE)
        if path == "/calendar/e2e.ics":
            return self._send(200, "text/calendar", ical_feed().encode())

        if path.startswith("/search/2/") and "outage" in path.lower():
            return self._json(503, {"errorText": "Service unavailable (E2E outage)"})
        query = path.removeprefix("/search/2/poiSearch/").removesuffix(".json")
        if path.startswith("/search/2/poiSearch/") and path.endswith(".json") and query:
            return self._json(200, search_response(query))
        if path == "/search/2/nearbySearch/.json":
            return self._json(200, _starting_today(_load("nearby_search")))
        if path == "/search/2/place.json":
            return self._json(200, place_response(query.get("entityId", [""])[0]))
        if path.startswith("/search/2/geocode/"):
            return self._json(200, _load("geocode"))

        self._json(404, {"error": f"The E2E stub doesn't serve {path}"})

    def _json(self, status: int, body: dict):
        self._send(status, "application/json", json.dumps(body).encode())

    def _send(self, status: int, content_type: str, body: bytes):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        # Flutter web fetches tiles from another origin.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        sys.stderr.write(f"stub: {format % args}\n")


if __name__ == "__main__":
    print(f"E2E stub listening on :{PORT}, fixtures from {FIXTURES}", flush=True)
    Server(("", PORT), Handler).serve_forever()
