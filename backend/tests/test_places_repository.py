import math
import random
from unittest.mock import patch

from django.test import SimpleTestCase

from apps.places import repository as places
from apps.users import repository as users
from services.firestore import doc_id, get_client
from services.geo import (
    _EARTH_RADIUS_KM,
    MAX_QUERY_CELLS_FALLBACK,
    MAX_RADIUS_KM,
    distance_km,
    encode_geohash,
    geohash_query_prefixes,
)
from tests.base import FirestoreTestCase


def _place_data(tomtom_id, name="Test", lat=0.0, lng=0.0, **extra):
    return {"tomtom_id": tomtom_id, "name": name, "address": "123", "location": {"lat": lat, "lng": lng}, **extra}


def _ids(results):
    return {p["tomtom_id"] for p in results}


class SearchPlacesTest(FirestoreTestCase):
    def test_finds_match_behind_many_non_matching_candidates(self):
        # 25 docs share the query's longest word ("pizza") but don't contain the whole query.
        # Their IDs sort before the real match, so limiting before filtering would miss it.
        for i in range(25):
            places.update_or_create_place(_place_data(f"a{i:02}", f"Pizza Palace {i}"))
        places.update_or_create_place(_place_data("zz", "Pizza Hut"))

        self.assertEqual(_ids(places.search_places("pizza hut")), {"zz"})

    def test_pages_through_candidates_with_a_cursor(self):
        for i in range(12):
            places.update_or_create_place(_place_data(f"a{i:02}", f"Pizza Palace {i}"))
        for i in range(4):
            places.update_or_create_place(_place_data(f"z{i}", f"Pizza Hut {i}"))

        with patch.object(places, "_SEARCH_PAGE_SIZE", 5):
            self.assertEqual(_ids(places.search_places("pizza hut")), {"z0", "z1", "z2", "z3"})
            self.assertEqual(len(places.search_places("pizza hut", limit=3)), 3)
            self.assertEqual(len(places.search_places("pizza", limit=20)), 16)

    def test_returns_every_match_unless_limited(self):
        for i in range(30):
            places.update_or_create_place(_place_data(f"p{i:02}", f"Pizza {i}"))

        self.assertEqual(len(places.search_places("pizza")), 30)  # unbounded, like icontains
        self.assertEqual(len(places.search_places("pizza", limit=5)), 5)

    def test_candidate_cap_bounds_reads(self):
        for i in range(12):
            places.update_or_create_place(_place_data(f"p{i:02}", f"Pizza {i}"))

        with patch.object(places, "_SEARCH_PAGE_SIZE", 5), patch.object(places, "_MAX_SEARCH_CANDIDATES", 7):
            self.assertEqual(len(places.search_places("pizza")), 7)

    def test_matches_inside_words(self):
        places.update_or_create_place(_place_data("1", "Joe's Pizza"))
        places.update_or_create_place(_place_data("2", "Joe'sPizza"))
        places.update_or_create_place(_place_data("3", "JoesPizzaPlace"))
        places.update_or_create_place(_place_data("4", "Burger Barn"))

        self.assertEqual(_ids(places.search_places("izza")), {"1", "2", "3"})
        self.assertEqual(_ids(places.search_places("pizza")), {"1", "2", "3"})
        self.assertEqual(_ids(places.search_places("spizzap")), {"3"})
        self.assertEqual(_ids(places.search_places("urge")), {"4"})

    def test_long_words_beyond_the_indexed_length(self):
        name = "Supercalifragilisticexpialidocious Cafe"
        places.update_or_create_place(_place_data("long", name))

        # 25 characters starting 9 characters into a 34-character word.
        self.assertEqual(_ids(places.search_places("fragilisticexpialidocious")), {"long"})
        self.assertEqual(_ids(places.search_places("Supercalifragilisticexpialidocious")), {"long"})
        self.assertEqual(_ids(places.search_places("docious caf")), {"long"})
        self.assertEqual(places.search_places("fragilisticexpialidociousness"), [])

    def test_multi_word_and_punctuation_queries(self):
        places.update_or_create_place(_place_data("1", "Joe's Pizza"))
        places.update_or_create_place(_place_data("2", "Ben & Jerry's"))
        places.update_or_create_place(_place_data("3", "Pizza Hut"))

        # Partial first and last words.
        self.assertEqual(_ids(places.search_places("e's piz")), {"1"})
        self.assertEqual(_ids(places.search_places("OE'S PIZZA")), {"1"})
        self.assertEqual(_ids(places.search_places("n & j")), {"2"})
        self.assertEqual(_ids(places.search_places("& jerry's")), {"2"})
        self.assertEqual(_ids(places.search_places("zza h")), {"3"})
        # Punctuation is part of the substring, like icontains.
        self.assertEqual(places.search_places("joes pizza"), [])
        self.assertEqual(places.search_places("ben and jerry"), [])
        # Surrounding and repeated whitespace is ignored.
        self.assertEqual(_ids(places.search_places("  joe's   pizza ")), {"1"})
        # Punctuation-only queries are indexed too.
        self.assertEqual(_ids(places.search_places("&")), {"2"})
        self.assertEqual(_ids(places.search_places("'s")), {"1", "2"})
        # A blank query has nothing to look up.
        self.assertEqual(places.search_places("   "), [])

    def test_punctuation_inside_words(self):
        places.update_or_create_place(_place_data("aw", "A&W Restaurant"))
        places.update_or_create_place(_place_data("7", "7-Eleven"))

        self.assertEqual(_ids(places.search_places("&")), {"aw"})
        self.assertEqual(_ids(places.search_places("a&w")), {"aw"})
        self.assertEqual(_ids(places.search_places("&w rest")), {"aw"})
        self.assertEqual(_ids(places.search_places("-")), {"7"})
        self.assertEqual(_ids(places.search_places("7-e")), {"7"})

    def test_case_folding(self):
        places.update_or_create_place(_place_data("1", "CAFÉ ΟΔΟΣ"))

        self.assertEqual(_ids(places.search_places("café")), {"1"})
        self.assertEqual(_ids(places.search_places("οδοσ")), {"1"})

    def test_renaming_updates_the_index(self):
        places.update_or_create_place(_place_data("1", "Old Name"))
        places.update_or_create_place(_place_data("1", "New Name"))

        self.assertEqual(places.search_places("old"), [])
        self.assertEqual(_ids(places.search_places("ew na")), {"1"})

    def test_reindex_rewrites_stale_search_terms(self):
        places.update_or_create_place(_place_data("1", "Joe's Pizza"))
        places.update_or_create_place(_place_data("2", "Burger Barn"))
        # Simulate a doc indexed by the old word-prefix scheme.
        ref = get_client().collection(places.PLACES).document(doc_id("1"))
        ref.update({"search_terms": ["j", "jo", "joe", "p", "pi", "piz", "pizz", "pizza", "s"]})
        self.assertEqual(places.search_places("izza"), [])

        self.assertEqual(places.reindex_search_terms(batch_size=1), 1)
        self.assertEqual(_ids(places.search_places("izza")), {"1"})
        self.assertEqual(places.reindex_search_terms(), 0)

    def test_search_terms_are_substrings_of_words(self):
        self.assertEqual(
            places._search_terms("Ab-c d"),
            ["-", "-c", "a", "ab", "ab-", "ab-c", "b", "b-", "b-c", "c", "d"],
        )
        terms = places._search_terms("x" * 5 + "abcdefghijklmnopqrstuvwxyz")
        self.assertIn("abcdefghijklmnopqrst", terms)
        self.assertIn("ghijklmnopqrstuvwxyz", terms)
        self.assertTrue(all(len(t) <= places._MAX_SEARCH_TERM_LENGTH for t in terms))


class NearbyPlacesTest(FirestoreTestCase):
    def setUp(self):
        super().setUp()
        self.user = users.create_user("testuser", "password")
        self.auth_headers = {"HTTP_AUTHORIZATION": f"Bearer {users.get_or_create_token(self.user)}"}

    def _nearby(self, **params):
        return self.client.get("/api/places/nearby", params, **self.auth_headers)

    def test_rejects_out_of_range_params(self):
        for params in (
            {"lat": 0, "lng": 0, "radius_km": 100000},
            {"lat": 0, "lng": 0, "radius_km": MAX_RADIUS_KM + 0.1},
            {"lat": 0, "lng": 0, "radius_km": 0},
            {"lat": 0, "lng": 0, "radius_km": -1},
            {"lat": 0, "lng": 0, "radius_km": "nan"},
            {"lat": 0, "lng": 0, "radius_km": "inf"},
            {"lat": 90.5, "lng": 0},
            {"lat": -91, "lng": 0},
            {"lat": "nan", "lng": 0},
            {"lat": 0, "lng": 180.5},
            {"lat": 0, "lng": -181},
        ):
            with self.subTest(params=params):
                self.assertEqual(self._nearby(**params).status_code, 422)

    def test_accepts_in_range_params(self):
        places.update_or_create_place(_place_data("nyc", "City Hall", 40.7128, -74.0060))

        response = self._nearby(lat=40.7128, lng=-74.0060, radius_km=MAX_RADIUS_KM)
        self.assertEqual(response.status_code, 200)
        self.assertEqual([p["tomtom_id"] for p in response.json()], ["nyc"])
        self.assertEqual(self._nearby(lat=90, lng=180).status_code, 200)  # default radius

    def test_repository_never_scans_the_collection(self):
        for radius in (0, -1, MAX_RADIUS_KM * 2, 100000, math.inf, math.nan):
            with self.subTest(radius=radius), self.assertRaises(ValueError):
                places.nearby_places(0, 0, radius)
        with self.assertRaises(ValueError):
            places.nearby_places(91, 0, 5)
        with self.assertRaises(ValueError):
            places.nearby_places(0, 181, 5)

        # Every query is a bounded geohash range, even where cells get narrow (the poles).
        coverings = []

        def recording(*args):
            coverings.append(geohash_query_prefixes(*args))
            return coverings[-1]

        with patch.object(places, "geohash_query_prefixes", side_effect=recording):
            for lat, lng in ((0, 0), (89.9999, 0), (-90, 180), (60, -180)):
                places.nearby_places(lat, lng, MAX_RADIUS_KM)
        self.assertEqual(len(coverings), 4)
        for prefixes in coverings:
            self.assertTrue(prefixes)
            self.assertTrue(all(prefixes))

    def test_across_the_antimeridian_and_the_pole(self):
        places.update_or_create_place(_place_data("east", "East", 0.0, 179.99))
        places.update_or_create_place(_place_data("pole-a", "Pole A", 89.99, 0.0))
        places.update_or_create_place(_place_data("pole-b", "Pole B", 89.99, 180.0))
        places.update_or_create_place(_place_data("far", "Far", 0.0, 170.0))

        self.assertEqual(_ids(places.nearby_places(0.0, -179.99, 5)), {"east"})
        self.assertEqual(_ids(places.nearby_places(89.995, 90.0, 5)), {"pole-a", "pole-b"})

    def test_results_are_ordered_by_id(self):
        created = [
            places.update_or_create_place(_place_data(t, t, 40.7128 + i * 0.001, -74.0060))
            for i, t in enumerate(("c", "a", "b"))
        ]

        nearby = places.nearby_places(40.7128, -74.0060, 5)
        self.assertEqual([p["id"] for p in nearby], sorted(p["id"] for p in created))


class GeohashCoveringTest(SimpleTestCase):
    """Pure geometry, no emulator needed."""

    @staticmethod
    def _destination(lat, lng, bearing_deg, km):
        d = km / _EARTH_RADIUS_KM
        phi1, lmb1, theta = math.radians(lat), math.radians(lng), math.radians(bearing_deg)
        phi2 = math.asin(math.sin(phi1) * math.cos(d) + math.cos(phi1) * math.sin(d) * math.cos(theta))
        lmb2 = lmb1 + math.atan2(
            math.sin(theta) * math.sin(d) * math.cos(phi1), math.cos(d) - math.sin(phi1) * math.sin(phi2)
        )
        return math.degrees(phi2), (math.degrees(lmb2) + 180) % 360 - 180

    def test_prefixes_cover_every_point_in_the_circle(self):
        rng = random.Random(1234)
        centers = [(0.0, 0.0), (40.7, -74.0), (89.9999, 10.0), (-90.0, 0.0), (65.0, 179.999), (-33.9, -180.0)]
        centers += [(rng.uniform(-90, 90), rng.uniform(-180, 180)) for _ in range(300)]
        for lat, lng in centers:
            radius = rng.choice([0.01, 1.0, 5.0, rng.uniform(0.001, MAX_RADIUS_KM), MAX_RADIUS_KM])
            prefixes = geohash_query_prefixes(lat, lng, radius)
            self.assertTrue(all(prefixes))
            self.assertLessEqual(len(prefixes), MAX_QUERY_CELLS_FALLBACK)
            for _ in range(20):
                plat, plng = self._destination(
                    lat, lng, rng.uniform(0, 360), radius * rng.choice([rng.random(), 0.9999999])
                )
                if distance_km(lat, lng, plat, plng) > radius:
                    continue
                geohash = encode_geohash(plat, plng)
                self.assertTrue(
                    any(geohash.startswith(p) for p in prefixes),
                    f"{(plat, plng)} within {radius} km of {(lat, lng)} not covered by {prefixes}",
                )

    def test_rejects_huge_radius(self):
        for radius in (MAX_RADIUS_KM + 1, 20000):
            with self.assertRaises(ValueError):
                geohash_query_prefixes(0, 0, radius)


class RecentPlacesTest(FirestoreTestCase):
    def test_ordered_by_creation_time_not_id(self):
        first = places.update_or_create_place(_place_data("first"))
        places.update_or_create_place(_place_data("second"))
        places.update_or_create_place(_place_data("third"))
        # IDs come from per-process blocks, so an older place can hold a larger ID.
        get_client().collection(places.PLACES).document(doc_id("first")).update({"id": first["id"] + 1000})

        self.assertEqual([p["tomtom_id"] for p in places.recent_places(10)], ["third", "second", "first"])
        self.assertEqual([p["tomtom_id"] for p in places.recent_places(2)], ["third", "second"])


class SavedPlaceUpdateTest(FirestoreTestCase):
    def setUp(self):
        super().setUp()
        self.user = users.create_user("testuser", "password")
        self.place = places.update_or_create_place(_place_data("p1", "Place"))

    def test_update_missing_bookmark_returns_none(self):
        self.assertIsNone(places.update_saved_place(self.user, self.place, is_pinned=True))
        self.assertIsNone(places.update_saved_place(self.user, self.place))
        self.assertIsNone(places.get_saved_place(self.user, self.place))  # nothing was created

    def test_update_after_delete_returns_none(self):
        places.save_place(self.user, self.place)
        self.assertTrue(places.delete_saved_place(self.user, self.place["tomtom_id"]))

        self.assertIsNone(places.update_saved_place(self.user, self.place, is_pinned=True))

    def test_update_existing_bookmark(self):
        saved = places.save_place(self.user, self.place)

        updated = places.update_saved_place(self.user, self.place, is_pinned=True, icon="star")
        self.assertEqual(updated["id"], saved["id"])
        self.assertTrue(updated["is_pinned"])
        self.assertEqual(updated["icon"], "star")
        self.assertTrue(places.get_saved_place(self.user, self.place)["is_pinned"])

    def test_api_returns_404_for_missing_bookmark(self):
        headers = {"HTTP_AUTHORIZATION": f"Bearer {users.get_or_create_token(self.user)}"}
        response = self.client.patch(
            "/api/places/bookmarks/p1/pin", data={"is_pinned": True}, content_type="application/json", **headers
        )
        self.assertEqual(response.status_code, 404)

    def test_delete_missing_bookmark(self):
        self.assertFalse(places.delete_saved_place(self.user, self.place["tomtom_id"]))
        places.save_place(self.user, self.place)
        self.assertTrue(places.delete_saved_place(self.user, self.place["tomtom_id"]))
        self.assertFalse(places.delete_saved_place(self.user, self.place["tomtom_id"]))

    def test_delete_with_unstorable_tomtom_id(self):
        self.assertFalse(places.delete_saved_place(self.user, ""))

    def test_delete_bookmark_whose_place_is_gone(self):
        places.save_place(self.user, self.place)
        places._places().document(doc_id("p1")).delete()
        self.assertEqual(places.list_saved_places(self.user), [])  # hidden from the list ...

        headers = {"HTTP_AUTHORIZATION": f"Bearer {users.get_or_create_token(self.user)}"}
        response = self.client.delete("/api/places/bookmarks/p1", **headers)
        self.assertEqual(response.status_code, 204)  # ... but still removable
        self.assertEqual(self.client.delete("/api/places/bookmarks/p1", **headers).status_code, 404)


class ListSavedPlacesTest(FirestoreTestCase):
    def test_ordered_by_creation_time_not_id(self):
        user = users.create_user("testuser", "password")
        for tomtom_id in ("first", "second", "third"):
            places.save_place(user, places.update_or_create_place(_place_data(tomtom_id)))
        # IDs come from per-process blocks, so an older bookmark can hold a larger ID.
        ref = places._saved_places(user).document(doc_id("first"))
        ref.update({"id": ref.get().get("id") + 1000})

        self.assertEqual(
            [s["place"]["tomtom_id"] for s in places.list_saved_places(user)], ["first", "second", "third"]
        )

    def test_same_creation_time_falls_back_to_id(self):
        user = users.create_user("testuser", "password")
        for tomtom_id in ("a", "b"):
            places.save_place(user, places.update_or_create_place(_place_data(tomtom_id)))
        same = places._saved_places(user).document(doc_id("a")).get().get("created_at")
        places._saved_places(user).document(doc_id("b")).update({"created_at": same, "id": 1})
        places._saved_places(user).document(doc_id("a")).update({"id": 2})

        self.assertEqual([s["place"]["tomtom_id"] for s in places.list_saved_places(user)], ["b", "a"])


class InvalidTomTomIdTest(FirestoreTestCase):
    def setUp(self):
        super().setUp()
        self.user = users.create_user("testuser", "password")
        self.headers = {"HTTP_AUTHORIZATION": f"Bearer {users.get_or_create_token(self.user)}"}

    def _post(self, path, payload):
        return self.client.post(path, data=payload, content_type="application/json", **self.headers)

    def test_get_place_returns_none(self):
        self.assertIsNone(places.get_place(""))
        self.assertIsNone(places.get_place("\ud800"))

    def test_bookmark_with_empty_tomtom_id_is_404(self):
        self.assertEqual(self._post("/api/places/bookmark", {"tomtom_id": ""}).status_code, 404)

    def test_create_place_with_empty_tomtom_id_is_400(self):
        payload = {**_place_data(""), "address": "1 Main St"}
        self.assertEqual(self._post("/api/places/", payload).status_code, 400)


class PlaceDetailsTest(FirestoreTestCase):
    def setUp(self):
        super().setUp()
        self.user = users.create_user("testuser", "password")
        self.headers = {"HTTP_AUTHORIZATION": f"Bearer {users.get_or_create_token(self.user)}"}

    @patch("apps.places.api.TomTomClient.get_place_details", return_value=None)
    def test_unknown_place_is_404(self, get_place_details):
        response = self.client.get("/api/places/missing", **self.headers)
        self.assertEqual(response.status_code, 404, response.content)
        self.assertEqual(response.json(), {"detail": "Place not found in TomTom"})
        get_place_details.assert_called_once_with("missing")

    @patch("apps.places.api.TomTomClient.get_place_details")
    def test_fetched_place_is_stored(self, get_place_details):
        get_place_details.return_value = _place_data("fresh", "Fresh Place")
        response = self.client.get("/api/places/fresh", **self.headers)
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(places.get_place("fresh")["name"], "Fresh Place")
