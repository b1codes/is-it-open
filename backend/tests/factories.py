"""
Builders for test data: request payloads and TomTom API responses.

The fixtures in tests/conftest.py use these to create users, places, and bookmarks in the
emulator; tests can also call them directly to build payloads.
"""

import itertools

_ids = itertools.count(1)


def unique_id(prefix: str) -> str:
    return f"{prefix}{next(_ids)}"


def hours(*entries):
    """[(day_of_week, open_time, close_time), ...] as BusinessHoursSchema dicts."""
    return [{"day_of_week": d, "open_time": o, "close_time": c} for d, o, c in entries]


def place_data(tomtom_id=None, name="Test Place", lat=40.7128, lng=-74.0060, **extra) -> dict:
    """A place payload shaped like PlaceCreateSchema (and TomTomClient's parsed results)."""
    return {
        "tomtom_id": tomtom_id or unique_id("place-"),
        "name": name,
        "address": "123 Test St",
        "location": {"lat": lat, "lng": lng},
        **extra,
    }


def tomtom_time_range(date, open_hm=(9, 0), close_hm=(17, 0)) -> dict:
    """One TomTom openingHours timeRange on `date` (YYYY-MM-DD)."""
    return {
        "startTime": {"date": date, "hour": open_hm[0], "minute": open_hm[1]},
        "endTime": {"date": date, "hour": close_hm[0], "minute": close_hm[1]},
    }


def tomtom_result(
    id="tt-1", name="Test Place", lat=10.0, lon=20.0, time_ranges=None, categories=("Restaurant",), **poi
) -> dict:
    """One result from a TomTom search response."""
    result_poi = {
        "name": name,
        "phone": "+1 555-0100",
        "url": "https://example.com",
        # Shaped like TomTom's: categorySet has only IDs; the names are in classifications (and in
        # the deprecated categories list).
        "categorySet": [{"id": 7315000 + i} for i, _ in enumerate(categories)],
        "categories": [c.lower() for c in categories],
        "classifications": [{"code": c.upper(), "names": [{"nameLocale": "en-US", "name": c}]} for c in categories],
        **poi,
    }
    if time_ranges is not None:
        result_poi["openingHours"] = {"mode": "nextSevenDays", "timeRanges": time_ranges}
    return {
        "type": "POI",
        "id": id,
        "poi": result_poi,
        "address": {"freeformAddress": "123 Test St, Testville"},
        "position": {"lat": lat, "lon": lon},
    }


def tomtom_response(*results) -> dict:
    return {"summary": {"numResults": len(results)}, "results": list(results)}
