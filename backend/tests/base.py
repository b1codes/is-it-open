import os

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.test import SimpleTestCase, override_settings

from services.firestore import clear_emulator

# Override to run several test suites against one emulator without them wiping each other.
TEST_PROJECT = os.environ.get("FIRESTORE_TEST_PROJECT", "demo-is-it-open-test")


@override_settings(GOOGLE_CLOUD_PROJECT=TEST_PROJECT)
class FirestoreTestCase(SimpleTestCase):
    """
    Runs against the Firestore emulator under a dedicated test project, which is wiped before
    every test. Local development data in the main project is never touched.
    """

    @classmethod
    def setUpClass(cls):
        if not settings.FIRESTORE_EMULATOR_HOST:
            raise ImproperlyConfigured(
                "Tests need the Firestore emulator. Start it with `docker compose up -d firestore` "
                "and set FIRESTORE_EMULATOR_HOST (e.g. localhost:8080)."
            )
        super().setUpClass()

    def setUp(self):
        super().setUp()
        clear_emulator()
