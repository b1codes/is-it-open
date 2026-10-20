"""The seed_e2e management command, which docker-compose.e2e.yml runs before the E2E journeys."""

from io import StringIO

import pytest
from django.core.management import CommandError, call_command

from apps.places import repository as places
from apps.users import repository as users
from apps.users.management.commands.seed_e2e import SEED_PASSWORD, SEED_USERNAME


def _seed():
    call_command("seed_e2e", stdout=StringIO())


def _place(tomtom_id):
    return {"tomtom_id": tomtom_id, "name": tomtom_id, "address": "", "location": {"lat": 0, "lng": 0}}


def _bookmarks(user):
    return {s["place"]["name"]: s for s in places.list_saved_places(user)}


def test_creates_the_account_with_a_home_and_bookmarks(firestore_db):
    _seed()

    user = users.authenticate(SEED_USERNAME, SEED_PASSWORD)
    assert user is not None
    assert (user.home_city, user.home_lat, user.home_lng) == ("Springfield", 39.80178, -89.64352)
    bookmarks = _bookmarks(user)
    assert bookmarks.keys() == {"Joe's Pizza", "Riverside Community Garden"}
    assert bookmarks["Joe's Pizza"]["is_pinned"] is True
    assert bookmarks["Riverside Community Garden"]["is_pinned"] is False


def test_the_custom_place_is_found_by_local_search(firestore_db):
    _seed()

    assert [p["name"] for p in places.search_places("garden")] == ["Riverside Community Garden"]


def test_rerunning_resets_the_account(firestore_db):
    _seed()
    user = users.get_user(SEED_USERNAME)
    user.first_name = "Changed"
    users.save_user(user, ["first_name"])
    places.delete_saved_place(user, "Tu4lEjRtadpLbiAPajPyOQ")
    places.save_place(user, places.update_or_create_place(_place("extra")))

    _seed()

    user = users.get_user(SEED_USERNAME)
    assert user.first_name == "Sam"
    assert _bookmarks(user).keys() == {"Joe's Pizza", "Riverside Community Garden"}


def test_refuses_to_run_outside_the_emulator(firestore_db, settings):
    settings.FIRESTORE_EMULATOR_HOST = ""

    with pytest.raises(CommandError, match="emulator"):
        _seed()
    assert users.get_user(SEED_USERNAME) is None
