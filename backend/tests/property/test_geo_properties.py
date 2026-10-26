"""Property-based tests for services/geo.py: geohashes, nearby-search coverings, and distances."""

import math

from hypothesis import assume, given
from hypothesis import strategies as st

from services.geo import (
    _BASE32,
    _EARTH_RADIUS_KM,
    MAX_QUERY_CELLS_FALLBACK,
    MAX_RADIUS_KM,
    distance_km,
    encode_geohash,
    geohash_query_prefixes,
)

lats = st.floats(-90, 90)
lngs = st.floats(-180, 180)
radii = st.floats(0.001, MAX_RADIUS_KM)
precisions = st.integers(1, 12)


def decode_cell(geohash: str):
    """The (lat_min, lat_max, lng_min, lng_max) cell a geohash names."""
    lat, lng = [-90.0, 90.0], [-180.0, 180.0]
    is_lng = True
    for char in geohash:
        bits = _BASE32.index(char)
        for shift in range(4, -1, -1):
            rng = lng if is_lng else lat
            mid = (rng[0] + rng[1]) / 2
            if bits >> shift & 1:
                rng[0] = mid
            else:
                rng[1] = mid
            is_lng = not is_lng
    return lat[0], lat[1], lng[0], lng[1]


def destination(lat, lng, bearing_deg, km):
    """The point `km` from (lat, lng) along `bearing_deg` on the sphere."""
    d = km / _EARTH_RADIUS_KM
    phi1, lmb1, theta = math.radians(lat), math.radians(lng), math.radians(bearing_deg)
    phi2 = math.asin(max(-1.0, min(1.0, math.sin(phi1) * math.cos(d) + math.cos(phi1) * math.sin(d) * math.cos(theta))))
    lmb2 = lmb1 + math.atan2(
        math.sin(theta) * math.sin(d) * math.cos(phi1), math.cos(d) - math.sin(phi1) * math.sin(phi2)
    )
    return math.degrees(phi2), (math.degrees(lmb2) + 180) % 360 - 180


@given(lats, lngs, precisions)
def test_geohash_has_the_requested_length_and_alphabet(lat, lng, precision):
    geohash = encode_geohash(lat, lng, precision)

    assert len(geohash) == precision
    assert set(geohash) <= set(_BASE32)


@given(lats, lngs, precisions)
def test_coarser_geohash_is_a_prefix(lat, lng, precision):
    assert encode_geohash(lat, lng, precision + 1).startswith(encode_geohash(lat, lng, precision))


@given(lats, lngs, precisions)
def test_point_lies_in_its_geohash_cell(lat, lng, precision):
    lat_min, lat_max, lng_min, lng_max = decode_cell(encode_geohash(lat, lng, precision))

    assert lat_min <= lat <= lat_max
    assert lng_min <= lng <= lng_max


@given(lats, lngs, lats, lngs)
def test_distance_is_symmetric_non_negative_and_bounded(lat1, lng1, lat2, lng2):
    d = distance_km(lat1, lng1, lat2, lng2)

    assert 0 <= d <= math.pi * _EARTH_RADIUS_KM + 1e-6
    assert d == distance_km(lat2, lng2, lat1, lng1)


@given(lats, lngs)
def test_distance_to_self_is_zero(lat, lng):
    assert distance_km(lat, lng, lat, lng) == 0


@given(lats, lngs, lats, lngs, lats, lngs)
def test_distance_triangle_inequality(lat1, lng1, lat2, lng2, lat3, lng3):
    direct = distance_km(lat1, lng1, lat3, lng3)
    via = distance_km(lat1, lng1, lat2, lng2) + distance_km(lat2, lng2, lat3, lng3)

    # Haversine loses precision near antipodal points (asin of ~1): about a centimetre at 20,000 km.
    assert direct <= via + 1e-3


@given(lats, lngs, radii, st.floats(0, 360), st.floats(0, 1))
def test_covering_contains_every_point_in_the_circle(lat, lng, radius_km, bearing, fraction):
    prefixes = geohash_query_prefixes(lat, lng, radius_km)
    point = destination(lat, lng, bearing, radius_km * fraction)
    assume(distance_km(lat, lng, *point) <= radius_km)

    geohash = encode_geohash(*point)
    assert any(geohash.startswith(p) for p in prefixes), (point, prefixes)


@given(lats, lngs, radii)
def test_covering_is_bounded_and_never_matches_everything(lat, lng, radius_km):
    prefixes = geohash_query_prefixes(lat, lng, radius_km)

    assert 1 <= len(prefixes) <= MAX_QUERY_CELLS_FALLBACK
    assert all(prefixes)
    assert prefixes == sorted(set(prefixes))


@given(lats, lngs, radii, st.integers(-3, 3))
def test_covering_ignores_whole_turns_of_longitude(lat, lng, radius_km, turns):
    shifted = lng + 360 * turns
    assume(abs(((shifted + 180) % 360 - 180) - ((lng + 180) % 360 - 180)) < 1e-9)  # no float drift

    assert geohash_query_prefixes(lat, shifted, radius_km) == geohash_query_prefixes(lat, lng, radius_km)
