import hashlib
import math
from datetime import date, datetime, timedelta
from urllib.parse import quote

import requests
from django.conf import settings
from django.core.cache import cache


def _path_segment(text: str) -> str:
    """`text` as one URL path segment, so '/', '?' or '#' in a query or address can't change the URL."""
    return quote(text, safe="")


def _is_coordinate(value) -> bool:
    return isinstance(value, int | float) and not isinstance(value, bool) and math.isfinite(value)


def _is_position(lat, lng) -> bool:
    """Whether (lat, lng) is in LocationSchema's range, so a place there can be returned."""
    return _is_coordinate(lat) and _is_coordinate(lng) and -90 <= lat <= 90 and -180 <= lng <= 180


def _object(value) -> dict:
    """`value` if it's a JSON object, else {}: TomTom fields of the wrong type are treated as missing."""
    return value if isinstance(value, dict) else {}


def _array(value) -> list:
    """`value` if it's a JSON array, else []."""
    return value if isinstance(value, list) else []


def _text(value) -> str | None:
    """`value` if it's a non-empty string, else None."""
    return value if isinstance(value, str) and value else None


def _format_time(time: dict) -> str:
    """HH:MM from a TomTom time ({"hour": 9, "minute": 0}). Missing parts are 0."""
    hour, minute = time.get("hour", 0), time.get("minute", 0)
    if not all(isinstance(v, int) and not isinstance(v, bool) for v in (hour, minute)):
        raise ValueError(f"Not a time: {time!r}")
    # Out of range would break the API contract (BusinessHoursSchema) and the app's time parsing.
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise ValueError(f"Not a time: {time!r}")
    return f"{hour:02d}:{minute:02d}"


def _days_open(start: dict, end: dict, open_time: str, close_time: str) -> list[tuple[date, str, str]]:
    """
    A TomTom time range as (date, open, close) blocks, one per day it's open. A block that closes at
    or before it opens runs past midnight (00:00 to 00:00 is a full day), as the app reads it, so a
    range of up to a day (overnight, 22:00 to 02:00 the next day) is one block on the day it opens.
    A longer one is split at midnight: open until midnight on its first day, all day on the days
    between, and from midnight on its last day, and one of a week or more is all day every day. Read
    as one block, a 24/7 place's range (00:00 one Monday to 00:00 the next) was open on Mondays
    only. Raises ValueError on a bad date, and
    OverflowError on a range reaching past the year 9999.
    """
    start_date = datetime.strptime(start["date"], "%Y-%m-%d").date()
    # Without an end date, it's read as one block, as before end dates were.
    if end.get("date") is None:
        return [(start_date, open_time, close_time)]
    opens_at = datetime.combine(start_date, datetime.strptime(open_time, "%H:%M").time())
    end_date = datetime.strptime(end["date"], "%Y-%m-%d").date()
    closes_at = datetime.combine(end_date, datetime.strptime(close_time, "%H:%M").time())
    if closes_at - opens_at <= timedelta(days=1):
        return [(start_date, open_time, close_time)]

    # A week or more covers every moment of every weekday, so each is open all day. Cut off at seven
    # blocks instead, a range that opened mid-day (a 24/7 place whose window TomTom starts at the
    # current time) kept only the end of its first weekday.
    if closes_at - opens_at >= timedelta(days=7):
        return [(start_date + timedelta(days=i), "00:00", "00:00") for i in range(7)]

    blocks = [(start_date, open_time, "00:00")]
    day = start_date + timedelta(days=1)
    while datetime.combine(day, datetime.min.time()) < closes_at:
        last = closes_at <= datetime.combine(day + timedelta(days=1), datetime.min.time())
        # A range just under a week can end on the weekday it opened (Monday 10:00 to the next
        # Monday 09:00). That block goes on the first date, since a weekday's later dates are
        # dropped as another week's.
        on = day if day - start_date < timedelta(days=7) else start_date
        blocks.append((on, "00:00", close_time if last else "00:00"))
        day += timedelta(days=1)
    return blocks


class GeocodeUnavailable(Exception):
    """TomTom couldn't be asked (no API key) or didn't answer, so whether an address has a match isn't known."""


# Error statuses that say nothing about the address, so a geocode that gets one is tried again later, as
# after a timeout or a 5xx: rejected credentials (a revoked or inactive key, like having none), too many
# requests, and a request timeout.
_GEOCODE_UNAVAILABLE_STATUSES = frozenset({401, 403, 408, 429})


class TomTomClient:
    def __init__(self):
        self.api_key = settings.TOMTOM_API_KEY
        self.base_url = settings.TOMTOM_BASE_URL.rstrip("/")

    def search_place(self, query):
        """
        Search for a place using the TomTom POI Search API.
        Returns a list of structured place data suitable for PlaceCreateSchema.
        """
        if not self.api_key:
            return []

        url = f"{self.base_url}/poiSearch/{_path_segment(query)}.json"
        params = {
            "key": self.api_key,
            "limit": 10,
            "openingHours": "nextSevenDays",  # Request opening hours
        }
        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            return self._parse_results(_array(_object(response.json()).get("results")))
        except requests.RequestException:
            return []

    def nearby_search(self, lat, lng, radius=5000, limit=10):
        """
        Search for nearby points of interest using TomTom Nearby Search API.
        """
        if not self.api_key:
            return []

        url = f"{self.base_url}/nearbySearch/.json"
        params = {
            "key": self.api_key,
            "lat": lat,
            "lon": lng,
            "radius": radius,
            "limit": limit,
            "openingHours": "nextSevenDays",
        }
        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            return self._parse_results(_array(_object(response.json()).get("results")))
        except requests.RequestException:
            return []

    def _parse_results(self, results):
        parsed = []
        for result in results:
            place_data = self._parse_place(result)
            if place_data:
                parsed.append(place_data)
        return parsed

    def _parse_place(self, result):
        """
        A TomTom result as PlaceCreateSchema data, or None if it lacks what a place needs (an ID,
        a name, and a position). Missing or null optional fields get defaults.
        """
        if not isinstance(result, dict):
            return None
        poi = _object(result.get("poi"))
        address = _object(result.get("address"))
        position = _object(result.get("position"))
        tomtom_id, name = _text(result.get("id")), _text(poi.get("name"))
        lat, lng = position.get("lat"), position.get("lon")
        if not (tomtom_id and name and _is_position(lat, lng)):
            return None

        hours = self._parse_opening_hours(poi.get("openingHours"))
        categories = self._parse_categories(poi)

        def part(key):
            return _text(address.get(key)) or ""

        return {
            "tomtom_id": tomtom_id,
            "name": name,
            # Construct a readable address
            "address": _text(address.get("freeformAddress"))
            or f"{part('streetNumber')} {part('streetName')}, {part('municipality')}",
            "location": {"lat": lat, "lng": lng},
            "phone": _text(poi.get("phone")),
            "website": _text(poi.get("url")),
            "categories": categories,
            "hours": hours,
        }

    def _parse_categories(self, poi):
        """
        Category names, most specific first, from `classifications[].names` (TomTom's current
        field), else the deprecated `categories` list. `categorySet` only has numeric IDs, so
        reading names from it (as this used to) gave every place an empty list.
        """
        names: list[str] = []

        def add(name):
            if isinstance(name, str) and name and name not in names:
                names.append(name)

        for classification in _array(poi.get("classifications")):
            for entry in _array(_object(classification).get("names")):
                add(_object(entry).get("name"))
        if not names:
            for name in _array(poi.get("categories")):
                add(name)
        return names

    def _parse_opening_hours(self, opening_hours_data):
        """
        Parse TomTom openingHours into generic weekly schedule.
        TomTom returns 'nextSevenDays' with specific dates.
        We map these dates to day of week (0-6).
        """
        if not isinstance(opening_hours_data, dict):
            return []

        parsed_hours = []
        # nextSevenDays can reach the same weekday twice (today and a week from today); the first
        # date seen for a weekday is the closest, so only its ranges are kept. A split day (open
        # 11:00-14:00 and 17:00-22:00) has several ranges on that one date, and all of them count.
        first_date_of_day: dict[int, date] = {}

        # Malformed ranges (missing or null parts, bad dates or times) are skipped.
        for time_range in _array(opening_hours_data.get("timeRanges")):
            try:
                start = time_range["startTime"]
                end = time_range["endTime"]
                days = _days_open(start, end, _format_time(start), _format_time(end))
            except (AttributeError, KeyError, OverflowError, TypeError, ValueError):
                continue

            for day, open_time, close_time in days:
                day_of_week = day.weekday()  # 0=Monday, 6=Sunday
                if first_date_of_day.get(day_of_week, day) != day:
                    continue  # A later week's date for a weekday we already have
                first_date_of_day[day_of_week] = day
                block = {"day_of_week": day_of_week, "open_time": open_time, "close_time": close_time}
                if block not in parsed_hours:
                    parsed_hours.append(block)

        return parsed_hours

    def get_place_details(self, tomtom_id):
        """
        Fetch detailed information about a specific place using its unique identifier.
        """
        if not self.api_key or not tomtom_id:
            return None

        # Use the Place by ID endpoint: {base}/place.json?entityId={entityId}&key={Your_API_Key}
        url = f"{self.base_url}/place.json"
        params = {
            "key": self.api_key,
            "entityId": tomtom_id,
            "openingHours": "nextSevenDays",
        }
        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            results = _array(_object(response.json()).get("results"))
            if results:
                return self._parse_place(results[0])
        except requests.RequestException:
            pass
        return None

    def geocode_address(self, address: str):
        """
        Geocode an address string using TomTom Search API.
        Returns a dict with 'lat' and 'lon' keys, or None if TomTom has no match, rejects the address
        (a 4xx other than those below), or no address was given. Raises GeocodeUnavailable without an
        API key, when the request fails, or on a 5xx, 401, 403, 408 or 429.
        """
        if not address:
            return None
        if not self.api_key:
            raise GeocodeUnavailable("no TomTom API key")

        # Create a stable cache key
        address_hash = hashlib.md5(address.strip().lower().encode("utf-8"), usedforsecurity=False).hexdigest()
        cache_key = f"geocode_{address_hash}"

        cached_result = cache.get(cache_key)
        if cached_result:
            return cached_result

        url = f"{self.base_url}/geocode/{_path_segment(address)}.json"
        params = {"key": self.api_key, "limit": 1}
        try:
            response = requests.get(url, params=params, timeout=5)
            if response.status_code in _GEOCODE_UNAVAILABLE_STATUSES or response.status_code >= 500:
                raise GeocodeUnavailable(f"TomTom answered {response.status_code}")
            # Any other error is TomTom's answer about this address (a 400: one it can't read), which
            # asking again won't change. Treated as unavailable, it kept the geocode pending for good,
            # so each later profile save asked again and the old address's coordinates stayed.
            if response.status_code >= 400:
                return None
            body = response.json()
        except requests.RequestException as error:
            raise GeocodeUnavailable(str(error)) from error
        results = _array(_object(body).get("results"))
        if results:
            position = _object(_object(results[0]).get("position"))
            lat = position.get("lat")
            lon = position.get("lon")
            if _is_coordinate(lat) and _is_coordinate(lon):
                result = {"lat": lat, "lon": lon}
                # Cache for 1 day
                cache.set(cache_key, result, 86400)
                return result
        return None
