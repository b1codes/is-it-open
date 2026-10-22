import hashlib
import math
from datetime import datetime
from urllib.parse import quote

import requests
from django.conf import settings
from django.core.cache import cache


def _path_segment(text: str) -> str:
    """`text` as one URL path segment, so '/', '?' or '#' in a query or address can't change the URL."""
    return quote(text, safe="")


def _is_coordinate(value) -> bool:
    return isinstance(value, int | float) and not isinstance(value, bool) and math.isfinite(value)


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
        if not (tomtom_id and name and _is_coordinate(lat) and _is_coordinate(lng)):
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
        first_date_of_day: dict[int, str] = {}

        # Malformed ranges (missing or null parts, bad dates or times) are skipped.
        for time_range in _array(opening_hours_data.get("timeRanges")):
            try:
                start = time_range["startTime"]
                end = time_range["endTime"]
                date = start["date"]
                day_of_week = datetime.strptime(date, "%Y-%m-%d").weekday()  # 0=Monday, 6=Sunday
                if first_date_of_day.get(day_of_week, date) != date:
                    continue  # A later week's date for a weekday we already have

                open_time = _format_time(start)
                close_time = _format_time(end)
            except (AttributeError, KeyError, TypeError, ValueError):
                continue

            first_date_of_day[day_of_week] = date
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
        Returns a dict with 'lat' and 'lon' keys, or None if not found or error.
        """
        if not self.api_key or not address:
            return None

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
            response.raise_for_status()
            results = _array(_object(response.json()).get("results"))
            if results:
                position = _object(_object(results[0]).get("position"))
                lat = position.get("lat")
                lon = position.get("lon")
                if _is_coordinate(lat) and _is_coordinate(lon):
                    result = {"lat": lat, "lon": lon}
                    # Cache for 1 day
                    cache.set(cache_key, result, 86400)
                    return result
        except requests.RequestException:
            pass
        return None
