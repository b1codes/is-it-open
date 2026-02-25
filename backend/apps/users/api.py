from ninja import Router, Schema
from django.contrib.auth.models import User
from django.contrib.auth import authenticate
from django.shortcuts import get_object_or_404
from ninja.errors import HttpError
from .models import AuthToken, UserProfile
from typing import Optional

router = Router()

class LoginInput(Schema):
    username: str
    password: str

class AuthOutput(Schema):
    token: str
    username: str
    id: int
    email: Optional[str] = None
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    home_address: Optional[str] = ''
    home_lat: Optional[float] = None
    home_lng: Optional[float] = None
    work_address: Optional[str] = ''
    work_lat: Optional[float] = None
    work_lng: Optional[float] = None
    use_current_location: bool = False

class RegisterInput(Schema):
    username: str
    password: str
    email: Optional[str] = None

@router.post("/login", response=AuthOutput)
def login(request, data: LoginInput):
    user = authenticate(username=data.username, password=data.password)
    if not user:
        raise HttpError(401, "Invalid credentials")
    
    token, created = AuthToken.objects.get_or_create(user=user)
    # Ensure profile exists
    if not hasattr(user, 'profile'):
        UserProfile.objects.create(user=user)
    
    return {
        "token": token.key,
        "username": user.username,
        "id": user.id,
        "email": user.email,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "home_address": user.profile.home_address,
        "home_lat": user.profile.home_lat,
        "home_lng": user.profile.home_lng,
        "work_address": user.profile.work_address,
        "work_lat": user.profile.work_lat,
        "work_lng": user.profile.work_lng,
        "use_current_location": user.profile.use_current_location
    }

@router.post("/register", response=AuthOutput)
def register(request, data: RegisterInput):
    if User.objects.filter(username=data.username).exists():
        raise HttpError(400, "Username already taken")
    
    user = User.objects.create_user(
        username=data.username,
        password=data.password,
        email=data.email
    )
    
    token = AuthToken.objects.create(user=user)
    # Create UserProfile
    profile = UserProfile.objects.create(user=user)
    
    return {
        "token": token.key,
        "username": user.username,
        "id": user.id,
        "email": user.email,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "home_address": profile.home_address,
        "home_lat": profile.home_lat,
        "home_lng": profile.home_lng,
        "work_address": profile.work_address,
        "work_lat": profile.work_lat,
        "work_lng": profile.work_lng,
        "use_current_location": profile.use_current_location
    }

@router.get("/me", response=AuthOutput)
def me(request):
    # This endpoint will require auth, handled by global or router level security
    if not request.user.is_authenticated:
        raise HttpError(401, "Unauthorized")
    
    # We need to get the token for the response schema
    # If using standard django auth (session), there is no token.
    # But we are using token auth, so we can get it from the user.
    try:
        token = request.user.auth_token.key
    except AuthToken.DoesNotExist:
        # Create one if missing for some reason
        token_obj = AuthToken.objects.create(user=request.user)
        token = token_obj.key

    # Ensure profile exists
    if not hasattr(request.user, 'profile'):
        UserProfile.objects.create(user=request.user)

    return {
        "token": token,
        "username": request.user.username,
        "id": request.user.id,
        "email": request.user.email,
        "first_name": request.user.first_name,
        "last_name": request.user.last_name,
        "home_address": request.user.profile.home_address,
        "home_lat": request.user.profile.home_lat,
        "home_lng": request.user.profile.home_lng,
        "work_address": request.user.profile.work_address,
        "work_lat": request.user.profile.work_lat,
        "work_lng": request.user.profile.work_lng,
        "use_current_location": request.user.profile.use_current_location
    }

class ProfileUpdateInput(Schema):
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    home_address: Optional[str] = None
    home_lat: Optional[float] = None
    home_lng: Optional[float] = None
    work_address: Optional[str] = None
    work_lat: Optional[float] = None
    work_lng: Optional[float] = None
    use_current_location: Optional[bool] = None

@router.put("/me", response=AuthOutput)
def update_me(request, data: ProfileUpdateInput):
    if not request.user.is_authenticated:
        raise HttpError(401, "Unauthorized")
    
    user = request.user
    
    # Update User fields if provided
    user_updated = False
    if data.first_name is not None:
        user.first_name = data.first_name
        user_updated = True
    if data.last_name is not None:
        user.last_name = data.last_name
        user_updated = True
        
    if user_updated:
        user.save()
        
    # Ensure profile exists
    if not hasattr(user, 'profile'):
        UserProfile.objects.create(user=user)
        
    profile = user.profile
    
    # Update UserProfile fields if provided
    profile_updated = False
    if data.home_address is not None:
        profile.home_address = data.home_address
        profile_updated = True
    if data.home_lat is not None:
        profile.home_lat = data.home_lat
        profile_updated = True
    if data.home_lng is not None:
        profile.home_lng = data.home_lng
        profile_updated = True
        
    if data.work_address is not None:
        profile.work_address = data.work_address
        profile_updated = True
    if data.work_lat is not None:
        profile.work_lat = data.work_lat
        profile_updated = True
    if data.work_lng is not None:
        profile.work_lng = data.work_lng
        profile_updated = True
        
    if data.use_current_location is not None:
        profile.use_current_location = data.use_current_location
        profile_updated = True
        
    if profile_updated:
        profile.save()

    try:
        token = user.auth_token.key
    except AuthToken.DoesNotExist:
        token_obj = AuthToken.objects.create(user=user)
        token = token_obj.key

    return {
        "token": token,
        "username": user.username,
        "id": user.id,
        "email": user.email,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "home_address": profile.home_address,
        "home_lat": profile.home_lat,
        "home_lng": profile.home_lng,
        "work_address": profile.work_address,
        "work_lat": profile.work_lat,
        "work_lng": profile.work_lng,
        "use_current_location": profile.use_current_location
    }
