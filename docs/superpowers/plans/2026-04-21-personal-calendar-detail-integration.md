# Personal Calendar Detail Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show personal calendar events in the place detail view and prevent scheduling "Planned Visits" during those times.

**Architecture:** Move `CalendarDataBloc` to a global scope in `main.dart`. Update `PlaceDetailScreen` to listen to this bloc, merge remote events into its local calendar controller, and validate visits against both business hours and personal events.

**Tech Stack:** Flutter, BLoC, calendar_view, icalendar_parser.

---

### Task 1: Globalize CalendarDataBloc

**Files:**
- Modify: `frontend/lib/main.dart`
- Modify: `frontend/lib/screens/calendar/calendar_screen.dart`

- [ ] **Step 1: Move CalendarDataBloc to root providers in main.dart**

```dart
// frontend/lib/main.dart
// ... imports ...
import 'bloc/calendar/calendar_data_bloc.dart';
import 'bloc/calendar/calendar_data_event.dart';

// In MultiBlocProvider
providers: [
  // ... existing ...
  BlocProvider<CalendarDataBloc>(
    create: (context) {
      final bloc = CalendarDataBloc(
        apiService: context.read<ApiService>(),
      );
      bloc.add(LoadSavedPlaces());
      bloc.add(const InitDeviceCalendar());
      // Remote events will be loaded when Auth state changes or screen builds
      return bloc;
    },
  ),
],
```

- [ ] **Step 2: Update CalendarScreen to remove local provider**

Remove the `MultiBlocProvider` that wraps `_CalendarScreenView` and instead just ensure `LoadRemoteEvents` is called if needed.

- [ ] **Step 3: Add LoadRemoteEvents trigger in HomeScreen or main.dart**

Since `CalendarDataBloc` is global, we should trigger `LoadRemoteEvents` when the user is authenticated.

```dart
// In main.dart, wrap the MaterialApp's home in a BlocListener for AuthBloc
BlocListener<AuthBloc, AuthState>(
  listener: (context, state) {
    if (state is AuthAuthenticated) {
      final url = state.user.calendarSubscriptionUrl;
      if (url != null && url.isNotEmpty) {
        context.read<CalendarDataBloc>().add(LoadRemoteEvents(url));
      }
    }
  },
  child: ...
)
```

- [ ] **Step 4: Verify main calendar still works**

Run: `flutter test test/screens/calendar/calendar_screen_test.dart` (if exists) or manual verification.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/main.dart frontend/lib/screens/calendar/calendar_screen.dart
git commit -m "feat: move CalendarDataBloc to global scope"
```

### Task 2: Merge Remote Events into PlaceDetailScreen

**Files:**
- Modify: `frontend/lib/screens/places/place_detail_screen.dart`

- [ ] **Step 1: Wrap PlaceDetailScreen body in BlocBuilder for CalendarDataBloc**

```dart
// frontend/lib/screens/places/place_detail_screen.dart
@override
Widget build(BuildContext context) {
  return BlocBuilder<CalendarDataBloc, CalendarDataState>(
    builder: (context, dataState) {
      // ... existing build logic ...
    },
  );
}
```

- [ ] **Step 2: Update _buildEventController to accept dataState and include remoteEvents**

```dart
EventController<Object?> _buildEventController(CalendarDataState dataState) {
  final controller = EventController<Object?>();
  // ... existing business hours logic ...
  
  // Add remote events
  controller.addAll(dataState.remoteEvents);

  // ... existing planned visit logic ...
  return controller;
}
```

- [ ] **Step 3: Update _buildEventTile to handle personal events**

```dart
Widget _buildEventTile(
  DateTime date,
  List<CalendarEventData<dynamic>> events,
  Rect boundary,
  DateTime startDuration,
  DateTime endDuration,
) {
  if (events.isEmpty) return const SizedBox.shrink();
  final event = events[0];
  final isPlannedVisit = event.title == 'Planned Visit';
  final isOpen = event.title == 'Open';
  final isPersonal = !isPlannedVisit && !isOpen;

  if (isPersonal) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(4),
      child: Text(
        event.title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          overflow: TextOverflow.ellipsis,
        ),
        maxLines: 1,
      ),
    );
  }
  // ... rest of the existing _buildEventTile logic ...
}
```

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/places/place_detail_screen.dart
git commit -m "feat: show personal events in PlaceDetailScreen"
```

### Task 3: Implement Smart Availability Check

**Files:**
- Modify: `frontend/lib/screens/places/place_detail_screen.dart`

- [ ] **Step 1: Add _isAvailableDuring method**

```dart
bool _isAvailableDuring(DateTime start, DateTime end, CalendarDataState dataState) {
  // 1. Must be within business hours
  if (!_isOpenDuring(start, end)) return false;

  // 2. Must not overlap with any personal events
  for (final event in dataState.remoteEvents) {
    final eventStart = event.startTime ?? event.date;
    final eventEnd = event.endTime ?? event.date;

    // Standard overlap check: (StartA < EndB) and (EndA > StartB)
    if (start.isBefore(eventEnd) && end.isAfter(eventStart)) {
      return false;
    }
  }
  return true;
}
```

- [ ] **Step 2: Update conflict feedback SnackBars**

Replace the existing "business hours" check in `onTapUp`, `onDateTap`, and `onVerticalDragUpdate` with `_isAvailableDuring`.

```dart
void _showConflictMessage(DateTime start, DateTime end, CalendarDataState dataState) {
  String message = 'Planned visit must be entirely within open business hours';
  
  // Check if it's a personal conflict specifically for better feedback
  bool isPersonalConflict = false;
  for (final event in dataState.remoteEvents) {
    final eventStart = event.startTime ?? event.date;
    final eventEnd = event.endTime ?? event.date;
    if (start.isBefore(eventEnd) && end.isAfter(eventStart)) {
      isPersonalConflict = true;
      break;
    }
  }

  if (isPersonalConflict) {
    message = 'Conflicts with a personal calendar event';
  }

  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.orange,
      duration: const Duration(seconds: 2),
    ),
  );
}
```

- [ ] **Step 3: Update interaction handlers**

```dart
// Example update for onTapUp in _buildEventTile
if (_isAvailableDuring(tappedTime, visitEnd, dataState)) {
  setState(() => _plannedVisitTime = tappedTime);
} else {
  _showConflictMessage(tappedTime, visitEnd, dataState);
}
```

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/places/place_detail_screen.dart
git commit -m "feat: implement conflict detection for personal events"
```

### Task 4: Verification and Testing

**Files:**
- Create: `frontend/test/screens/places/place_detail_conflict_test.dart`

- [ ] **Step 1: Write widget test for conflict detection**

```dart
void main() {
  testWidgets('Planned visit blocked by personal event', (WidgetTester tester) async {
    // 1. Setup mock CalendarDataBloc with a busy event at 10 AM
    // 2. Pump PlaceDetailScreen
    // 3. Attempt to set planned visit at 10 AM
    // 4. Verify SnackBar "Conflicts with a personal calendar event" appears
  });
}
```

- [ ] **Step 2: Run all frontend tests**

Run: `flutter test`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add frontend/test/screens/places/place_detail_conflict_test.dart
git commit -m "test: add personal calendar conflict verification"
```
