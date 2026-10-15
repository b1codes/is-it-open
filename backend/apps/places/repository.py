"""
Firestore persistence for places and saved places (bookmarks).

Layout:
    places/{doc_id(tomtom_id)}                  place data, with business hours embedded
    users/{user_doc}/saved_places/{place_doc}   a user's bookmark of a place

Functions return plain dicts shaped like the API schemas.
"""
import re

from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from services.firestore import allocate_id, doc_id, get_client
from services.geo import distance_km, encode_geohash, geohash_query_prefixes

PLACES = "places"
SAVED_PLACES = "saved_places"

# Longest word prefix indexed for name search; longer query words are truncated to this.
_MAX_SEARCH_TERM_LENGTH = 20


def _places():
    return get_client().collection(PLACES)


def _saved_places(user):
    return get_client().collection("users").document(user.doc_id).collection(SAVED_PLACES)


def _words(text: str):
    return re.findall(r"\w+", (text or "").lower())


def _search_terms(name: str):
    """Every prefix of every word in the name, so a word-prefix query can use array_contains."""
    terms = set()
    for word in _words(name):
        for end in range(1, min(len(word), _MAX_SEARCH_TERM_LENGTH) + 1):
            terms.add(word[:end])
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
                "id": allocate_id(transaction, PLACES),
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
            updates["search_terms"] = _search_terms(data["name"])
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
    """Case-insensitive name search. Matches names containing the query, anchored on a word prefix."""
    words = _words(query)
    if not words:
        return []
    needle = " ".join(query.lower().split())
    term = max(words, key=len)[:_MAX_SEARCH_TERM_LENGTH]

    snapshots = _places().where(filter=FieldFilter("search_terms", "array_contains", term)).limit(limit).stream()
    places = [_to_place(s.to_dict()) for s in snapshots]
    return [p for p in places if needle in p["name"].lower()]


def nearby_places(lat: float, lng: float, radius_km: float):
    seen = {}
    for prefix in geohash_query_prefixes(lat, lng, radius_km):
        query = _places()
        if prefix:
            query = query.where(filter=FieldFilter("geohash", ">=", prefix)).where(
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
    query = _places().order_by("id", direction=firestore.Query.DESCENDING).limit(limit)
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
            "id": allocate_id(transaction, SAVED_PLACES),
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
    snapshot = ref.get()
    if not snapshot.exists:
        return None
    data = snapshot.to_dict()
    if fields:
        ref.update(fields)
        data.update(fields)
    return _to_saved_place(data, place)


def delete_saved_place(user, place: dict) -> bool:
    ref = _saved_places(user).document(doc_id(place["tomtom_id"]))
    if not ref.get().exists:
        return False
    ref.delete()
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
