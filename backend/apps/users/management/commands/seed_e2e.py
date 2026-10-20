"""
Seeds the E2E stack (docker-compose.e2e.yml) with a known account and places. See e2e/README.md.

    python manage.py seed_e2e

Creates the account SEED_USERNAME / SEED_PASSWORD with a home address and two bookmarks: a TomTom
place (also served by the E2E stub, so its details resolve) and a custom place that only local
search finds. Re-running resets the account to that state.

It refuses to run unless FIRESTORE_EMULATOR_HOST is set, so the known login can never be created
in a real Firestore project.
"""

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from apps.places import repository as places_repo
from apps.users import repository as users_repo
from services.firestore import get_client

SEED_USERNAME = "e2e-seeded"
SEED_PASSWORD = "e2e-password"

# Weekday hours (0 is Monday), as stored by the API.
_EVERY_DAY = range(7)

SEED_PLACES = [
    {
        # The first result of contracts/tomtom/fixtures/poi_search.json.
        "tomtom_id": "Tu4lEjRtadpLbiAPajPyOQ",
        "name": "Joe's Pizza",
        "address": "7 Carmine Street, New York, NY 10014",
        "location": {"lat": 40.730599, "lng": -74.002139},
        "phone": "+1 212-366-1182",
        "website": "www.joespizzanyc.com",
        "categories": ["pizza", "restaurant"],
        "hours": [{"day_of_week": d, "open_time": "10:00", "close_time": "23:00"} for d in _EVERY_DAY],
    },
    {
        "tomtom_id": "custom-e2e-community-garden",
        "name": "Riverside Community Garden",
        "address": "12 River Road, Springfield, IL 62701",
        "location": {"lat": 39.7990, "lng": -89.6440},
        "categories": [],
        "hours": [{"day_of_week": d, "open_time": "07:00", "close_time": "19:00"} for d in _EVERY_DAY],
    },
]

SEED_PROFILE = {
    "email": "e2e-seeded@example.com",
    "first_name": "Sam",
    "last_name": "Seeded",
    "home_address": "1 Main Street, Springfield, IL 62701",
    "home_street": "1 Main Street",
    "home_city": "Springfield",
    "home_state": "IL",
    "home_zip": "62701",
    # Where the stub geocodes every address (contracts/tomtom/fixtures/geocode.json).
    "home_lat": 39.80178,
    "home_lng": -89.64352,
}


class Command(BaseCommand):
    help = "Seed the E2E stack's emulator with a known account and places (emulator only)."

    def handle(self, *args, **options):
        if not settings.FIRESTORE_EMULATOR_HOST:
            raise CommandError("seed_e2e only runs against the Firestore emulator (FIRESTORE_EMULATOR_HOST is unset).")

        places = [places_repo.update_or_create_place(data) for data in SEED_PLACES]

        existing = users_repo.get_user(SEED_USERNAME)
        if existing:
            for saved in places_repo.list_saved_places(existing):
                places_repo.delete_saved_place(existing, saved["place"]["tomtom_id"])
            get_client().collection(users_repo.USERS).document(existing.doc_id).delete()

        user = users_repo.create_user(SEED_USERNAME, SEED_PASSWORD, **SEED_PROFILE)
        if user is None:
            raise CommandError(f"Couldn't create {SEED_USERNAME}: it was created concurrently.")

        places_repo.save_place(user, places[0])
        places_repo.update_saved_place(user, places[0], is_pinned=True)
        places_repo.save_place(user, places[1])

        self.stdout.write(f"Seeded {SEED_USERNAME} with {len(places)} bookmarks.")
