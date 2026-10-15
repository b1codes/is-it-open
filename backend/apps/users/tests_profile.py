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
