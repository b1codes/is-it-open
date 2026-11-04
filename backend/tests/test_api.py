import json
from unittest.mock import patch

from apps.places import repository as places
from apps.users import repository as users
from tests.base import FirestoreTestCase


def _place_data(tomtom_id, name="Test", lat=0.0, lng=0.0, **extra):
    return {"tomtom_id": tomtom_id, "name": name, "address": "123", "location": {"lat": lat, "lng": lng}, **extra}


class SavedPlaceRepositoryTest(FirestoreTestCase):
    def test_check_it_out_default_false(self):
        user = users.create_user("testuser", "password")
        place = places.update_or_create_place(_place_data("123"))
        saved_place = places.save_place(user, place)

        self.assertFalse(saved_place["is_check_it_out"])

    def test_save_place_is_idempotent_per_user(self):
        user = users.create_user("testuser", "password")
        place = places.update_or_create_place(_place_data("123"))

        first = places.save_place(user, place)
        second = places.save_place(user, place, custom_name="Renamed")

        self.assertEqual(first["id"], second["id"])
        self.assertEqual(second["custom_name"], "Renamed")
        self.assertEqual(len(places.list_saved_places(user)), 1)


class PlaceRepositoryTest(FirestoreTestCase):
    def test_ids_are_sequential_integers(self):
        first = places.update_or_create_place(_place_data("a"))
        second = places.update_or_create_place(_place_data("b"))
        again = places.update_or_create_place(_place_data("a", name="Renamed"))

        self.assertEqual(second["id"], first["id"] + 1)
        self.assertEqual(again["id"], first["id"])
        self.assertEqual(again["name"], "Renamed")

    def test_tomtom_ids_with_slashes(self):
        place = places.update_or_create_place(_place_data("US/POI/p0/123"))
        self.assertEqual(places.get_place("US/POI/p0/123")["id"], place["id"])

    def test_nearby_filters_by_radius(self):
        places.update_or_create_place(_place_data("nyc", "City Hall", 40.7128, -74.0060))
        places.update_or_create_place(_place_data("bk", "Brooklyn Bridge Park", 40.7003, -73.9967))  # ~1.6 km
        places.update_or_create_place(_place_data("nwk", "Newark", 40.7357, -74.1724))  # ~14 km

        nearby = places.nearby_places(40.7128, -74.0060, 5.0)
        self.assertEqual({p["tomtom_id"] for p in nearby}, {"nyc", "bk"})

        wide = places.nearby_places(40.7128, -74.0060, 20.0)
        self.assertEqual({p["tomtom_id"] for p in wide}, {"nyc", "bk", "nwk"})

    def test_search_is_case_insensitive_substring_of_name(self):
        places.update_or_create_place(_place_data("1", "Joe's Pizza"))
        places.update_or_create_place(_place_data("2", "Pizza Hut"))
        places.update_or_create_place(_place_data("3", "Burger Barn"))

        self.assertEqual({p["tomtom_id"] for p in places.search_places("pizza")}, {"1", "2"})
        self.assertEqual({p["tomtom_id"] for p in places.search_places("JOE'S PIZ")}, {"1"})
        self.assertEqual(places.search_places("taco"), [])


class PlaceApiTest(FirestoreTestCase):
    def setUp(self):
        super().setUp()
        self.user = users.create_user("testuser", "password")
        self.token = users.get_or_create_token(self.user)
        self.auth_headers = {"HTTP_AUTHORIZATION": f"Bearer {self.token}"}

    def test_create_place(self):
        payload = {
            "tomtom_id": "123",
            "name": "Test Place",
            "address": "123 Test St",
            "location": {"lat": 10.0, "lng": 20.0},
            "hours": [{"day_of_week": 0, "open_time": "09:00", "close_time": "17:00"}],
        }
        response = self.client.post(
            "/api/places/", data=json.dumps(payload), content_type="application/json", **self.auth_headers
        )
        self.assertEqual(response.status_code, 200)
        place = places.get_place("123")
        self.assertIsNotNone(place)
        self.assertEqual(place["location"], {"lat": 10.0, "lng": 20.0})
        self.assertEqual(len(place["hours"]), 1)
        self.assertEqual(place["hours"][0]["open_time"], "09:00")
        self.assertEqual(response.json()["id"], place["id"])

    def test_toggle_check_it_out(self):
        place = places.update_or_create_place(_place_data("1234", "Test2"))
        places.save_place(self.user, place)

        response = self.client.patch(
            "/api/places/bookmarks/1234/check-it-out",
            data=json.dumps({"is_check_it_out": True}),
            content_type="application/json",
            **self.auth_headers,
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(places.get_saved_place(self.user, place)["is_check_it_out"])

    def test_bookmark_lifecycle(self):
        places.update_or_create_place(
            _place_data(
                "b1",
                "Bookmarked",
                hours=[
                    {"day_of_week": 2, "open_time": "08:00", "close_time": "12:00"},
                    {"day_of_week": 1, "open_time": "09:00", "close_time": "17:00"},
                ],
            )
        )

        response = self.client.post(
            "/api/places/bookmark",
            data=json.dumps({"tomtom_id": "b1", "custom_name": "Fave"}),
            content_type="application/json",
            **self.auth_headers,
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["custom_name"], "Fave")

        response = self.client.get("/api/places/bookmarks", **self.auth_headers)
        bookmarks = response.json()
        self.assertEqual(len(bookmarks), 1)
        self.assertEqual(bookmarks[0]["place"]["tomtom_id"], "b1")
        self.assertEqual([h["day_of_week"] for h in bookmarks[0]["place"]["hours"]], [1, 2])

        response = self.client.delete("/api/places/bookmarks/b1", **self.auth_headers)
        self.assertEqual(response.status_code, 204)
        response = self.client.delete("/api/places/bookmarks/b1", **self.auth_headers)
        self.assertEqual(response.status_code, 404)

    def test_bookmarks_are_scoped_per_user(self):
        place = places.update_or_create_place(_place_data("shared"))
        other = users.create_user("other", "password")
        places.save_place(other, place)

        response = self.client.get("/api/places/bookmarks", **self.auth_headers)
        self.assertEqual(response.json(), [])

        response = self.client.patch(
            "/api/places/bookmarks/shared/pin",
            data=json.dumps({"is_pinned": True}),
            content_type="application/json",
            **self.auth_headers,
        )
        self.assertEqual(response.status_code, 404)

    def test_requires_auth(self):
        response = self.client.get("/api/places/bookmarks", HTTP_AUTHORIZATION="Bearer nope")
        self.assertEqual(response.status_code, 401)

    def test_get_place_details_fetches_from_tomtom(self):
        mock_details = {
            "tomtom_id": "tom123",
            "name": "TomTom Place",
            "address": "456 Tom St",
            "location": {"lat": 40.0, "lng": -70.0},
            "phone": "555-0199",
            "website": "https://tomtom.com",
            "categories": ["Test"],
            "hours": [{"day_of_week": 1, "open_time": "10:00", "close_time": "18:00"}],
        }

        with patch("apps.places.api.TomTomClient.get_place_details") as mock_get:
            mock_get.return_value = mock_details

            response = self.client.get("/api/places/tom123", **self.auth_headers)

            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertEqual(data["name"], "TomTom Place")
            self.assertEqual(data["tomtom_id"], "tom123")

            # Verify it's saved in Firestore
            place = places.get_place("tom123")
            self.assertIsNotNone(place)
            self.assertEqual(len(place["hours"]), 1)
