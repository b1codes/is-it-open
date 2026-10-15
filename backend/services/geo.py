import math

_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"
_EARTH_RADIUS_KM = 6371.0088
_KM_PER_DEGREE = 111.32
GEOHASH_PRECISION = 10


def encode_geohash(lat: float, lng: float, precision: int = GEOHASH_PRECISION) -> str:
    lat_range = [-90.0, 90.0]
    lng_range = [-180.0, 180.0]
    chars = []
    bits = 0
    bit_count = 0
    use_lng = True

    while len(chars) < precision:
        value, rng = (lng, lng_range) if use_lng else (lat, lat_range)
        mid = (rng[0] + rng[1]) / 2
        if value >= mid:
            bits = bits * 2 + 1
            rng[0] = mid
        else:
            bits *= 2
            rng[1] = mid
        use_lng = not use_lng

        bit_count += 1
        if bit_count == 5:
            chars.append(_BASE32[bits])
            bits = 0
            bit_count = 0

    return "".join(chars)


def _cell_size_degrees(precision: int):
    total_bits = precision * 5
    lat_bits = total_bits // 2
    lng_bits = total_bits - lat_bits
    return 180.0 / (2 ** lat_bits), 360.0 / (2 ** lng_bits)


def geohash_query_prefixes(lat: float, lng: float, radius_km: float):
    """
    Geohash prefixes whose cells together cover every point within `radius_km` of (lat, lng).

    Picks the finest precision whose cells are at least `radius_km` on each side, then returns
    the center cell plus its 8 neighbours. Returns [""] (match everything) for huge radii.
    """
    cos_lat = max(math.cos(math.radians(lat)), 1e-9)

    for precision in range(GEOHASH_PRECISION, 0, -1):
        lat_deg, lng_deg = _cell_size_degrees(precision)
        if lat_deg * _KM_PER_DEGREE >= radius_km and lng_deg * _KM_PER_DEGREE * cos_lat >= radius_km:
            break
    else:
        return [""]

    prefixes = set()
    for dlat in (-lat_deg, 0.0, lat_deg):
        for dlng in (-lng_deg, 0.0, lng_deg):
            cell_lat = min(max(lat + dlat, -90.0), 90.0)
            cell_lng = (lng + dlng + 180.0) % 360.0 - 180.0
            prefixes.add(encode_geohash(cell_lat, cell_lng, precision))
    return sorted(prefixes)


def distance_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle (haversine) distance in kilometres."""
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = phi2 - phi1
    dlmb = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlmb / 2) ** 2
    return 2 * _EARTH_RADIUS_KM * math.asin(math.sqrt(a))
