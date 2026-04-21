# Design Document: Audit Profile API for Coordinate Delivery

**Date:** 2026-04-21  
**Author:** Gemini CLI  
**Task:** 86b9gcmc0  

## Overview
The goal is to ensure the user profile endpoints (`/auth/me` GET and PUT) consistently deliver geocoded coordinates for Home and Work addresses and include all necessary profile fields.

## Current State
- `UserProfile` model stores `home_lat`, `home_lng`, `work_lat`, `work_lng`.
- `AuthOutput` schema includes these coordinate fields and `calendar_subscription_url`.
- `GET /auth/me` return dictionary is missing `calendar_subscription_url`.
- `PUT /auth/me` return dictionary includes all fields but needs verification for coordinate consistency.

## Proposed Changes

### 1. Schema Audit
- Verify `AuthOutput` in `backend/apps/users/api.py` correctly defines all needed fields.
- Keep the name `AuthOutput` as it is used throughout the auth system.

### 2. Endpoint Enhancements
- **`GET /auth/me`**:
    - Add `calendar_subscription_url` to the return dictionary.
    - Ensure all `home_lat`, `home_lng`, `work_lat`, `work_lng` values from `user.profile` are included.
- **`PUT /auth/me`**:
    - Ensure that after geocoding or explicit updates, the returned dictionary reflects the most recent database state for coordinates.

### 3. Testing Strategy
- Create `backend/apps/users/tests_profile.py`.
- **Test Case 1: GET Profile**:
    - Create a user with a profile containing coordinates.
    - Fetch `/auth/me` and verify coordinates and `calendar_subscription_url` are present in JSON.
- **Test Case 2: PUT Profile (Geocoding)**:
    - Update home/work address strings.
    - Verify that the API returns non-null coordinates (mocking `TomTomClient` if possible or using a test env).
    - *Note: Since actual geocoding requires a network call, I will mock the `TomTomClient` to ensure predictable test results.*
- **Test Case 3: PUT Profile (Explicit Coordinates)**:
    - Update profile with explicit `lat`/`lng` values.
    - Verify they are stored and returned correctly.

## Success Criteria
- All profile endpoints return the full set of coordinates if they exist.
- `calendar_subscription_url` is returned in the GET endpoint.
- Tests pass for both retrieval and update scenarios.
