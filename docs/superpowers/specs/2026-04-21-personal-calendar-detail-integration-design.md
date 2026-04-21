# Design Spec: Personal Calendar Integration in Place Detail View

Integrating the user's personal remote calendar into the `PlaceDetailScreen` to provide a holistic view of availability and smarter conflict detection for planned visits.

## 1. Problem Statement
Users currently see business hours in the `PlaceDetailScreen` but cannot see their own personal schedule. This makes the "Planned Visit" feature less useful as it doesn't account for personal conflicts (e.g., a meeting during gym hours).

## 2. Goals
- Show remote calendar events (via ICS proxy) on the `PlaceDetailScreen` calendar.
- Distinguish visually between business hours, personal events, and planned visits.
- Prevent scheduling "Planned Visits" during personal events.
- Maintain a clean UI with strict overflow rules for personal event labels.

## 3. Architecture & Data Flow

### 3.1 Global State Management
The `CalendarDataBloc` will be moved from `CalendarScreen` to the root of the app in `lib/main.dart`.
- **Reasoning**: It needs to be alive and populated before entering a detail screen to ensure immediate availability of remote events.
- **Provider**: `MultiBlocProvider` in `MyApp` will now include `CalendarDataBloc`.

### 3.2 PlaceDetailScreen Logic
The `PlaceDetailScreen` will be wrapped in a `BlocBuilder<CalendarDataBloc, CalendarDataState>`.
- **Event Merging**: The local `_buildEventController` will be updated to include `dataState.remoteEvents` alongside business hours and the planned visit.
- **Conflict Logic**: The `_isOpenDuring` check will be expanded to `_isAvailableDuring`.

## 4. Visual Design
- **Personal Events**:
  - **Color**: `Colors.blueGrey` with 0.6 opacity (neutral "Busy" look).
  - **Tile**: Simple `Container` with 1 line of text, `TextOverflow.ellipsis`, and `fontWeight.w500`.
  - **Interactivity**: Non-interactive (taps on these areas will trigger the "Open" area logic below them if applicable).
- **Business Hours**: `Colors.green` with 0.7 opacity (background layer).
- **Planned Visit**: Primary primary color (Blue) with white border, draggable and tap-to-set.

## 5. Implementation Details

### 5.1 Availability Check
New method `_isAvailableDuring(DateTime start, DateTime end)`:
1.  Check `_isOpenDuring(start, end)` (Business hours check).
2.  Check for any overlap with `remoteEvents` in `CalendarDataBloc`.
3.  Return `true` only if open AND no personal overlap.

### 5.2 Conflict Feedback
- If a user taps or drags into a personal event:
  - **SnackBar**: "Conflicts with a personal calendar event."
  - **Color**: `Colors.orange`.

## 6. Testing Strategy
- **Unit Test**: Test the overlap detection logic with mocked remote events.
- **Widget Test**: 
  - Verify `remoteEvents` from the Bloc are rendered in the `DayView`/`WeekView`.
  - Verify "Planned Visit" cannot be placed over a personal event.

## 7. User Review Required
- snakbar color: `Colors.orange` approved.
- Personal event style: Neutral BlueGrey with ellipsis approved.
