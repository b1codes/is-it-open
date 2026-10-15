from ninja import Query, Router, Schema
from ninja.errors import HttpError
from typing import List, Optional

from services.firestore import InvalidDocumentKey
from services.tomtom import TomTomClient
from . import repository

router = Router()

# Schemes
class BusinessHoursSchema(Schema):
    day_of_week: int
    open_time: str
    close_time: str

class LocationSchema(Schema):
    lat: float
    lng: float

class PlaceSchema(Schema):
    id: int
    tomtom_id: str
    name: str
    address: str
    location: LocationSchema
    phone: Optional[str] = None
    website: Optional[str] = None
    categories: List[str] = []
    hours: List[BusinessHoursSchema] = []

class PlaceCreateSchema(Schema):
    tomtom_id: str
    name: str
    address: str
    location: LocationSchema
    phone: Optional[str] = None
    website: Optional[str] = None
    categories: List[str] = []
    hours: List[BusinessHoursSchema] = []

class SavedPlaceSchema(Schema):
    id: int
    place: PlaceSchema
    custom_name: Optional[str] = None
    icon: Optional[str] = None
    color: Optional[str] = None
    is_pinned: bool
    is_check_it_out: bool = False
    average_visit_length: Optional[int] = None

class TogglePinInput(Schema):
    is_pinned: bool

class ToggleCheckItOutInput(Schema):
    is_check_it_out: bool

class UpdateGraphicInput(Schema):
    icon: Optional[str] = None
    color: Optional[str] = None
    custom_name: Optional[str] = None

class UpdateVisitLengthInput(Schema):
    visit_length: Optional[int] = None

class SavePlaceInput(Schema):
    tomtom_id: str
    custom_name: Optional[str] = None

def _get_place_or_404(tomtom_id: str) -> dict:
    place = repository.get_place(tomtom_id)
    if not place:
        raise HttpError(404, "Not Found")
    return place

def _update_saved_place_or_404(request, tomtom_id: str, **fields) -> dict:
    place = _get_place_or_404(tomtom_id)
    saved_place = repository.update_saved_place(request.auth, place, **fields)
    if not saved_place:
        raise HttpError(404, "Not Found")
    return saved_place

# Endpoints

@router.get("/search", response=List[PlaceCreateSchema])
def search_places(request, query: str):
    client = TomTomClient()
    results = client.search_place(query)
    
    # Search local database for custom places
    local_places = repository.search_places(query)
    tomtom_ids = {r.get('tomtom_id') for r in results if isinstance(r, dict)}
    
    for place in local_places:
        if place["tomtom_id"] not in tomtom_ids:
            results.append(place)
            tomtom_ids.add(place["tomtom_id"])
            
    return results

@router.post("/", response=PlaceSchema)
def create_place(request, payload: PlaceCreateSchema):
    try:
        return repository.update_or_create_place(payload.dict())
    except InvalidDocumentKey:
        raise HttpError(400, "Invalid tomtom_id")

@router.post("/bookmark", response=SavedPlaceSchema)
def bookmark_place(request, payload: SavePlaceInput):
    place = _get_place_or_404(payload.tomtom_id)
    return repository.save_place(request.auth, place, custom_name=payload.custom_name)

@router.get("/bookmarks", response=List[SavedPlaceSchema])
def get_bookmarks(request):
    return repository.list_saved_places(request.auth)

@router.delete("/bookmarks/{tomtom_id}", response={204: None, 404: dict})
def delete_bookmark(request, tomtom_id: str):
    if repository.delete_saved_place(request.auth, tomtom_id):
        return 204, None
    return 404, {"detail": "Bookmark not found"}

@router.patch("/bookmarks/{tomtom_id}/pin", response=SavedPlaceSchema)
def toggle_pin(request, tomtom_id: str, payload: TogglePinInput):
    return _update_saved_place_or_404(request, tomtom_id, is_pinned=payload.is_pinned)

@router.patch("/bookmarks/{tomtom_id}/check-it-out", response=SavedPlaceSchema)
def toggle_check_it_out(request, tomtom_id: str, payload: ToggleCheckItOutInput):
    return _update_saved_place_or_404(request, tomtom_id, is_check_it_out=payload.is_check_it_out)

@router.patch("/bookmarks/{tomtom_id}/graphic", response=SavedPlaceSchema)
def update_graphic(request, tomtom_id: str, payload: UpdateGraphicInput):
    data = payload.dict(exclude_unset=True)
    fields = {}
    if 'icon' in data:
        fields['icon'] = data['icon']
    if 'color' in data:
        fields['color'] = data['color']
    if 'custom_name' in data:
        cn = data['custom_name']
        fields['custom_name'] = cn if cn and cn.strip() else None

    return _update_saved_place_or_404(request, tomtom_id, **fields)

@router.patch("/bookmarks/{tomtom_id}/visit-length", response=SavedPlaceSchema)
def update_visit_length(request, tomtom_id: str, payload: UpdateVisitLengthInput):
    return _update_saved_place_or_404(request, tomtom_id, average_visit_length=payload.visit_length)

@router.get("/nearby", response=List[PlaceSchema])
def get_nearby_places(
    request,
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(5.0, gt=0, le=repository.MAX_NEARBY_RADIUS_KM),
):
    return repository.nearby_places(lat, lng, radius_km)

@router.get("/suggestions", response=List[PlaceCreateSchema])
def get_suggestions(request, lat: Optional[float] = None, lng: Optional[float] = None):
    if lat is not None and lng is not None:
        client = TomTomClient()
        return client.nearby_search(lat, lng)
    
    # Fallback: Get some recently added places
    return repository.recent_places(10)

@router.get("/{tomtom_id}", response=PlaceSchema)
def get_place_details(request, tomtom_id: str):
    # Check if place exists in DB
    place = repository.get_place(tomtom_id)
    
    if place:
        return place
    
    # If not, fetch from TomTom and save
    client = TomTomClient()
    details = client.get_place_details(tomtom_id)
    
    if not details:
        raise HttpError(404, "Place not found in TomTom")

    try:
        return repository.update_or_create_place(details)
    except InvalidDocumentKey:
        raise HttpError(404, "Place not found in TomTom")
