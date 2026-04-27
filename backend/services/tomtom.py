import requests
from django.conf import settings
from datetime import datetime
from django.core.cache import cache
import hashlib

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

        url = f"{self.BASE_URL}/poiSearch/{query}.json"
        params = {
            "key": self.api_key,
            "limit": 10,
            "openingHours": "nextSevenDays", # Request opening hours
        }
        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            return self._parse_results(data.get('results', []))
        except requests.RequestException:
            return []

    def _parse_results(self, results):
        parsed = []
        for result in results:
            poi = result.get('poi', {})
            address = result.get('address', {})
            position = result.get('position', {})
            
            hours = self._parse_opening_hours(poi.get('openingHours', {}))
            
            categories = []
            for cset in poi.get('categorySet', []):
                name = cset.get('name')
                if name:
                    categories.append(name)

            place_data = {
                "tomtom_id": result.get('id'),
                "name": poi.get('name'),
                # Construct a readable address
                "address": address.get('freeformAddress', 
                    f"{address.get('streetNumber', '')} {address.get('streetName', '')}, {address.get('municipality', '')}"
                ),
                "location": {
                    "lat": position.get('lat'),
                    "lng": position.get('lon')
                },
                "phone": poi.get('phone'),
                "website": poi.get('url'),
                "categories": categories,
                "hours": hours
            }
            parsed.append(place_data)
        return parsed

    def _parse_opening_hours(self, opening_hours_data):
        """
        Parse TomTom openingHours into generic weekly schedule.
        TomTom returns 'nextSevenDays' with specific dates. 
        We map these dates to day of week (0-6).
        """
        if not opening_hours_data or 'timeRanges' not in opening_hours_data:
            return []

        parsed_hours = []
        # We need to deduplicate by day of week because nextSevenDays might wrap around 
        # or we only want the first occurrence of each day.
        seen_days = set()

        for time_range in opening_hours_data.get('timeRanges', []):
            start = time_range.get('startTime', {})
            end = time_range.get('endTime', {})
            
            date_str = start.get('date')
            if not date_str:
                continue
                
            try:
                date_obj = datetime.strptime(date_str, "%Y-%m-%d")
                day_of_week = date_obj.weekday() # 0=Monday, 6=Sunday
                
                if day_of_week in seen_days:
                    continue # Already have hours for this day (from the 'next 7 days' window, first one is closest)
                
                seen_days.add(day_of_week)

                open_time = f"{start.get('hour', 0):02d}:{start.get('minute', 0):02d}"
                close_time = f"{end.get('hour', 0):02d}:{end.get('minute', 0):02d}"

                parsed_hours.append({
                    "day_of_week": day_of_week,
                    "open_time": open_time,
                    "close_time": close_time
                })
            except ValueError:
                continue
                
        return parsed_hours

    def get_place_details(self, tomtom_id):
        # We can implement this later if needed, but search covers it.
        pass

    def geocode_address(self, address: str):
        """
        Geocode an address string using TomTom Search API.
        Returns a dict with 'lat' and 'lon' keys, or None if not found or error.
        """
        if not self.api_key or not address:
            return None

        # Create a stable cache key
        address_hash = hashlib.md5(address.strip().lower().encode('utf-8')).hexdigest()
        cache_key = f"geocode_{address_hash}"
        
        cached_result = cache.get(cache_key)
        if cached_result:
            return cached_result

        url = f"{self.BASE_URL}/geocode/{address}.json"
        params = {
            "key": self.api_key,
            "limit": 1
        }
        try:
            response = requests.get(url, params=params, timeout=5)
            response.raise_for_status()
            data = response.json()
            results = data.get('results', [])
            if results:
                position = results[0].get('position', {})
                lat = position.get('lat')
                lon = position.get('lon')
                if lat is not None and lon is not None:
                    result = {'lat': lat, 'lon': lon}
                    # Cache for 1 day
                    cache.set(cache_key, result, 86400)
                    return result
        except requests.RequestException:
            pass
        return None
