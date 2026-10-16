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
    "openingHours": "nextSevenDays",  # Try to request hours? Documentation doesn't say we need to request it explicitly usually, but let's see.
}

response = requests.get(url, params=params)
data = response.json()

print(json.dumps(data, indent=2))
