from django.test import SimpleTestCase
from unittest.mock import patch, Mock
from services.tomtom import TomTomClient
import requests

class TomTomClientTest(SimpleTestCase):
    def setUp(self):
        self.client = TomTomClient()
        self.client.api_key = "test_key"

    @patch('services.tomtom.requests.get')
    def test_search_place_success(self, mock_get):
        mock_response = Mock()
        expected_api_response = {
            'results': [
                {
                    'id': '123',
                    'poi': {
                        'name': 'Test Place',
                        'openingHours': {
                            'mode': 'nextSevenDays',
                            'timeRanges': [
                                {
                                    'startTime': {'date': '2023-10-23', 'hour': 9, 'minute': 0}, # Monday
                                    'endTime': {'date': '2023-10-23', 'hour': 17, 'minute': 0}
                                }
                            ]
                        }
                    },
                    'address': {'freeformAddress': '123 Test St'},
                    'position': {'lat': 10.0, 'lon': 20.0}
                }
            ]
        }
        mock_response.json.return_value = expected_api_response
        mock_response.status_code = 200
        mock_get.return_value = mock_response

        results = self.client.search_place("query")
        
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]['tomtom_id'], '123')
        self.assertEqual(results[0]['name'], 'Test Place')
        self.assertEqual(results[0]['location']['lat'], 10.0)
        self.assertEqual(results[0]['location']['lng'], 20.0)
        self.assertEqual(len(results[0]['hours']), 1)
        self.assertEqual(results[0]['hours'][0]['day_of_week'], 0) # 2023-10-23 is a Monday
        self.assertEqual(results[0]['hours'][0]['open_time'], "09:00")

    @patch('services.tomtom.requests.get')
    def test_search_place_failure(self, mock_get):
        mock_get.side_effect = requests.RequestException("Network error")
        results = self.client.search_place("query")
        self.assertEqual(results, [])
