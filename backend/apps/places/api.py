from ninja import Router, Schema
from typing import List, Optional
from django.shortcuts import get_object_or_404
from django.db import transaction

from services.tomtom import TomTomClient
from .models import Place, SavedPlace
from apps.hours.models import BusinessHours

router = Router()

# Schemes
class BusinessHoursSchema(Schema):
    day_of_week: int
    open_time: str
    close_time: str

class PlaceSchema(Schema):
    id: int
    tomtom_id: str
    name: str
    address: str
    latitude: float
    longitude: float
    hours: List[BusinessHoursSchema] = []

    @staticmethod
    def resolve_hours(obj):
        return [
            {
                "day_of_week": h.day_of_week,
                "open_time": h.open_time.strftime("%H:%M"),
                "close_time": h.close_time.strftime("%H:%M"),
            }
            for h in obj.hours.all()
        ]

class PlaceCreateSchema(Schema):
    tomtom_id: str
    name: str
    address: str
    latitude: float
    longitude: float
    hours: List[BusinessHoursSchema] = []

class SavedPlaceSchema(Schema):
    id: int
    place: PlaceSchema
    custom_name: Optional[str] = None

class SavePlaceInput(Schema):
    tomtom_id: str
    custom_name: Optional[str] = None

# Endpoints

@router.get("/search", response=List[PlaceCreateSchema])
def search_places(request, query: str):
    client = TomTomClient()
    results = client.search_place(query)
    
    # Search local database for custom places
    local_places = Place.objects.filter(name__icontains=query)
    tomtom_ids = {r.get('tomtom_id') for r in results if isinstance(r, dict)}
    
    for place in local_places:
        if place.tomtom_id not in tomtom_ids:
            results.append({
                "tomtom_id": place.tomtom_id,
                "name": place.name,
                "address": place.address,
                "latitude": place.latitude,
                "longitude": place.longitude,
                "hours": PlaceSchema.resolve_hours(place)
            })
            tomtom_ids.add(place.tomtom_id)
            
    return results

@router.get("/{tomtom_id}", response=PlaceSchema)
def get_place_details(request, tomtom_id: str):
    # Check if place exists in DB
    place = Place.objects.filter(tomtom_id=tomtom_id).first()
    
    if place:
        return place
    
    # If not, fetch from TomTom and save
    client = TomTomClient()
    details = client.get_place_details(tomtom_id) # Hypothetical method, need to implement in TomTomClient
    
    # For now, let's assume search returns enough info or we implement get_place_details
    # If get_place_details is not implemented, we might return 404 or handle differently.
    # But sticking to plan: Fetch details, store in DB.
    
    # TODO: Implement full details fetch. For now, returning 404 if not cached 
    # as we rely on search results being passed to create.
    # Alternatively, we can use the create_place logic.
    return 404

@router.post("/", response=PlaceSchema)
def create_place(request, payload: PlaceCreateSchema):
    with transaction.atomic():
        place, created = Place.objects.get_or_create(
            tomtom_id=payload.tomtom_id,
            defaults={
                "name": payload.name,
                "address": payload.address,
                "latitude": payload.latitude,
                "longitude": payload.longitude,
            }
        )
        
        # Update hours
        if payload.hours:
            place.hours.all().delete()
            for hour in payload.hours:
                BusinessHours.objects.create(
                    place=place,
                    day_of_week=hour.day_of_week,
                    open_time=hour.open_time,
                    close_time=hour.close_time
                )
    return place

@router.post("/bookmark", response=SavedPlaceSchema)
def bookmark_place(request, payload: SavePlaceInput):
    place = get_object_or_404(Place, tomtom_id=payload.tomtom_id)
    saved_place, created = SavedPlace.objects.get_or_create(
        user=request.auth,
        place=place,
        defaults={"custom_name": payload.custom_name}
    )
    if not created and payload.custom_name:
        saved_place.custom_name = payload.custom_name
        saved_place.save()
    return saved_place
