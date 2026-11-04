import dataclasses
import datetime
from io import StringIO
from unittest.mock import patch

from django.contrib.auth.hashers import make_password
from django.core.management import CommandError, call_command
from google.cloud.firestore_v1.batch import WriteBatch

from apps.places import repository as places
from apps.users import repository as users
from apps.users.management.commands import import_postgres
from apps.users.management.commands.import_postgres import LegacyData, apply_plan, build_plan, find_conflicts
from services.firestore import doc_id, get_client
from tests.base import FirestoreTestCase

JOINED = datetime.datetime(2026, 3, 1, 12, 0, tzinfo=datetime.UTC)
ALICE_TOKEN = "a" * 40
ALICE_HASH = make_password("s3cret")
MALLORY_HASH = make_password("x")


def _user_row(id, username, password="", is_active=True, token_key=None, **profile):
    """A row as USERS_SQL returns it. A user without a UserProfile has NULL profile columns."""
    row = {
        "id": id,
        "username": username,
        "password": password,
        "email": f"{username}@example.com",
        "first_name": username.title(),
        "last_name": "",
        "is_active": is_active,
        "date_joined": JOINED,
        "token_key": token_key,
        "token_created_at": JOINED if token_key else None,
    }
    row.update(dict.fromkeys(import_postgres._PROFILE_COLUMNS))
    row.update(profile)
    return row


def _legacy_data():
    return LegacyData(
        users=[
            _user_row(
                3,
                "alice",
                ALICE_HASH,
                token_key=ALICE_TOKEN,
                home_address="1 Main St",
                home_city="Springfield",
                home_lat=40.0,
                home_lng=-75.0,
                work_address="",
                work_lat=None,
                work_lng=None,
                use_current_location=True,
                calendar_subscription_url="https://example.com/cal.ics",
            ),
            _user_row(7, "google-oauth2|123", "!unusablehash"),  # Auth0 user, no profile row
            _user_row(9, "mallory", MALLORY_HASH, is_active=False, token_key="b" * 40),
        ],
        places=[
            {
                "id": 5,
                "tomtom_id": "tt/5",
                "name": "Blue Bottle Coffee",
                "address": "1 Market St",
                "lat": 37.7936,
                "lng": -122.3950,
                "phone": "555-0100",
                "website": None,
                "categories": ["cafe"],
            },
            {
                "id": 12,
                "tomtom_id": "tt-12",
                "name": "Corner Library",
                "address": "2 Oak Ave",
                "lat": 37.80,
                "lng": -122.40,
                "phone": None,
                "website": "https://lib.example.com",
                "categories": [],
            },
        ],
        hours=[
            {"place_id": 5, "day_of_week": 1, "open_time": datetime.time(7, 0), "close_time": datetime.time(18, 0)},
            {"place_id": 5, "day_of_week": 0, "open_time": datetime.time(13, 0), "close_time": datetime.time(17, 30)},
            {"place_id": 5, "day_of_week": 0, "open_time": datetime.time(7, 0), "close_time": datetime.time(11, 0)},
        ],
        saved_places=[
            {
                "id": 21,
                "user_id": 3,
                "place_id": 12,
                "custom_name": "Library",
                "icon": "book",
                "color": "#ff0000",
                "is_pinned": True,
                "is_check_it_out": False,
                "average_visit_length": 45,
                "created_at": JOINED,
            },
            {
                "id": 4,
                "user_id": 3,
                "place_id": 5,
                "custom_name": None,
                "icon": None,
                "color": None,
                "is_pinned": False,
                "is_check_it_out": True,
                "average_visit_length": None,
                "created_at": JOINED,
            },
            {  # belongs to the inactive user, so it is skipped with them
                "id": 30,
                "user_id": 9,
                "place_id": 5,
                "custom_name": None,
                "icon": None,
                "color": None,
                "is_pinned": False,
                "is_check_it_out": False,
                "average_visit_length": None,
                "created_at": JOINED,
            },
        ],
    )


def _import(data=None, **kwargs):
    plan = build_plan(data or _legacy_data(), **kwargs)
    if conflicts := find_conflicts(plan):
        raise AssertionError(conflicts)
    apply_plan(plan)
    return plan


class ImportPostgresTest(FirestoreTestCase):
    def test_users_keep_ids_password_hashes_tokens_and_profile(self):
        _import()

        alice = users.get_user("alice")
        self.assertEqual(alice.id, 3)
        self.assertTrue(alice.check_password("s3cret"))
        self.assertEqual(alice.token, ALICE_TOKEN)
        self.assertEqual(users.authenticate("alice", "s3cret").id, 3)
        self.assertEqual(users.get_user_by_token(ALICE_TOKEN).username, "alice")
        self.assertEqual(users.get_or_create_token(alice), ALICE_TOKEN)
        self.assertEqual(
            (alice.home_address, alice.home_city, alice.home_lat, alice.home_lng, alice.use_current_location),
            ("1 Main St", "Springfield", 40.0, -75.0, True),
        )
        self.assertEqual(alice.calendar_subscription_url, "https://example.com/cal.ics")
        self.assertIsNone(alice.work_lat)

        auth0 = users.get_user("google-oauth2|123")
        self.assertEqual(auth0.id, 7)
        self.assertEqual(auth0.home_address, "")
        self.assertIsNone(auth0.token)
        self.assertFalse(auth0.check_password(""))

        # Same document shape the repository writes
        snapshot = get_client().collection(users.USERS).document(alice.doc_id).get()
        expected = set(dataclasses.asdict(alice)) | {"created_at"}
        self.assertEqual(set(snapshot.to_dict()), expected)
        self.assertEqual(snapshot.get("created_at"), JOINED)

    def test_inactive_users_are_skipped_with_their_tokens_and_bookmarks(self):
        plan = _import()

        self.assertIsNone(users.get_user("mallory"))
        self.assertIsNone(users.get_user_by_token("b" * 40))
        self.assertEqual(plan.skipped, {"users": 1, "places": 0, "saved_places": 1})

    def test_include_inactive(self):
        _import(include_inactive=True)
        self.assertEqual(users.get_user("mallory").id, 9)
        self.assertEqual(users.get_user_by_token("b" * 40).username, "mallory")

    def test_places_keep_ids_hours_location_and_are_searchable(self):
        _import()

        place = places.get_place("tt/5")
        self.assertEqual(place["id"], 5)
        self.assertEqual(place["location"], {"lat": 37.7936, "lng": -122.3950})
        self.assertEqual(place["categories"], ["cafe"])
        self.assertEqual(
            place["hours"],
            [
                {"day_of_week": 0, "open_time": "07:00", "close_time": "11:00"},
                {"day_of_week": 0, "open_time": "13:00", "close_time": "17:30"},
                {"day_of_week": 1, "open_time": "07:00", "close_time": "18:00"},
            ],
        )
        self.assertEqual([p["id"] for p in places.search_places("blue bot")], [5])
        self.assertEqual([p["id"] for p in places.nearby_places(37.7936, -122.3950, 2)], [5, 12])
        self.assertEqual([p["id"] for p in places.recent_places()], [12, 5])

        # Same document shape the repository writes
        created = places.update_or_create_place(
            {"tomtom_id": "new", "name": "New", "address": "x", "location": {"lat": 1.0, "lng": 2.0}}
        )
        new_doc = places._places().document(doc_id("new")).get().to_dict()
        imported_doc = places._places().document(doc_id("tt/5")).get().to_dict()
        self.assertEqual(set(imported_doc), set(new_doc))
        self.assertEqual(imported_doc["search_terms"], places._search_terms("Blue Bottle Coffee"))
        self.assertEqual(created["id"], 13)

    def test_saved_places_keep_ids_and_fields(self):
        _import()

        alice = users.get_user("alice")
        saved = places.list_saved_places(alice)
        self.assertEqual([s["id"] for s in saved], [4, 21])
        library = saved[1]
        self.assertEqual(library["place"]["id"], 12)
        self.assertEqual(
            {k: library[k] for k in places._SAVED_PLACE_FIELDS},
            {
                "custom_name": "Library",
                "icon": "book",
                "color": "#ff0000",
                "is_pinned": True,
                "is_check_it_out": False,
                "average_visit_length": 45,
            },
        )
        self.assertTrue(saved[0]["is_check_it_out"])

        # Same document shape the repository writes
        new = places.update_or_create_place(
            {"tomtom_id": "new", "name": "New", "address": "x", "location": {"lat": 1.0, "lng": 2.0}}
        )
        places.save_place(alice, new)
        new_doc = places._saved_places(alice).document(doc_id("new")).get().to_dict()
        imported_doc = places._saved_places(alice).document(doc_id("tt-12")).get().to_dict()
        self.assertEqual(set(imported_doc), set(new_doc))

    def test_new_ids_continue_after_the_largest_imported_id(self):
        _import()

        self.assertEqual(users.create_user("newbie", "pw").id, 10)  # mallory's 9 is reserved too
        place = places.update_or_create_place(
            {"tomtom_id": "new", "name": "New", "address": "x", "location": {"lat": 1.0, "lng": 2.0}}
        )
        self.assertEqual(place["id"], 13)
        self.assertEqual(places.save_place(users.get_user("alice"), place)["id"], 31)  # mallory's 30 too

    def test_rerun_is_idempotent_and_never_lowers_counters(self):
        _import()
        users.create_user("newbie", "pw")  # reserves a block of user IDs, raising the counter past 9
        counters = import_postgres.counter_values()
        before = {
            path: ref.get().to_dict() for path, ref in ((r.path, r) for r, _ in build_plan(_legacy_data()).writes)
        }

        _import()

        after = {path: get_client().document(path).get().to_dict() for path in before}
        self.assertEqual(after, before)
        self.assertGreater(counters["users"], 9)
        self.assertEqual(import_postgres.counter_values(), counters)
        self.assertEqual(
            import_postgres.firestore_counts(), {"users": 3, "auth_tokens": 1, "places": 2, "saved_places": 2}
        )

    def test_conflicting_records_are_detected(self):
        users.create_user("alice", "pw")  # id 1 in Firestore, 3 in Postgres
        places.update_or_create_place(  # takes place id 1 ...
            {"tomtom_id": "other", "name": "Other", "address": "x", "location": {"lat": 1.0, "lng": 2.0}}
        )
        data = _legacy_data()
        data.places[0]["id"] = 1  # ... which Postgres gives to tt/5

        conflicts = find_conflicts(build_plan(data))

        self.assertEqual(len(conflicts), 2)
        self.assertIn("users/alice has id 1 in Firestore but 3 in Postgres", conflicts)

    def test_batches_stay_within_the_firestore_limit(self):
        data = LegacyData(
            places=[
                {"id": i, "tomtom_id": f"p{i}", "name": f"Place {i}", "address": "x", "lat": 0.0, "lng": 0.0}
                for i in range(1, 1202)
            ]
        )
        sizes = []
        commit = WriteBatch.commit

        def spy(batch, *args, **kwargs):
            sizes.append(len(batch._write_pbs))
            return commit(batch, *args, **kwargs)

        with patch.object(WriteBatch, "commit", spy):
            _import(data)

        self.assertEqual(sizes, [500, 500, 201])
        self.assertEqual(import_postgres.firestore_counts()["places"], 1201)
        self.assertEqual(import_postgres.counter_values(), {"places": 1201})


@patch.object(import_postgres, "read_postgres", side_effect=lambda url: _legacy_data())
class ImportPostgresCommandTest(FirestoreTestCase):
    def test_dry_run_writes_nothing(self, read_postgres):
        out = StringIO()
        call_command("import_postgres", "--dry-run", "--database-url", "postgres://legacy", stdout=out)

        read_postgres.assert_called_once_with("postgres://legacy")
        self.assertIn("Dry run", out.getvalue())
        self.assertIn("saved_places", out.getvalue())
        self.assertEqual(
            import_postgres.firestore_counts(), {"users": 0, "auth_tokens": 0, "places": 0, "saved_places": 0}
        )
        self.assertEqual(import_postgres.counter_values(), {})

    def test_import_reports_counts(self, read_postgres):
        out = StringIO()
        call_command("import_postgres", "--database-url", "postgres://legacy", stdout=out)

        lines = {
            line.split()[0]: line.split()[1:]
            for line in out.getvalue().splitlines()
            if line.startswith("  ") and line.split()
        }
        # postgres, skipped, written, firestore, counter
        self.assertEqual(lines["users"], ["3", "1", "2", "2", "9"])
        self.assertEqual(lines["auth_tokens"], ["2", "1", "1", "1", "-"])
        self.assertEqual(lines["places"], ["2", "0", "2", "2", "12"])
        self.assertEqual(lines["saved_places"], ["3", "1", "2", "2", "30"])
        self.assertIn("Import complete", out.getvalue())

    def test_conflicts_abort_without_writing(self, read_postgres):
        users.create_user("alice", "pw")

        with self.assertRaisesMessage(CommandError, "users/alice has id 1"):
            call_command("import_postgres", "--database-url", "postgres://legacy", stdout=StringIO())
        self.assertIsNone(places.get_place("tt/5"))

    def test_requires_a_database_url(self, read_postgres):
        with self.assertRaisesMessage(CommandError, "DATABASE_URL"):
            call_command("import_postgres", "--database-url", "", stdout=StringIO())
