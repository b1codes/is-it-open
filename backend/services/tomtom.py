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


def _format_time(time: dict) -> str:
    """HH:MM from a TomTom time ({"hour": 9, "minute": 0}). Missing parts are 0."""
    hour, minute = time.get("hour", 0), time.get("minute", 0)
    if not all(isinstance(v, int) and not isinstance(v, bool) for v in (hour, minute)):
        raise ValueError(f"Not a time: {time!r}")
    return f"{hour:02d}:{minute:02d}"


class TomTomClient:
    BASE_URL = "https://api.tomtom.com/search/2"

    def __init__(self):
        self.api_key = settings.TOMTOM_API_KEY

    def search_place(self, query):
        """
        Search for a place using the TomTom POI Search API.
        Returns a list of structured place data suitable for PlaceCreateSchema.
        """
        if not self.api_key:
            return []

        url = f"{self.BASE_URL}/poiSearch/{_path_segment(query)}.json"
        params = {
            "key": self.api_key,
            "limit": 10,
            "openingHours": "nextSevenDays",  # Request opening hours
        }
        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            return self._parse_results(data.get("results") or [])
        except requests.RequestException:
            return []

    def nearby_search(self, lat, lng, radius=5000, limit=10):
        """
        Search for nearby points of interest using TomTom Nearby Search API.
        """
        if not self.api_key:
            return []

        url = f"{self.BASE_URL}/nearbySearch/.json"
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
            data = response.json()
            return self._parse_results(data.get("results") or [])
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
        poi = result.get("poi") or {}
        address = result.get("address") or {}
        position = result.get("position") or {}
        lat, lng = position.get("lat"), position.get("lon")
        if not (result.get("id") and poi.get("name") and _is_coordinate(lat) and _is_coordinate(lng)):
            return None

        hours = self._parse_opening_hours(poi.get("openingHours"))

        categories = []
        for cset in poi.get("categorySet") or []:
            name = cset.get("name") if isinstance(cset, dict) else None
            if name:
                categories.append(name)

        return {
            "tomtom_id": result["id"],
            "name": poi["name"],
            # Construct a readable address
            "address": address.get("freeformAddress")
            or f"{address.get('streetNumber', '')} {address.get('streetName', '')}, {address.get('municipality', '')}",
            "location": {"lat": lat, "lng": lng},
            "phone": poi.get("phone"),
            "website": poi.get("url"),
            "categories": categories,
            "hours": hours,
        }

    def _parse_opening_hours(self, opening_hours_data):
        """
        Parse TomTom openingHours into generic weekly schedule.
        TomTom returns 'nextSevenDays' with specific dates.
        We map these dates to day of week (0-6).
        """
        if not isinstance(opening_hours_data, dict):
            return []

        parsed_hours = []
        # We need to deduplicate by day of week because nextSevenDays might wrap around
        # or we only want the first occurrence of each day.
        seen_days = set()

        # Malformed ranges (missing or null parts, bad dates or times) are skipped.
        for time_range in opening_hours_data.get("timeRanges") or []:
            try:
                start = time_range["startTime"]
                end = time_range["endTime"]
                date_obj = datetime.strptime(start["date"], "%Y-%m-%d")
                day_of_week = date_obj.weekday()  # 0=Monday, 6=Sunday

                if day_of_week in seen_days:
                    continue  # Already have hours for this day (from the 'next 7 days' window, first one is closest)

                open_time = _format_time(start)
                close_time = _format_time(end)
            except (AttributeError, KeyError, TypeError, ValueError):
                continue

            seen_days.add(day_of_week)
            parsed_hours.append({"day_of_week": day_of_week, "open_time": open_time, "close_time": close_time})

        return parsed_hours

    def get_place_details(self, tomtom_id):
        """
        Fetch detailed information about a specific place using its unique identifier.
        """
        if not self.api_key or not tomtom_id:
            return None

        # Use the Place by ID endpoint
        # https://api.tomtom.com/search/2/place.json?entityId={entityId}&key={Your_API_Key}
        url = "https://api.tomtom.com/search/2/place.json"
        params = {
            "key": self.api_key,
            "entityId": tomtom_id,
            "openingHours": "nextSevenDays",
        }
        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            results = data.get("results", [])
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
        address_hash = hashlib.md5(address.strip().lower().encode("utf-8")).hexdigest()
        cache_key = f"geocode_{address_hash}"

        cached_result = cache.get(cache_key)
        if cached_result:
            return cached_result

        url = f"{self.BASE_URL}/geocode/{_path_segment(address)}.json"
        params = {"key": self.api_key, "limit": 1}
        try:
            response = requests.get(url, params=params, timeout=5)
            response.raise_for_status()
            data = response.json()
            results = data.get("results", [])
            if results:
                position = results[0].get("position") or {}
                lat = position.get("lat")
                lon = position.get("lon")
                if lat is not None and lon is not None:
                    result = {"lat": lat, "lon": lon}
                    # Cache for 1 day
                    cache.set(cache_key, result, 86400)
                    return result
        except requests.RequestException:
            pass
        return None
