"""
Firestore persistence for places and saved places (bookmarks).

Layout:
    places/{doc_id(tomtom_id)}                  place data, with business hours embedded
    users/{user_doc}/saved_places/{place_doc}   a user's bookmark of a place

Functions return plain dicts shaped like the API schemas.
"""
import math
import re

from google.api_core.exceptions import NotFound
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from google.cloud.firestore_v1.field_path import FieldPath

from services.firestore import allocate_id, doc_id, get_client
from services.geo import MAX_RADIUS_KM, distance_km, encode_geohash, geohash_query_prefixes

PLACES = "places"
SAVED_PLACES = "saved_places"

# Longest substring indexed for name search; longer query words are truncated to this.
_MAX_SEARCH_TERM_LENGTH = 20
# Candidates fetched per round trip while filtering search results.
_SEARCH_PAGE_SIZE = 100
# Cost guard: stop after reading this many candidates even if `limit` matches weren't found.
# Only reached when the most selective query word is very common but the full query is rare.
_MAX_SEARCH_CANDIDATES = 2000

MAX_NEARBY_RADIUS_KM = MAX_RADIUS_KM


def _places():
    return get_client().collection(PLACES)


def _saved_places(user):
    return get_client().collection("users").document(user.doc_id).collection(SAVED_PLACES)


def _normalize_text(text: str) -> str:
    """Case-fold and collapse whitespace. Shared by the index and the query so they agree."""
    return " ".join((text or "").casefold().split())


def _words(text: str):
    return re.findall(r"\w+", _normalize_text(text))


def _search_terms(name: str):
    """
    Every substring (up to _MAX_SEARCH_TERM_LENGTH characters) of every word in the name, so a
    query word can be found with array_contains wherever it falls inside a word.
    """
    terms = set()
    for word in _words(name):
        for start in range(len(word)):
            for end in range(start + 1, min(len(word), start + _MAX_SEARCH_TERM_LENGTH) + 1):
                terms.add(word[start:end])
    return sorted(terms)


def _normalize_hours(hours):
    normalized = [
        {
            "day_of_week": h["day_of_week"] if isinstance(h, dict) else h.day_of_week,
            "open_time": (h["open_time"] if isinstance(h, dict) else h.open_time)[:5],
            "close_time": (h["close_time"] if isinstance(h, dict) else h.close_time)[:5],
        }
        for h in hours
    ]
    return sorted(normalized, key=lambda h: (h["day_of_week"], h["open_time"]))


def _location_fields(lat, lng):
    return {
        "location": firestore.GeoPoint(lat, lng),
        "geohash": encode_geohash(lat, lng),
    }


def _to_place(data: dict) -> dict:
    location = data["location"]
    return {
        "id": data["id"],
        "tomtom_id": data["tomtom_id"],
        "name": data["name"],
        "address": data["address"],
        "location": {"lat": location.latitude, "lng": location.longitude},
        "phone": data.get("phone"),
        "website": data.get("website"),
        "categories": data.get("categories", []),
        "hours": data.get("hours", []),
    }


def get_place(tomtom_id: str):
    snapshot = _places().document(doc_id(tomtom_id)).get()
    return _to_place(snapshot.to_dict()) if snapshot.exists else None


def update_or_create_place(data: dict) -> dict:
    """Upsert TomTom (or user-supplied) place data. Mirrors the old get_or_create + update logic."""
    client = get_client()
    ref = _places().document(doc_id(data["tomtom_id"]))
    location = data.get("location") or {}
    lat, lng = location.get("lat"), location.get("lng")
    hours = _normalize_hours(data.get("hours") or [])

    @firestore.transactional
    def upsert(transaction):
        snapshot = ref.get(transaction=transaction)

        if not snapshot.exists:
            place = {
                "id": allocate_id(PLACES),
                "tomtom_id": data["tomtom_id"],
                "name": data.get("name"),
                "search_terms": _search_terms(data.get("name")),
                "address": data.get("address"),
                "phone": data.get("phone"),
                "website": data.get("website"),
                "categories": data.get("categories") or [],
                "hours": hours,
                "created_at": firestore.SERVER_TIMESTAMP,
                **_location_fields(lat, lng),
            }
            transaction.set(ref, place)
            return place

        place = snapshot.to_dict()
        updates = {}
        current = place["location"]
        if lat != current.latitude or lng != current.longitude:
            updates.update(_location_fields(lat, lng))
        if data.get("name") and place.get("name") != data["name"]:
            updates["name"] = data["name"]
        search_terms = _search_terms(updates.get("name", place.get("name")))
        if place.get("search_terms") != search_terms:  # also heals docs indexed by older code
            updates["search_terms"] = search_terms
        for field in ("address", "phone", "website", "categories"):
            if data.get(field) and place.get(field) != data[field]:
                updates[field] = data[field]
        if hours:
            updates["hours"] = hours

        if updates:
            transaction.update(ref, updates)
            place.update(updates)
        return place

    return _to_place(upsert(client.transaction()))


def search_places(query: str, limit: int = 20):
    """
    Case-insensitive substring search on place names, like the old `name__icontains=query`
    (except that whitespace runs are collapsed and the query is trimmed). Queries without any
    word character return nothing, since they can't be looked up in the index.

    Candidates come from an array_contains on one query word, then the full query is checked
    in memory. Any name containing the query contains every one of its words inside one of its
    own words (a run of word characters in the query is a run of word characters in the name,
    so it can't cross a word boundary there). _search_terms indexes every substring of every
    word up to _MAX_SEARCH_TERM_LENGTH characters, so each query word, truncated to that length,
    is indexed on every matching name, whether it's a whole word, a word's prefix or suffix
    (first/last query word) or a fragment from mid-word. Using the longest word just narrows
    the candidates.
    """
    needle = _normalize_text(query)
    words = _words(query)
    if not words or limit <= 0:
        return []
    term = max(words, key=len)[:_MAX_SEARCH_TERM_LENGTH]

    # Only the implicit document-ID order, so the automatic single-field index serves this.
    candidates = (
        _places()
        .where(filter=FieldFilter("search_terms", "array_contains", term))
        .order_by(FieldPath.document_id())
    )
    matches = []
    scanned = 0
    cursor = None
    while scanned < _MAX_SEARCH_CANDIDATES:
        page_size = min(_SEARCH_PAGE_SIZE, _MAX_SEARCH_CANDIDATES - scanned)
        page = candidates.start_after(cursor) if cursor is not None else candidates
        snapshots = list(page.limit(page_size).stream())
        for snapshot in snapshots:
            data = snapshot.to_dict()
            if needle in _normalize_text(data.get("name")):
                matches.append(_to_place(data))
                if len(matches) == limit:
                    return matches
        scanned += len(snapshots)
        if len(snapshots) < page_size:
            break
        cursor = snapshots[-1]
    return matches


def reindex_search_terms(batch_size: int = 400) -> int:
    """
    Rewrite `search_terms` on every place whose index is out of date (e.g. written before the
    index switched from word prefixes to substrings). Returns the number of places updated.

    For local/dev data; run with
    `uv run python manage.py shell -c "from apps.places.repository import reindex_search_terms; print(reindex_search_terms())"`.
    """
    client = get_client()
    query = _places().order_by(FieldPath.document_id())
    updated = 0
    cursor = None
    while True:
        page = query.start_after(cursor) if cursor is not None else query
        snapshots = list(page.limit(batch_size).stream())
        batch = client.batch()
        pending = 0
        for snapshot in snapshots:
            data = snapshot.to_dict()
            terms = _search_terms(data.get("name"))
            if data.get("search_terms") != terms:
                batch.update(snapshot.reference, {"search_terms": terms})
                pending += 1
        if pending:
            batch.commit()
            updated += pending
        if len(snapshots) < batch_size:
            return updated
        cursor = snapshots[-1]


def nearby_places(lat: float, lng: float, radius_km: float):
    """
    Places within `radius_km` of (lat, lng), ordered by ID. Raises ValueError for out-of-range
    input, including radius_km above MAX_NEARBY_RADIUS_KM, so it never reads a large region.
    """
    if not (math.isfinite(lng) and -180.0 <= lng <= 180.0):
        raise ValueError(f"lng must be within [-180, 180], got {lng}")
    prefixes = geohash_query_prefixes(lat, lng, radius_km)  # validates lat and radius_km

    seen = {}
    for prefix in prefixes:
        query = _places().where(filter=FieldFilter("geohash", ">=", prefix)).where(
            filter=FieldFilter("geohash", "<", prefix + "~")
        )
        for snapshot in query.stream():
            seen[snapshot.id] = snapshot.to_dict()

    places = []
    for data in seen.values():
        location = data["location"]
        if distance_km(lat, lng, location.latitude, location.longitude) <= radius_km:
            places.append(_to_place(data))
    return sorted(places, key=lambda p: p["id"])


def recent_places(limit: int = 10):
    """Most recently created places. Ordered by creation time, since IDs aren't allocated in order."""
    query = _places().order_by("created_at", direction=firestore.Query.DESCENDING).limit(limit)
    return [_to_place(s.to_dict()) for s in query.stream()]


# Saved places

_SAVED_PLACE_FIELDS = ("custom_name", "icon", "color", "is_pinned", "is_check_it_out", "average_visit_length")


def _to_saved_place(data: dict, place: dict) -> dict:
    return {"id": data["id"], "place": place, **{f: data.get(f) for f in _SAVED_PLACE_FIELDS}}


def get_saved_place(user, place: dict):
    snapshot = _saved_places(user).document(doc_id(place["tomtom_id"])).get()
    return _to_saved_place(snapshot.to_dict(), place) if snapshot.exists else None


def save_place(user, place: dict, custom_name=None) -> dict:
    """Bookmark `place` for `user` (get_or_create). Updates the custom name if one is given."""
    client = get_client()
    ref = _saved_places(user).document(doc_id(place["tomtom_id"]))

    @firestore.transactional
    def get_or_create(transaction):
        snapshot = ref.get(transaction=transaction)
        if snapshot.exists:
            data = snapshot.to_dict()
            if custom_name:
                data["custom_name"] = custom_name
                transaction.update(ref, {"custom_name": custom_name})
            return data

        data = {
            "id": allocate_id(SAVED_PLACES),
            "place_id": place["id"],
            "tomtom_id": place["tomtom_id"],
            "custom_name": custom_name,
            "icon": None,
            "color": None,
            "is_pinned": False,
            "is_check_it_out": False,
            "average_visit_length": None,
            "created_at": firestore.SERVER_TIMESTAMP,
        }
        transaction.set(ref, data)
        return data

    return _to_saved_place(get_or_create(client.transaction()), place)


def update_saved_place(user, place: dict, **fields):
    """Apply `fields` to the user's bookmark of `place`. Returns None if it isn't bookmarked."""
    ref = _saved_places(user).document(doc_id(place["tomtom_id"]))

    # Transactional, so a bookmark deleted after the read retries the transaction (and returns
    # None) instead of failing the update with NotFound.
    @firestore.transactional
    def update(transaction):
        snapshot = ref.get(transaction=transaction)
        if not snapshot.exists:
            return None
        data = snapshot.to_dict()
        if fields:
            transaction.update(ref, fields)
            data.update(fields)
        return data

    data = update(get_client().transaction())
    return _to_saved_place(data, place) if data is not None else None


def delete_saved_place(user, place: dict) -> bool:
    """Delete the user's bookmark of `place`. Returns False if it wasn't bookmarked."""
    ref = _saved_places(user).document(doc_id(place["tomtom_id"]))
    # One atomic call: the precondition fails with NotFound if the bookmark is already gone,
    # so concurrent deletes can't both report success.
    try:
        ref.delete(option=get_client().write_option(exists=True))
    except NotFound:
        return False
    return True


def list_saved_places(user):
    saved = [s.to_dict() for s in _saved_places(user).order_by("id").stream()]
    refs = [_places().document(doc_id(s["tomtom_id"])) for s in saved]
    places = {s.id: _to_place(s.to_dict()) for s in get_client().get_all(refs) if s.exists}
    return [
        _to_saved_place(s, places[doc_id(s["tomtom_id"])])
        for s in saved
        if doc_id(s["tomtom_id"]) in places
    ]
