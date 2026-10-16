"""
Manual check against the live TomTom API: prints the raw POI search response for "pizza" near NYC.

Not part of the test suite (it needs a real key and network access; the suite mocks TomTom). Run
from backend/ with TOMTOM_API_KEY in .env:

    uv run python scripts/check_tomtom.py
"""

import json

import requests

# Load key from .env manually since we are running as a script
try:
    with open(".env") as f:
        for line in f:
            if "TOMTOM_API_KEY" in line:
                key = line.split("=")[1].strip().strip("'")
                break
except OSError:
    print("Could not load .env")
    exit(1)

url = "https://api.tomtom.com/search/2/poiSearch/pizza.json"
params = {
    "key": key,
    "limit": 1,
    "lat": 40.7128,  # NY
    "lon": -74.0060,
    "openingHours": "nextSevenDays",
}

response = requests.get(url, params=params)
data = response.json()

print(json.dumps(data, indent=2))
