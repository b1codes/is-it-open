import math

_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"
_EARTH_RADIUS_KM = 6371.0088
GEOHASH_PRECISION = 10

# Largest radius geohash_query_prefixes accepts. Keeps every covering to a small region, so a
# nearby search can never turn into a scan of (most of) the collection.
MAX_RADIUS_KM = 50.0

# Prefix queries per nearby search: prefer few, fall back to more when few are far too coarse
# (high latitudes, where geohash cells get narrow and a circle spans many of them).
MAX_QUERY_CELLS = 9
MAX_QUERY_CELLS_FALLBACK = 32
# A covering whose cells are this many times larger than the search box (in either dimension)
# reads far more than it needs to, so the fallback budget is tried.
_COARSE_FACTOR = 4
# Pads the bounding box so floating-point error can't drop a point sitting on its edge (~1 cm).
_EDGE_MARGIN_DEG = 1e-7


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


def _grid(precision: int):
    """(rows, cols, cell height in degrees, cell width in degrees) of the geohash grid."""
    total_bits = precision * 5
    lat_bits = total_bits // 2
    lng_bits = total_bits - lat_bits
    rows, cols = 2**lat_bits, 2**lng_bits
    return rows, cols, 180.0 / rows, 360.0 / cols


def _bounding_box(lat: float, lng: float, radius_km: float):
    """
    (lat_min, lat_max, [(lng_lo, lng_hi), ...]) containing every point within `radius_km`.

    Longitude ranges are split at the antimeridian. A circle containing a pole spans every
    longitude. Otherwise its exact half-width is asin(sin(d) / cos(lat)) for angular radius d.
    """
    angular = radius_km / _EARTH_RADIUS_KM
    dlat = math.degrees(angular) + _EDGE_MARGIN_DEG
    lat_min, lat_max = lat - dlat, lat + dlat
    if lat_min <= -90.0 or lat_max >= 90.0:
        return max(lat_min, -90.0), min(lat_max, 90.0), [(-180.0, 180.0)]

    ratio = math.sin(angular) / math.cos(math.radians(lat))
    dlng = math.degrees(math.asin(min(ratio, 1.0))) + _EDGE_MARGIN_DEG
    lng_min, lng_max = lng - dlng, lng + dlng
    if lng_min < -180.0:
        return lat_min, lat_max, [(lng_min + 360.0, 180.0), (-180.0, lng_max)]
    if lng_max > 180.0:
        return lat_min, lat_max, [(lng_min, 180.0), (-180.0, lng_max - 360.0)]
    return lat_min, lat_max, [(lng_min, lng_max)]


def _span(lo: float, hi: float, origin: float, size: float, count: int):
    """Indices of the first and last grid cells (of `size` degrees from `origin`) touching [lo, hi]."""
    first = min(max(math.floor((lo - origin) / size), 0), count - 1)
    last = min(max(math.floor((hi - origin) / size), 0), count - 1)
    return first, last


def _covering(precision: int, box):
    lat_min, lat_max, lng_ranges = box
    rows, cols, lat_size, lng_size = _grid(precision)
    row_span = _span(lat_min, lat_max, -90.0, lat_size, rows)
    col_spans = [_span(lo, hi, -180.0, lng_size, cols) for lo, hi in lng_ranges]
    n_cols = min(sum(last - first + 1 for first, last in col_spans), cols)
    count = (row_span[1] - row_span[0] + 1) * n_cols
    return count, row_span, col_spans, lat_size, lng_size


def _is_coarse(covering, box) -> bool:
    lat_min, lat_max, lng_ranges = box
    _, _, _, lat_size, lng_size = covering
    box_height = lat_max - lat_min
    box_width = sum(hi - lo for lo, hi in lng_ranges)
    return lat_size > _COARSE_FACTOR * box_height or lng_size > _COARSE_FACTOR * box_width


def geohash_query_prefixes(lat: float, lng: float, radius_km: float):
    """
    Geohash prefixes whose cells together cover every point within `radius_km` of (lat, lng).

    Covers the circle's bounding box (antimeridian- and pole-aware) with the finest grid that
    needs at most MAX_QUERY_CELLS cells, or up to MAX_QUERY_CELLS_FALLBACK when that grid is
    much coarser than the box. Never returns an empty prefix (which would match the whole
    collection): raises ValueError if the inputs are out of range (including a radius above
    MAX_RADIUS_KM) or the circle can't be covered with that many cells.
    """
    if not (math.isfinite(lat) and -90.0 <= lat <= 90.0):
        raise ValueError(f"lat must be within [-90, 90], got {lat}")
    if not math.isfinite(lng):
        raise ValueError(f"lng must be finite, got {lng}")
    if not (math.isfinite(radius_km) and 0 < radius_km <= MAX_RADIUS_KM):
        raise ValueError(f"radius_km must be within (0, {MAX_RADIUS_KM}], got {radius_km}")

    lng = (lng + 180.0) % 360.0 - 180.0
    box = _bounding_box(lat, lng, radius_km)

    # Cell counts only grow with precision, so stop at the first grid over budget.
    fits = {MAX_QUERY_CELLS: None, MAX_QUERY_CELLS_FALLBACK: None}
    for precision in range(1, GEOHASH_PRECISION + 1):
        covering = _covering(precision, box)
        if covering[0] > MAX_QUERY_CELLS_FALLBACK:
            break
        for budget in fits:
            if covering[0] <= budget:
                fits[budget] = (precision, covering)

    chosen = fits[MAX_QUERY_CELLS]
    if chosen is None or _is_coarse(chosen[1], box):
        chosen = fits[MAX_QUERY_CELLS_FALLBACK] or chosen
    if chosen is None:
        raise ValueError(f"radius_km={radius_km} is too large to query by geohash")

    precision, (_, (row_first, row_last), col_spans, lat_size, lng_size) = chosen
    cols = {col for first, last in col_spans for col in range(first, last + 1)}
    return sorted(
        encode_geohash(-90.0 + (row + 0.5) * lat_size, -180.0 + (col + 0.5) * lng_size, precision)
        for row in range(row_first, row_last + 1)
        for col in cols
    )


def distance_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle (haversine) distance in kilometres."""
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = phi2 - phi1
    dlmb = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlmb / 2) ** 2
    return 2 * _EARTH_RADIUS_KM * math.asin(math.sqrt(a))
