from apps.users import repository
from tests.base import FirestoreTestCase
import json
from unittest.mock import patch

class ProfileApiTest(FirestoreTestCase):
    def setUp(self):
        super().setUp()
        self.user = repository.create_user("testuser", "password", email="test@example.com")
        # Ensure profile has some data
        self.user.home_address = "123 Home St"
        self.user.home_lat = 40.7128
        self.user.home_lng = -74.0060
        self.user.calendar_subscription_url = "https://example.com/cal.ics"
        repository.save_user(self.user)
        self.token = repository.get_or_create_token(self.user)
        self.auth_headers = {"HTTP_AUTHORIZATION": f"Bearer {self.token}"}

    def test_get_me_returns_all_fields(self):
        """Verify GET /auth/me returns coordinates and calendar URL."""
        response = self.client.get("/api/auth/me", **self.auth_headers)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertEqual(data["home_lat"], 40.7128)
        self.assertEqual(data["home_lng"], -74.0060)
        self.assertEqual(data["calendar_subscription_url"], "https://example.com/cal.ics")

    @patch("apps.users.api.TomTomClient.geocode_address")
    def test_update_me_geocodes_and_returns_coords(self, mock_geocode):
        """Verify PUT /auth/me triggers geocoding and returns new coordinates."""
        mock_geocode.return_value = {"lat": 34.0522, "lon": -118.2437}
        
        payload = {
            "home_street": "New St",
            "home_city": "Los Angeles",
            "home_state": "CA"
        }
        
        response = self.client.put(
            "/api/auth/me",
            data=json.dumps(payload),
            content_type="application/json",
            **self.auth_headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertEqual(data["home_lat"], 34.0522)
        self.assertEqual(data["home_lng"], -118.2437)
        
        # Verify Firestore update
        user = repository.get_user("testuser")
        self.assertEqual(user.home_lat, 34.0522)
        self.assertEqual(user.home_city, "Los Angeles")
        # Credentials are untouched by profile saves
        self.assertTrue(user.check_password("password"))
        self.assertEqual(user.token, self.token)

    @patch("apps.users.api.TomTomClient.geocode_address")
    def test_update_me_keeps_concurrent_changes_to_other_fields(self, mock_geocode):
        """A profile update only writes the fields it changed."""

        def concurrent_rename(address):
            # Another request renames the user while this one waits on the geocoder.
            other = repository.get_user("testuser")
            other.first_name = "Renamed"
            repository.save_user(other, {"first_name"})
            return {"lat": 34.0522, "lon": -118.2437}

        mock_geocode.side_effect = concurrent_rename

        response = self.client.put(
            "/api/auth/me",
            data=json.dumps({"home_city": "Los Angeles"}),
            content_type="application/json",
            **self.auth_headers
        )

        self.assertEqual(response.status_code, 200)
        user = repository.get_user("testuser")
        self.assertEqual(user.first_name, "Renamed")
        self.assertEqual(user.home_city, "Los Angeles")
        self.assertEqual(user.home_lat, 34.0522)
        self.assertEqual(user.home_address, "123 Home St")

    def test_save_user_rejects_unknown_or_protected_fields(self):
        for field in ("token", "password", "nonexistent"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                repository.save_user(self.user, {field})
