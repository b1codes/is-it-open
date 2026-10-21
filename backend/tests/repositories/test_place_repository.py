"""apps/places/repository.py against the emulator: places and per-user saved places (bookmarks).

Search and nearby queries are covered in tests/test_places_repository.py.
"""

import pytest

from apps.places import repository as places
from services.firestore import doc_id, get_client
from services.geo import encode_geohash
from tests import factories
from tests.repositories.test_user_repository import _run_concurrently


def _raw_place(tomtom_id) -> dict | None:
    return get_client().collection(places.PLACES).document(doc_id(tomtom_id)).get().to_dict()


class TestUpdateOrCreatePlace:
    def test_creates_a_place(self, firestore_db):
        data = factories.place_data(
            "p1",
            name="Joe's Pizza",
            lat=40.73,
            lng=-73.99,
            phone="555",
            website="https://joes.example",
            categories=["Pizza"],
            hours=factories.hours((3, "11:00:00", "22:00:00"), (1, "11:00", "21:00")),
        )

        place = places.update_or_create_place(data)

        assert place == {
            "id": place["id"],
            "tomtom_id": "p1",
            "name": "Joe's Pizza",
            "address": "123 Test St",
            "location": {"lat": 40.73, "lng": -73.99},
            "phone": "555",
            "website": "https://joes.example",
            "categories": ["Pizza"],
            "hours": factories.hours((1, "11:00", "21:00"), (3, "11:00", "22:00")),
        }
        raw = _raw_place("p1")
        assert raw["geohash"] == encode_geohash(40.73, -73.99)
        assert "joe's" in raw["search_terms"] and "pizz" in raw["search_terms"]

    def test_ids_are_sequential_and_stable(self, firestore_db):
        a = places.update_or_create_place(factories.place_data("a"))
        b = places.update_or_create_place(factories.place_data("b"))
        a_again = places.update_or_create_place(factories.place_data("a"))

        assert b["id"] == a["id"] + 1
        assert a_again["id"] == a["id"]

    def test_is_idempotent(self, firestore_db):
        data = factories.place_data("p1", hours=factories.hours((0, "09:00", "17:00")))
        first = places.update_or_create_place(data)
        raw_before = _raw_place("p1")

        again = places.update_or_create_place(data)

        assert again == first
        assert _raw_place("p1") == raw_before

    def test_moving_a_place_updates_its_geohash(self, make_place):
        make_place("p1", lat=40.73, lng=-73.99)

        moved = places.update_or_create_place(factories.place_data("p1", lat=51.5, lng=-0.12))

        assert moved["location"] == {"lat": 51.5, "lng": -0.12}
        assert _raw_place("p1")["geohash"] == encode_geohash(51.5, -0.12)
        assert places.nearby_places(51.5, -0.12, 1) == [moved]
        assert places.nearby_places(40.73, -73.99, 1) == []

    def test_renaming_updates_the_search_index(self, make_place):
        make_place("p1", name="Old Name")

        places.update_or_create_place(factories.place_data("p1", name="Brand New"))

        assert [p["tomtom_id"] for p in places.search_places("brand")] == ["p1"]
        assert places.search_places("old") == []

    def test_heals_a_stale_search_index(self, make_place):
        make_place("p1", name="Cafe Luna")
        get_client().collection(places.PLACES).document("p1").update({"search_terms": ["stale"]})

        places.update_or_create_place(factories.place_data("p1", name="Cafe Luna"))

        assert [p["tomtom_id"] for p in places.search_places("luna")] == ["p1"]

    def test_updates_fields_that_are_given(self, make_place):
        make_place("p1", phone="111", website="https://old.example", categories=["Old"])

        updated = places.update_or_create_place(
            factories.place_data(
                "p1", address="9 New St", phone="222", website="https://new.example", categories=["New"]
            )
        )

        assert (updated["address"], updated["phone"], updated["website"], updated["categories"]) == (
            "9 New St",
            "222",
            "https://new.example",
            ["New"],
        )

    def test_keeps_fields_that_are_missing_or_empty(self, make_place):
        original = make_place(
            "p1", name="Keep", phone="111", website="https://keep.example", categories=["Keep"],
            hours=factories.hours((0, "09:00", "17:00")),
        )  # fmt: skip

        updated = places.update_or_create_place(
            {"tomtom_id": "p1", "name": "", "address": "", "location": original["location"], "phone": None, "hours": []}
        )

        assert updated == original

    def test_new_hours_replace_the_old_ones(self, make_place):
        make_place("p1", hours=factories.hours((0, "09:00", "17:00"), (1, "09:00", "17:00")))

        updated = places.update_or_create_place(
            factories.place_data("p1", hours=factories.hours((5, "10:00", "14:00")))
        )

        assert updated["hours"] == factories.hours((5, "10:00", "14:00"))

    def test_concurrent_creates_of_one_place_share_an_id(self, firestore_db):
        results, errors = _run_concurrently(lambda: places.update_or_create_place(factories.place_data("p1")))

        assert errors == []
        assert len({p["id"] for p in results}) == 1
        assert places.get_place("p1")["id"] == results[0]["id"]

    @pytest.mark.parametrize("tomtom_id", ["", "\ud800"])
    def test_unstorable_tomtom_id_raises(self, firestore_db, tomtom_id):
        with pytest.raises(places.InvalidDocumentKey):
            places.update_or_create_place(factories.place_data(tomtom_id) | {"tomtom_id": tomtom_id})


class TestGetPlace:
    def test_round_trips(self, place):
        assert places.get_place("place-1") == place

    @pytest.mark.parametrize("tomtom_id", ["nope", "", "\ud800"])
    def test_unknown_or_unstorable(self, firestore_db, tomtom_id):
        assert places.get_place(tomtom_id) is None


class TestRecentPlaces:
    def test_newest_first_up_to_the_limit(self, make_place):
        created = [make_place(f"p{i}") for i in range(4)]

        assert [p["tomtom_id"] for p in places.recent_places(3)] == ["p3", "p2", "p1"]
        assert len(places.recent_places()) == len(created)

    def test_empty(self, firestore_db):
        assert places.recent_places() == []


class TestSearchLimits:
    @pytest.mark.parametrize("query", ["", "   ", "\t\n"])
    def test_blank_query_returns_nothing(self, make_place, query):
        make_place(name="Anything")

        assert places.search_places(query) == []

    @pytest.mark.parametrize("limit", [0, -1])
    def test_non_positive_limit_returns_nothing(self, make_place, limit):
        make_place(name="Pizza")

        assert places.search_places("pizza", limit=limit) == []


# --- Saved places ---


class TestSavePlace:
    def test_creates_a_bookmark_with_defaults(self, user, place):
        saved = places.save_place(user, place)

        assert saved == {
            "id": saved["id"],
            "place": place,
            "custom_name": None,
            "icon": None,
            "color": None,
            "is_pinned": False,
            "is_check_it_out": False,
            "average_visit_length": None,
        }
        assert places.get_saved_place(user, place) == saved

    def test_is_idempotent_and_keeps_the_id(self, user, place):
        first = places.save_place(user, place, custom_name="Fave")
        again = places.save_place(user, place)
        renamed = places.save_place(user, place, custom_name="Renamed")

        assert first["id"] == again["id"] == renamed["id"]
        assert again["custom_name"] == "Fave"  # not cleared without a new name
        assert renamed["custom_name"] == "Renamed"
        assert len(places.list_saved_places(user)) == 1

    def test_saving_again_keeps_other_fields(self, user, place, make_bookmark):
        make_bookmark(user, place, is_pinned=True, icon="star")

        again = places.save_place(user, place, custom_name="New")

        assert (again["is_pinned"], again["icon"], again["custom_name"]) == (True, "star", "New")

    def test_bookmark_ids_are_sequential(self, user, make_place):
        ids = [places.save_place(user, make_place())["id"] for _ in range(3)]

        assert ids == [ids[0], ids[0] + 1, ids[0] + 2]

    def test_concurrent_saves_create_one_bookmark(self, user, place):
        results, errors = _run_concurrently(lambda: places.save_place(user, place))

        assert errors == []
        assert len({s["id"] for s in results}) == 1
        assert len(places.list_saved_places(user)) == 1

    def test_bookmarks_are_per_user(self, make_user, place):
        alice, bob = make_user("alice"), make_user("bob")

        a = places.save_place(alice, place, custom_name="Alice's")
        b = places.save_place(bob, place, custom_name="Bob's")

        assert a["id"] != b["id"]
        assert places.get_saved_place(alice, place)["custom_name"] == "Alice's"
        assert places.get_saved_place(bob, place)["custom_name"] == "Bob's"


class TestSavedPlaceDocument:
    def test_rejects_unknown_fields(self, place):
        with pytest.raises(ValueError, match="bogus"):
            places.saved_place_document(1, place, bogus=True)


class TestUpdateSavedPlace:
    def test_applies_fields(self, user, place, make_bookmark):
        saved = make_bookmark(user, place)

        updated = places.update_saved_place(user, place, is_pinned=True, color="#123456")

        assert updated == {**saved, "is_pinned": True, "color": "#123456"}
        assert places.get_saved_place(user, place) == updated

    def test_no_fields_returns_the_bookmark_unchanged(self, user, place, make_bookmark):
        saved = make_bookmark(user, place, icon="star")

        assert places.update_saved_place(user, place) == saved

    def test_missing_bookmark_returns_none_and_creates_nothing(self, user, place):
        assert places.update_saved_place(user, place, is_pinned=True) is None
        assert places.get_saved_place(user, place) is None

    def test_only_changes_that_users_bookmark(self, make_user, place, make_bookmark):
        alice, bob = make_user("alice"), make_user("bob")
        make_bookmark(alice, place)
        bobs = make_bookmark(bob, place)

        places.update_saved_place(alice, place, is_pinned=True)

        assert places.get_saved_place(bob, place) == bobs


class TestDeleteSavedPlace:
    def test_deletes_only_that_users_bookmark(self, make_user, place, make_bookmark):
        alice, bob = make_user("alice"), make_user("bob")
        make_bookmark(alice, place)
        make_bookmark(bob, place)

        assert places.delete_saved_place(alice, "place-1") is True
        assert places.delete_saved_place(alice, "place-1") is False

        assert places.get_saved_place(alice, place) is None
        assert places.get_saved_place(bob, place) is not None


class TestListSavedPlaces:
    def test_oldest_first(self, user, make_place, make_bookmark):
        for tomtom_id in ("c", "a", "b"):
            make_bookmark(user, make_place(tomtom_id))

        assert [s["place"]["tomtom_id"] for s in places.list_saved_places(user)] == ["c", "a", "b"]

    def test_includes_the_current_place_data(self, user, place, make_bookmark):
        make_bookmark(user, place)
        renamed = places.update_or_create_place(factories.place_data("place-1", name="Renamed"))

        (saved,) = places.list_saved_places(user)

        assert saved["place"] == renamed

    def test_skips_bookmarks_whose_place_is_gone(self, user, make_place, make_bookmark):
        kept, gone = make_place("kept"), make_place("gone")
        make_bookmark(user, kept)
        make_bookmark(user, gone)
        get_client().collection(places.PLACES).document("gone").delete()

        assert [s["place"]["tomtom_id"] for s in places.list_saved_places(user)] == ["kept"]

    def test_only_the_users_bookmarks(self, make_user, make_place, make_bookmark):
        alice, bob = make_user("alice"), make_user("bob")
        make_bookmark(alice, make_place("a"))
        make_bookmark(bob, make_place("b"))

        assert [s["place"]["tomtom_id"] for s in places.list_saved_places(alice)] == ["a"]
        assert [s["place"]["tomtom_id"] for s in places.list_saved_places(bob)] == ["b"]

    def test_empty(self, user):
        assert places.list_saved_places(user) == []


class TestReadingStoredHours:
    """Hours stored before the API checked them are returned in its HH:MM format, or left out."""

    @pytest.mark.parametrize(
        "stored, returned",
        [
            ("09:00", "09:00"),
            ("9:00", "09:00"),
            ("9:5", None),
            ("930", "09:30"),
            ("17", "17:00"),
            ("9am", "09:00"),
            ("9 AM", "09:00"),
            ("9:30p", "21:30"),
            ("12am", "00:00"),
            ("12pm", "12:00"),
            ("9a.m.", "09:00"),
            ("0am", None),
            ("13pm", None),
            ("24:00", "00:00"),
            ("24:30", None),
            ("23:60", None),
            (" 9:00 ", "09:00"),
            ("", None),
            ("noon", None),
            ("9:00:", None),
            (None, None),
            (900, None),
        ],
    )
    def test_time(self, stored, returned):
        assert places._read_time(stored) == returned

    @pytest.mark.parametrize(
        "entry",
        [
            {"day_of_week": 7, "open_time": "09:00", "close_time": "17:00"},
            {"day_of_week": -1, "open_time": "09:00", "close_time": "17:00"},
            {"day_of_week": "1", "open_time": "09:00", "close_time": "17:00"},
            {"day_of_week": True, "open_time": "09:00", "close_time": "17:00"},
            {"day_of_week": 1, "open_time": "09:00"},
            {"day_of_week": 1, "open_time": "09:00", "close_time": "late"},
            "Mon 9-5",
        ],
    )
    def test_entries_that_cant_be_read_are_left_out(self, entry):
        good = {"day_of_week": 1, "open_time": "10:00", "close_time": "11:00"}

        assert places._read_hours([entry, good]) == [good]

    def test_sorted_as_read(self):
        stored = factories.hours((1, "10:00", "12:00"), (1, "9:00", "9:30"), (0, "13:00", "14:00"))

        assert places._read_hours(stored) == factories.hours(
            (0, "13:00", "14:00"), (1, "09:00", "09:30"), (1, "10:00", "12:00")
        )

    @pytest.mark.parametrize("stored", [None, "09:00-17:00", {"day_of_week": 1}])
    def test_hours_that_arent_a_list_are_empty(self, stored):
        assert places._read_hours(stored) == []
