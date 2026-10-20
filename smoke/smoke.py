"""
Post-deploy smoke test: a few requests that show a deployed backend works end to end. It checks the
health check, signing in, a place search (TomTom), and a bookmark round trip (Firestore reads and
writes), and it leaves the account as it found it. See smoke/README.md.

    SMOKE_USERNAME=... SMOKE_PASSWORD=... python3 smoke/smoke.py https://api.example.com

The account must already exist; the smoke test never creates one. Standard library only, so it runs
anywhere with Python 3.11+.

Environment:
    SMOKE_USERNAME, SMOKE_PASSWORD   the test account (required)
    SMOKE_QUERY                      what to search for (default: pizza)
    SMOKE_WAIT                       seconds to wait for /health to answer, e.g. right after a
                                     deploy (default: 60)
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable
from typing import Any

TIMEOUT = 30  # seconds per request


class SmokeFailure(Exception):
    pass


class Api:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")
        self.token: str | None = None

    def request(self, method: str, path: str, body: Any = None, **params) -> tuple[int, Any]:
        """Sends a request and returns the status and the decoded JSON body (None if empty)."""
        url = self.base_url + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        headers = {"Accept": "application/json", "User-Agent": "is-it-open-smoke"}
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            # main() only accepts an http(s) base URL.
            with urllib.request.urlopen(request, timeout=TIMEOUT) as response:  # nosec B310
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read()
        except (urllib.error.URLError, TimeoutError) as error:
            raise SmokeFailure(f"{method} {path}: {error}") from None
        try:
            return status, json.loads(raw) if raw else None
        except ValueError:
            raise SmokeFailure(f"{method} {path}: {status}, not JSON: {raw[:200]!r}") from None

    def expect(self, status: int, method: str, path: str, body: Any = None, **params) -> Any:
        actual, data = self.request(method, path, body, **params)
        if actual != status:
            raise SmokeFailure(f"{method} {path}: expected {status}, got {actual}: {json.dumps(data)[:300]}")
        return data


def wait_for_health(api: Api, wait: float) -> str:
    deadline = time.monotonic() + wait
    while True:
        try:
            status, data = api.request("GET", "/health")
            if status == 200 and data == {"status": "ok"}:
                return "ok"
            problem = f"GET /health: {status} {data}"
        except SmokeFailure as error:
            problem = str(error)
        if time.monotonic() >= deadline:
            raise SmokeFailure(f"{problem} (gave up after {wait:.0f}s)")
        time.sleep(2)


def bookmarked_ids(api: Api) -> set[str]:
    return {saved["place"]["tomtom_id"] for saved in api.expect(200, "GET", "/api/places/bookmarks")}


def check(name: str, step: Callable[[], str]) -> None:
    """Runs one check and prints its outcome. Raises SmokeFailure if it fails."""
    start = time.monotonic()
    try:
        detail = step()
    except SmokeFailure as error:
        print(f"FAIL  {name}: {error}", flush=True)
        raise
    print(f"ok    {name} ({(time.monotonic() - start) * 1000:.0f} ms): {detail}", flush=True)


def run(base_url: str, username: str, password: str, query: str, wait: float) -> None:
    """Runs the checks in order. Raises SmokeFailure on the first that fails."""
    api = Api(base_url)

    check("health", lambda: wait_for_health(api, wait))

    def sign_in() -> str:
        api.token = api.expect(200, "POST", "/api/auth/login", {"username": username, "password": password})["token"]
        me = api.expect(200, "GET", "/api/auth/me")
        if me["username"] != username:
            raise SmokeFailure(f"GET /api/auth/me: signed in as {me['username']!r}, not {username!r}")
        return f"signed in as {username}"

    check("sign in", sign_in)

    already_saved: set[str] = set()
    place: dict = {}

    def search() -> str:
        found = api.expect(200, "GET", "/api/places/search", query=query)
        if not found:
            raise SmokeFailure(f"GET /api/places/search: no results for {query!r}")
        already_saved.update(bookmarked_ids(api))
        # A place the account hasn't saved, so the round trip below starts and ends with it unsaved.
        unsaved = [p for p in found if p["tomtom_id"] not in already_saved]
        if not unsaved:
            raise SmokeFailure(f"the account already saved every result for {query!r}; set SMOKE_QUERY")
        place.update(unsaved[0])
        return f"{len(found)} results for {query!r}"

    check("search", search)

    tomtom_id = place["tomtom_id"]
    path = f"/api/places/bookmarks/{urllib.parse.quote(tomtom_id, safe='')}"

    def round_trip() -> str:
        # The app saves a search result as a place before bookmarking it (ApiService.createPlace).
        api.expect(200, "POST", "/api/places/", place)
        saved = api.expect(200, "POST", "/api/places/bookmark", {"tomtom_id": tomtom_id})
        if saved["place"]["tomtom_id"] != tomtom_id:
            raise SmokeFailure(f"POST /api/places/bookmark saved {saved['place']['tomtom_id']}, not {tomtom_id}")
        try:
            if tomtom_id not in bookmarked_ids(api):
                raise SmokeFailure(f"GET /api/places/bookmarks doesn't list {tomtom_id} after saving it")
        finally:
            api.expect(204, "DELETE", path)
        if tomtom_id in bookmarked_ids(api):
            raise SmokeFailure(f"GET /api/places/bookmarks still lists {tomtom_id} after deleting it")
        return f"saved, listed and deleted {place['name']!r}"

    check("bookmark round trip", round_trip)


def main(argv: list[str]) -> int:
    if len(argv) != 2 or not argv[1].startswith(("http://", "https://")):
        print(__doc__, file=sys.stderr)
        return 2
    username, password = os.environ.get("SMOKE_USERNAME"), os.environ.get("SMOKE_PASSWORD")
    if not username or not password:
        print("Set SMOKE_USERNAME and SMOKE_PASSWORD to the test account.", file=sys.stderr)
        return 2

    print(f"Smoke testing {argv[1]}", flush=True)
    try:
        run(
            argv[1],
            username,
            password,
            query=os.environ.get("SMOKE_QUERY") or "pizza",
            wait=float(os.environ.get("SMOKE_WAIT") or 60),
        )
    except SmokeFailure:
        return 1
    print("All checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
