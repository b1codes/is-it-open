"""services/geo.py: geohash encoding, nearby-search coverings, and great-circle distance.

Pure functions, no emulator. tests/property/test_geo_properties.py checks the same functions
against randomly generated inputs.
"""

import math

import pytest

from services.geo import (
    _EARTH_RADIUS_KM,
    GEOHASH_PRECISION,
    MAX_QUERY_CELLS,
    MAX_QUERY_CELLS_FALLBACK,
    MAX_RADIUS_KM,
    distance_km,
    encode_geohash,
    geohash_query_prefixes,
)


class TestEncodeGeohash:
    @pytest.mark.parametrize(
        "lat, lng, expected",
        [
            (57.64911, 10.40744, "u4pruydqqv"),  # the example on Wikipedia's Geohash page
            (40.7128, -74.0060, "dr5regw3pp"),
            (0.0, 0.0, "s000000000"),
            (-90.0, -180.0, "0000000000"),
            (90.0, 180.0, "zzzzzzzzzz"),
        ],
    )
    def test_known_values(self, lat, lng, expected):
        assert encode_geohash(lat, lng) == expected

    def test_default_precision(self):
        assert len(encode_geohash(1.0, 2.0)) == GEOHASH_PRECISION

    @pytest.mark.parametrize("precision", [1, 5, 12])
    def test_precision_is_a_prefix_of_the_full_hash(self, precision):
        full = encode_geohash(40.7128, -74.0060, 12)

        assert encode_geohash(40.7128, -74.0060, precision) == full[:precision]


class TestDistanceKm:
    def test_same_point_is_zero(self):
        assert distance_km(40.7, -74.0, 40.7, -74.0) == 0

    def test_one_degree_of_latitude(self):
        assert distance_km(0, 0, 1, 0) == pytest.approx(111.195, abs=0.001)

    def test_new_york_to_london(self):
        assert distance_km(40.7128, -74.0060, 51.5074, -0.1278) == pytest.approx(5570, rel=0.001)

    def test_antipodes_are_half_the_circumference(self):
        assert distance_km(0, 0, 0, 180) == pytest.approx(math.pi * _EARTH_RADIUS_KM)

    def test_across_the_antimeridian(self):
        assert distance_km(0, 179.5, 0, -179.5) == pytest.approx(111.195, abs=0.001)


class TestGeohashQueryPrefixes:
    def test_small_circle_is_one_prefix(self):
        assert geohash_query_prefixes(40.7, -74.0, 5) == ["dr5r"]

    def test_tiny_circle_uses_fine_cells(self):
        assert geohash_query_prefixes(40.7, -74.0, 0.01) == ["dr5rs14y", "dr5rs14z"]

    def test_prefixes_are_sorted_distinct_and_non_empty(self):
        prefixes = geohash_query_prefixes(0.0, 0.0, 1)

        assert prefixes == sorted(set(prefixes))
        assert all(prefixes)
        assert len(prefixes) <= MAX_QUERY_CELLS

    @pytest.mark.parametrize("lat", [85.0, -85.0, 89.9])
    def test_high_latitudes_stay_within_the_fallback_budget(self, lat):
        assert 1 <= len(geohash_query_prefixes(lat, 0.0, 1)) <= MAX_QUERY_CELLS_FALLBACK

    @pytest.mark.parametrize("lng, equivalent", [(190.0, -170.0), (-190.0, 170.0), (360.0, 0.0), (540.0, 180.0)])
    def test_longitude_is_normalized(self, lng, equivalent):
        assert geohash_query_prefixes(10.0, lng, 5) == geohash_query_prefixes(10.0, equivalent, 5)

    def test_pole_covers_every_longitude(self):
        prefixes = geohash_query_prefixes(90.0, 0.0, 5)

        for lng in (-180.0, -90.0, 0.0, 90.0, 179.9):
            assert any(encode_geohash(89.99, lng).startswith(p) for p in prefixes)

    def test_largest_radius_is_accepted(self):
        assert geohash_query_prefixes(0.0, 0.0, MAX_RADIUS_KM)

    @pytest.mark.parametrize(
        "lat, lng, radius_km, message",
        [
            (90.1, 0.0, 5, "lat"),
            (-90.1, 0.0, 5, "lat"),
            (math.nan, 0.0, 5, "lat"),
            (math.inf, 0.0, 5, "lat"),
            (0.0, math.nan, 5, "lng"),
            (0.0, -math.inf, 5, "lng"),
            (0.0, 0.0, 0, "radius_km"),
            (0.0, 0.0, -1, "radius_km"),
            (0.0, 0.0, MAX_RADIUS_KM + 0.001, "radius_km"),
            (0.0, 0.0, math.inf, "radius_km"),
            (0.0, 0.0, math.nan, "radius_km"),
        ],
    )
    def test_invalid_input_raises(self, lat, lng, radius_km, message):
        with pytest.raises(ValueError, match=message):
            geohash_query_prefixes(lat, lng, radius_km)
