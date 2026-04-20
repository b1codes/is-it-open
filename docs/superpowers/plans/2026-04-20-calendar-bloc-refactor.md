# Calendar Bloc Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the Calendar screen to use `flutter_bloc` for state management, separating visual UI state from asynchronous data fetching.

**Architecture:** Create a `CalendarUiCubit` for synchronous visual state (view type, date navigation, layout toggles) and a `CalendarDataBloc` for asynchronous data fetching (saved places, device calendars, imported iCal, remote subscriptions). The UI will use `BlocBuilder` to react to these states and construct the `EventController` dynamically based on the aggregated data.

**Tech Stack:** Flutter, `flutter_bloc`, `calendar_view`, `device_calendar`, `icalendar_parser`.

---

### Task 1: Create `CalendarUiCubit`

**Files:**
- Create: `frontend/lib/bloc/calendar/calendar_ui_state.dart`
- Create: `frontend/lib/bloc/calendar/calendar_ui_cubit.dart`
- Create: `frontend/test/bloc/calendar/calendar_ui_cubit_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// frontend/test/bloc/calendar/calendar_ui_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:is_it_open/bloc/calendar/calendar_ui_cubit.dart';
import 'package:is_it_open/bloc/calendar/calendar_ui_state.dart';
import 'package:is_it_open/screens/calendar/calendar_screen.dart' show CalendarViewType;

void main() {
  group('CalendarUiCubit', () {
    late CalendarUiCubit cubit;
    late DateTime now;

    setUp(() {
      now = DateTime.now();
      cubit = CalendarUiCubit(initialDate: now);
    });

    tearDown(() {
      cubit.close();
    });

    test('initial state is correct', () {
      expect(cubit.state.currentView, CalendarViewType.week);
      expect(cubit.state.baseDate, now);
      expect(cubit.state.isCalendarExpanded, false);
      expect(cubit.state.isCalendarMinimized, false);
    });

    blocTest<CalendarUiCubit, CalendarUiState>(
      'emits new state when changeViewType is called',
      build: () => cubit,
      act: (cubit) => cubit.changeViewType(CalendarViewType.singleDay),
      expect: () => [
        CalendarUiState(
          currentView: CalendarViewType.singleDay,
          baseDate: now,
          isCalendarExpanded: false,
          isCalendarMinimized: false,
        )
      ],
    );

    blocTest<CalendarUiCubit, CalendarUiState>(
      'emits new state when navigateDate is called',
      build: () => cubit,
      act: (cubit) => cubit.navigateDate(now.add(const Duration(days: 1))),
      expect: () => [
        CalendarUiState(
          currentView: CalendarViewType.week,
          baseDate: now.add(const Duration(days: 1)),
          isCalendarExpanded: false,
          isCalendarMinimized: false,
        )
      ],
    );

    blocTest<CalendarUiCubit, CalendarUiState>(
      'emits new state when toggleExpanded is called',
      build: () => cubit,
      act: (cubit) => cubit.toggleExpanded(),
      expect: () => [
        CalendarUiState(
          currentView: CalendarViewType.week,
          baseDate: now,
          isCalendarExpanded: true,
          isCalendarMinimized: false,
        )
      ],
    );

    blocTest<CalendarUiCubit, CalendarUiState>(
      'emits new state when toggleMinimized is called',
      build: () => cubit,
      act: (cubit) => cubit.toggleMinimized(),
      expect: () => [
        CalendarUiState(
          currentView: CalendarViewType.week,
          baseDate: now,
          isCalendarExpanded: false,
          isCalendarMinimized: true,
        )
      ],
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && flutter test test/bloc/calendar/calendar_ui_cubit_test.dart`
Expected: FAIL because files/classes do not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// frontend/lib/bloc/calendar/calendar_ui_state.dart
import 'package:equatable/equatable.dart';
import '../../screens/calendar/calendar_screen.dart' show CalendarViewType;

class CalendarUiState extends Equatable {
  final CalendarViewType currentView;
  final DateTime baseDate;
  final bool isCalendarExpanded;
  final bool isCalendarMinimized;

  const CalendarUiState({
    required this.currentView,
    required this.baseDate,
    required this.isCalendarExpanded,
    required this.isCalendarMinimized,
  });

  CalendarUiState copyWith({
    CalendarViewType? currentView,
    DateTime? baseDate,
    bool? isCalendarExpanded,
    bool? isCalendarMinimized,
  }) {
    return CalendarUiState(
      currentView: currentView ?? this.currentView,
      baseDate: baseDate ?? this.baseDate,
      isCalendarExpanded: isCalendarExpanded ?? this.isCalendarExpanded,
      isCalendarMinimized: isCalendarMinimized ?? this.isCalendarMinimized,
    );
  }

  @override
  List<Object?> get props => [currentView, baseDate, isCalendarExpanded, isCalendarMinimized];
}
```

```dart
// frontend/lib/bloc/calendar/calendar_ui_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'calendar_ui_state.dart';
import '../../screens/calendar/calendar_screen.dart' show CalendarViewType;

class CalendarUiCubit extends Cubit<CalendarUiState> {
  CalendarUiCubit({DateTime? initialDate})
      : super(CalendarUiState(
          currentView: CalendarViewType.week,
          baseDate: initialDate ?? DateTime.now(),
          isCalendarExpanded: false,
          isCalendarMinimized: false,
        ));

  void changeViewType(CalendarViewType type) {
    emit(state.copyWith(currentView: type, baseDate: DateTime.now()));
  }

  void navigateDate(DateTime newDate) {
    emit(state.copyWith(baseDate: newDate));
  }

  void toggleExpanded() {
    emit(state.copyWith(
      isCalendarExpanded: !state.isCalendarExpanded,
      isCalendarMinimized: false,
    ));
  }

  void toggleMinimized() {
    emit(state.copyWith(
      isCalendarMinimized: !state.isCalendarMinimized,
      isCalendarExpanded: false,
    ));
  }
}
```

*(Note: We might need to make `CalendarViewType` accessible outside `calendar_screen.dart` if we want to avoid circular imports later, but for now referencing it is fine, or we can move the enum to `calendar_ui_state.dart`. Let's move the enum to `calendar_ui_state.dart` to be cleaner, and we will update `calendar_screen.dart` to import it from there in Task 3).*

Let's adjust Step 3 slightly to define the enum in `calendar_ui_state.dart`:

```dart
// frontend/lib/bloc/calendar/calendar_ui_state.dart
import 'package:equatable/equatable.dart';

enum CalendarViewType { singleDay, threeDay, week }

class CalendarUiState extends Equatable {
  final CalendarViewType currentView;
  final DateTime baseDate;
  final bool isCalendarExpanded;
  final bool isCalendarMinimized;

  const CalendarUiState({
    required this.currentView,
    required this.baseDate,
    required this.isCalendarExpanded,
    required this.isCalendarMinimized,
  });

  CalendarUiState copyWith({
    CalendarViewType? currentView,
    DateTime? baseDate,
    bool? isCalendarExpanded,
    bool? isCalendarMinimized,
  }) {
    return CalendarUiState(
      currentView: currentView ?? this.currentView,
      baseDate: baseDate ?? this.baseDate,
      isCalendarExpanded: isCalendarExpanded ?? this.isCalendarExpanded,
      isCalendarMinimized: isCalendarMinimized ?? this.isCalendarMinimized,
    );
  }

  @override
  List<Object?> get props => [currentView, baseDate, isCalendarExpanded, isCalendarMinimized];
}
```
Update the test import from `package:is_it_open/screens/calendar/calendar_screen.dart show CalendarViewType;` to `package:is_it_open/bloc/calendar/calendar_ui_state.dart show CalendarViewType;`.

Update `calendar_ui_cubit.dart` imports to remove the `calendar_screen.dart` import.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && flutter test test/bloc/calendar/calendar_ui_cubit_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/bloc/calendar/ frontend/test/bloc/calendar/
git commit -m "feat(frontend): create CalendarUiCubit and state"
```

---

### Task 2: Create `CalendarDataBloc`

**Files:**
- Create: `frontend/lib/bloc/calendar/calendar_data_event.dart`
- Create: `frontend/lib/bloc/calendar/calendar_data_state.dart`
- Create: `frontend/lib/bloc/calendar/calendar_data_bloc.dart`
- Create: `frontend/test/bloc/calendar/calendar_data_bloc_test.dart`

- [ ] **Step 1: Write the state and events (No tests needed for basic data classes)**

```dart
// frontend/lib/bloc/calendar/calendar_data_event.dart
import 'package:equatable/equatable.dart';

sealed class CalendarDataEvent extends Equatable {
  const CalendarDataEvent();

  @override
  List<Object?> get props => [];
}

class LoadSavedPlaces extends CalendarDataEvent {}

class TogglePlaceFilter extends CalendarDataEvent {
  final String tomtomId;
  const TogglePlaceFilter(this.tomtomId);

  @override
  List<Object?> get props => [tomtomId];
}

class InitDeviceCalendar extends CalendarDataEvent {
  final bool fromButton;
  const InitDeviceCalendar({this.fromButton = false});

  @override
  List<Object?> get props => [fromButton];
}

class ToggleDeviceCalendar extends CalendarDataEvent {
  final String calendarId;
  const ToggleDeviceCalendar(this.calendarId);

  @override
  List<Object?> get props => [calendarId];
}

class ImportIcalFile extends CalendarDataEvent {
  final String icsString;
  const ImportIcalFile(this.icsString);

  @override
  List<Object?> get props => [icsString];
}

class ClearImportedEvents extends CalendarDataEvent {}

class LoadRemoteEvents extends CalendarDataEvent {
  final String url;
  const LoadRemoteEvents(this.url);

  @override
  List<Object?> get props => [url];
}
```

```dart
// frontend/lib/bloc/calendar/calendar_data_state.dart
import 'package:equatable/equatable.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:device_calendar/device_calendar.dart';
import '../../models/saved_place.dart';

enum CalendarDataStatus { initial, loading, loaded, error }

class CalendarDataState extends Equatable {
  final CalendarDataStatus status;
  final List<SavedPlace> savedPlaces;
  final Set<String> checkedPlaceIds;
  final List<Calendar> deviceCalendars;
  final List<CalendarEventData<Object?>> deviceEvents;
  final Set<String> checkedCalendarIds;
  final bool hasCalendarPermission;
  final List<CalendarEventData<Object?>> importedEvents;
  final List<CalendarEventData<Object?>> remoteEvents;
  final String? errorMessage;
  final bool isLoadingRemote;

  const CalendarDataState({
    this.status = CalendarDataStatus.initial,
    this.savedPlaces = const [],
    this.checkedPlaceIds = const {},
    this.deviceCalendars = const [],
    this.deviceEvents = const [],
    this.checkedCalendarIds = const {},
    this.hasCalendarPermission = false,
    this.importedEvents = const [],
    this.remoteEvents = const [],
    this.errorMessage,
    this.isLoadingRemote = false,
  });

  CalendarDataState copyWith({
    CalendarDataStatus? status,
    List<SavedPlace>? savedPlaces,
    Set<String>? checkedPlaceIds,
    List<Calendar>? deviceCalendars,
    List<CalendarEventData<Object?>>? deviceEvents,
    Set<String>? checkedCalendarIds,
    bool? hasCalendarPermission,
    List<CalendarEventData<Object?>>? importedEvents,
    List<CalendarEventData<Object?>>? remoteEvents,
    String? errorMessage,
    bool? isLoadingRemote,
  }) {
    return CalendarDataState(
      status: status ?? this.status,
      savedPlaces: savedPlaces ?? this.savedPlaces,
      checkedPlaceIds: checkedPlaceIds ?? this.checkedPlaceIds,
      deviceCalendars: deviceCalendars ?? this.deviceCalendars,
      deviceEvents: deviceEvents ?? this.deviceEvents,
      checkedCalendarIds: checkedCalendarIds ?? this.checkedCalendarIds,
      hasCalendarPermission: hasCalendarPermission ?? this.hasCalendarPermission,
      importedEvents: importedEvents ?? this.importedEvents,
      remoteEvents: remoteEvents ?? this.remoteEvents,
      errorMessage: errorMessage, // We don't want to persist old errors normally, but we can copy it if needed. Let's just copy it if provided.
      isLoadingRemote: isLoadingRemote ?? this.isLoadingRemote,
    );
  }

  // Helper to clear error message
  CalendarDataState clearError() {
    return CalendarDataState(
      status: status,
      savedPlaces: savedPlaces,
      checkedPlaceIds: checkedPlaceIds,
      deviceCalendars: deviceCalendars,
      deviceEvents: deviceEvents,
      checkedCalendarIds: checkedCalendarIds,
      hasCalendarPermission: hasCalendarPermission,
      importedEvents: importedEvents,
      remoteEvents: remoteEvents,
      errorMessage: null,
      isLoadingRemote: isLoadingRemote,
    );
  }

  @override
  List<Object?> get props => [
        status,
        savedPlaces,
        checkedPlaceIds,
        deviceCalendars,
        deviceEvents,
        checkedCalendarIds,
        hasCalendarPermission,
        importedEvents,
        remoteEvents,
        errorMessage,
        isLoadingRemote,
      ];
}
```

- [ ] **Step 2: Write the failing test for the Bloc**

```dart
// frontend/test/bloc/calendar/calendar_data_bloc_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:is_it_open/bloc/calendar/calendar_data_bloc.dart';
import 'package:is_it_open/bloc/calendar/calendar_data_event.dart';
import 'package:is_it_open/bloc/calendar/calendar_data_state.dart';
import 'package:is_it_open/services/api_service.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
// We need to generate a mock for ApiService
import 'calendar_data_bloc_test.mocks.dart';

@GenerateMocks([ApiService])
void main() {
  group('CalendarDataBloc', () {
    late MockApiService mockApiService;
    late CalendarDataBloc bloc;

    setUp(() {
      mockApiService = MockApiService();
      bloc = CalendarDataBloc(apiService: mockApiService);
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is correct', () {
      expect(bloc.state.status, CalendarDataStatus.initial);
    });

    blocTest<CalendarDataBloc, CalendarDataState>(
      'LoadSavedPlaces emits [loading, loaded] when successful',
      build: () {
        when(mockApiService.getBookmarks()).thenAnswer((_) async => []);
        return bloc;
      },
      act: (bloc) => bloc.add(LoadSavedPlaces()),
      expect: () => [
        const CalendarDataState(status: CalendarDataStatus.loading),
        const CalendarDataState(status: CalendarDataStatus.loaded, savedPlaces: []),
      ],
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'TogglePlaceFilter updates checkedPlaceIds',
      build: () => bloc,
      seed: () => const CalendarDataState(checkedPlaceIds: {'123'}),
      act: (bloc) => bloc.add(const TogglePlaceFilter('123')),
      expect: () => [
        const CalendarDataState(checkedPlaceIds: {}),
      ],
    );
  });
}
```

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs` (to generate mocks)
Run: `cd frontend && flutter test test/bloc/calendar/calendar_data_bloc_test.dart`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```dart
// frontend/lib/bloc/calendar/calendar_data_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart' show Color, Colors;
import 'calendar_data_event.dart';
import 'calendar_data_state.dart';
import '../../services/api_service.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:icalendar_parser/icalendar_parser.dart';
import 'dart:convert' show jsonEncode, jsonDecode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class CalendarDataBloc extends Bloc<CalendarDataEvent, CalendarDataState> {
  final ApiService apiService;
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  CalendarDataBloc({required this.apiService}) : super(const CalendarDataState()) {
    on<LoadSavedPlaces>(_onLoadSavedPlaces);
    on<TogglePlaceFilter>(_onTogglePlaceFilter);
    on<InitDeviceCalendar>(_onInitDeviceCalendar);
    on<ToggleDeviceCalendar>(_onToggleDeviceCalendar);
    on<ImportIcalFile>(_onImportIcalFile);
    on<ClearImportedEvents>(_onClearImportedEvents);
    on<LoadRemoteEvents>(_onLoadRemoteEvents);

    _loadPersistedImportedEvents();
  }

  Future<void> _onLoadSavedPlaces(LoadSavedPlaces event, Emitter<CalendarDataState> emit) async {
    emit(state.clearError().copyWith(status: CalendarDataStatus.loading));
    try {
      final bookmarks = await apiService.getBookmarks();
      emit(state.copyWith(status: CalendarDataStatus.loaded, savedPlaces: bookmarks));
    } catch (e) {
      emit(state.copyWith(status: CalendarDataStatus.error, errorMessage: 'Failed to load places: $e'));
    }
  }

  void _onTogglePlaceFilter(TogglePlaceFilter event, Emitter<CalendarDataState> emit) {
    final updatedIds = Set<String>.from(state.checkedPlaceIds);
    if (updatedIds.contains(event.tomtomId)) {
      updatedIds.remove(event.tomtomId);
    } else {
      updatedIds.add(event.tomtomId);
    }
    emit(state.clearError().copyWith(checkedPlaceIds: updatedIds));
  }

  Future<void> _onInitDeviceCalendar(InitDeviceCalendar event, Emitter<CalendarDataState> emit) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && (permissionsGranted.data == false)) {
        permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
      }

      if (permissionsGranted.isSuccess && permissionsGranted.data == true) {
        emit(state.copyWith(hasCalendarPermission: true));
        final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
        if (calendarsResult.isSuccess && calendarsResult.data != null) {
          emit(state.copyWith(deviceCalendars: calendarsResult.data!));
        }
      } else if (event.fromButton) {
        emit(state.copyWith(errorMessage: 'Calendar permission denied. Please enable in Settings.'));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error initializing device calendar: $e'));
    }
  }

  Future<void> _onToggleDeviceCalendar(ToggleDeviceCalendar event, Emitter<CalendarDataState> emit) async {
    final updatedIds = Set<String>.from(state.checkedCalendarIds);
    if (updatedIds.contains(event.calendarId)) {
      updatedIds.remove(event.calendarId);
    } else {
      updatedIds.add(event.calendarId);
    }
    
    emit(state.clearError().copyWith(checkedCalendarIds: updatedIds));
    await _fetchDeviceEvents(updatedIds, emit);
  }

  Future<void> _fetchDeviceEvents(Set<String> activeIds, Emitter<CalendarDataState> emit) async {
    if (activeIds.isEmpty) {
      emit(state.copyWith(deviceEvents: []));
      return;
    }

    final calendarColorMap = <String, Color>{};
    for (final cal in state.deviceCalendars) {
      if (cal.id != null) {
        calendarColorMap[cal.id!] = cal.color != null
            ? Color(cal.color!).withValues(alpha: 0.7)
            : Colors.blue.withValues(alpha: 0.7);
      }
    }

    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 28));
    final endDate = now.add(const Duration(days: 84));

    List<CalendarEventData<Object?>> allEvents = [];

    for (final calendarId in activeIds) {
      final calColor = calendarColorMap[calendarId] ?? Colors.blue.withValues(alpha: 0.7);

      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(startDate: startDate, endDate: endDate),
      );

      if (eventsResult.isSuccess && eventsResult.data != null) {
        for (final event in eventsResult.data!) {
          if (event.start != null && event.end != null) {
            if (event.allDay == true) {
              allEvents.add(
                CalendarEventData(
                  title: event.title ?? 'No Title',
                  date: event.start!,
                  endDate: event.end!.subtract(const Duration(days: 1)),
                  description: event.description,
                  color: calColor,
                ),
              );
            } else {
              allEvents.add(
                CalendarEventData(
                  title: event.title ?? 'No Title',
                  date: event.start!,
                  startTime: event.start!,
                  endTime: event.end!,
                  description: event.description,
                  color: calColor,
                ),
              );
            }
          }
        }
      }
    }
    emit(state.copyWith(deviceEvents: allEvents));
  }

  bool _isAllDayIcsDateTime(IcsDateTime dt) {
    return !dt.dt.contains('T');
  }

  List<CalendarEventData<Object?>> _parseIcsString(String icsString, Color eventColor) {
    final iCalendar = ICalendar.fromString(icsString);
    final List<CalendarEventData<Object?>> events = [];
    for (final entry in iCalendar.data) {
      if (entry['type'] == 'VEVENT') {
        final title = entry['summary'] ?? 'Event';
        final dtstart = entry['dtstart'] as IcsDateTime?;
        final dtend = entry['dtend'] as IcsDateTime?;
        final description = entry['description'];

        if (dtstart != null) {
          final isAllDay = _isAllDayIcsDateTime(dtstart);
          final start = dtstart.toDateTime();
          final end = dtend?.toDateTime() ?? start?.add(const Duration(hours: 1));

          if (start != null) {
            if (isAllDay) {
              final endDate = end != null ? end.subtract(const Duration(days: 1)) : start;
              events.add(CalendarEventData(
                title: title,
                date: start,
                endDate: endDate,
                description: description,
                color: eventColor,
              ));
            } else {
              events.add(CalendarEventData(
                title: title,
                date: start,
                startTime: start,
                endTime: end ?? start,
                description: description,
                color: eventColor,
              ));
            }
          }
        }
      }
    }
    return events;
  }

  void _onImportIcalFile(ImportIcalFile event, Emitter<CalendarDataState> emit) {
    try {
      final events = _parseIcsString(event.icsString, Colors.teal.withValues(alpha: 0.5));
      emit(state.clearError().copyWith(importedEvents: events));
      _persistImportedEvents(events);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error importing iCal: $e'));
    }
  }

  void _onClearImportedEvents(ClearImportedEvents event, Emitter<CalendarDataState> emit) {
    emit(state.clearError().copyWith(importedEvents: []));
    _persistImportedEvents([]);
  }

  Future<void> _onLoadRemoteEvents(LoadRemoteEvents event, Emitter<CalendarDataState> emit) async {
    if (event.url.isEmpty) return;
    emit(state.clearError().copyWith(isLoadingRemote: true));
    try {
      final icsString = await apiService.getCalendarFromUrl(event.url);
      final events = _parseIcsString(icsString, Colors.deepPurple.withValues(alpha: 0.5));
      emit(state.copyWith(remoteEvents: events, isLoadingRemote: false));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error fetching remote calendar: $e', isLoadingRemote: false));
    }
  }

  Future<void> _loadPersistedImportedEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? eventsJson = prefs.getString('persisted_imported_events');
      if (eventsJson != null) {
        final List<dynamic> decoded = jsonDecode(eventsJson);
        final List<CalendarEventData<Object?>> events = decoded.map((e) {
          return CalendarEventData(
            title: e['title'],
            date: DateTime.parse(e['date']),
            startTime: e['startTime'] != null ? DateTime.parse(e['startTime']) : null,
            endTime: e['endTime'] != null ? DateTime.parse(e['endTime']) : null,
            description: e['description'],
            color: Colors.teal.withValues(alpha: 0.5),
          );
        }).toList();
        add(ImportIcalFile("")); // Hacky way if we rely on event for storing. Better to just update state directly or create a specific LoadPersisted event.
        // Let's just create an event for it or handle it cleanly.
        // Since we are in the constructor, we can't emit. We should probably dispatch a private event.
      }
    } catch (e) {
      debugPrint('Error loading persisted events: $e');
    }
  }
  
  // Note: We'll refine _loadPersistedImportedEvents in the refactoring step or handle it directly in the UI if needed. For now, we'll keep the logic in the bloc.
  Future<void> _persistImportedEvents(List<CalendarEventData> events) async {
     try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> toStore = events.map((e) {
        return {
          'title': e.title,
          'date': e.date.toIso8601String(),
          'startTime': e.startTime?.toIso8601String(),
          'endTime': e.endTime?.toIso8601String(),
          'description': e.description,
        };
      }).toList();
      await prefs.setString('persisted_imported_events', jsonEncode(toStore));
    } catch (e) {
      debugPrint('Error persisting events: $e');
    }
  }
}
```
*(Refactoring note: We'll add a `LoadPersistedImportedEvents` event to cleanly handle the `_loadPersistedImportedEvents` method).*

Update `calendar_data_event.dart`:
```dart
class LoadPersistedImportedEvents extends CalendarDataEvent {}
```
Update `calendar_data_bloc.dart`:
```dart
  CalendarDataBloc({required this.apiService}) : super(const CalendarDataState()) {
    // ...
    on<LoadPersistedImportedEvents>(_onLoadPersistedImportedEvents);
    add(LoadPersistedImportedEvents());
  }

  Future<void> _onLoadPersistedImportedEvents(LoadPersistedImportedEvents event, Emitter<CalendarDataState> emit) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? eventsJson = prefs.getString('persisted_imported_events');
      if (eventsJson != null) {
        final List<dynamic> decoded = jsonDecode(eventsJson);
        final List<CalendarEventData<Object?>> events = decoded.map((e) {
          return CalendarEventData(
            title: e['title'],
            date: DateTime.parse(e['date']),
            startTime: e['startTime'] != null ? DateTime.parse(e['startTime']) : null,
            endTime: e['endTime'] != null ? DateTime.parse(e['endTime']) : null,
            description: e['description'],
            color: Colors.teal.withValues(alpha: 0.5),
          );
        }).toList();
        emit(state.copyWith(importedEvents: events));
      }
    } catch (e) {
      debugPrint('Error loading persisted events: $e');
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && flutter test test/bloc/calendar/calendar_data_bloc_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/bloc/calendar/ frontend/test/bloc/calendar/
git commit -m "feat(frontend): create CalendarDataBloc, events, and state"
```

---

### Task 3: Refactor `CalendarScreen` (Part 1 - Initialization & Structure)

**Files:**
- Modify: `frontend/lib/screens/calendar/calendar_screen.dart`

- [ ] **Step 1: Write the minimal implementation**

Replace the current state management variables with Bloc providers and builders.

```dart
// frontend/lib/screens/calendar/calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:calendar_view/calendar_view.dart';
import '../../bloc/calendar/calendar_ui_cubit.dart';
import '../../bloc/calendar/calendar_ui_state.dart';
import '../../bloc/calendar/calendar_data_bloc.dart';
import '../../bloc/calendar/calendar_data_event.dart';
import '../../bloc/calendar/calendar_data_state.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../services/api_service.dart';
// ... other existing imports (remove device_calendar, icalendar_parser imports if not needed directly here)

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<CalendarUiCubit>(
          create: (context) => CalendarUiCubit(),
        ),
        BlocProvider<CalendarDataBloc>(
          create: (context) {
            final bloc = CalendarDataBloc(apiService: context.read<ApiService>());
            bloc.add(LoadSavedPlaces());
            bloc.add(InitDeviceCalendar());
            
            // Load remote events if authenticated
            final authState = context.read<AuthBloc>().state;
            if (authState is AuthAuthenticated) {
              final url = authState.user.calendarSubscriptionUrl;
              if (url != null && url.isNotEmpty) {
                bloc.add(LoadRemoteEvents(url));
              }
            }
            return bloc;
          },
        ),
      ],
      child: const _CalendarScreenView(),
    );
  }
}

class _CalendarScreenView extends StatelessWidget {
  const _CalendarScreenView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<CalendarDataBloc, CalendarDataState>(
      listenWhen: (previous, current) => current.errorMessage != null && current.errorMessage != previous.errorMessage,
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.errorMessage!)),
          );
        }
      },
      child: const _CalendarScreenContent(), // Move the rest of the UI build here
    );
  }
}

// Rename _CalendarScreenState to _CalendarScreenContent and make it a StatefulWidget again temporarily or convert to StatelessWidget entirely.
// Since we removed all local state, it can be a StatelessWidget.
class _CalendarScreenContent extends StatelessWidget {
  const _CalendarScreenContent({super.key});
  
  // Move all the UI builder methods here (_buildCalendar, _buildPlacesSidebar, etc.)
  // We will pass context to them or access Bloc within them.
  // ... (We will do this iteratively in the next tasks)
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/calendar/calendar_screen.dart
git commit -m "refactor(frontend): wrap CalendarScreen in BlocProviders"
```

---

### Task 4: Refactor `CalendarScreen` (Part 2 - EventController & Data Rendering)

**Files:**
- Modify: `frontend/lib/screens/calendar/calendar_screen.dart`

- [ ] **Step 1: Write the minimal implementation**

Move the logic that builds the `EventController` into a helper method inside `_CalendarScreenContent` that takes the `CalendarDataState` as input.

```dart
  // Inside _CalendarScreenContent

  static const List<Color> _defaultPalette = [
    Colors.blue, Colors.red, Colors.green, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.brown, Colors.indigo, Colors.cyan,
  ];

  Color _colorForPlace(SavedPlace sp, int index) {
    if (sp.color != null && sp.color!.isNotEmpty) {
      try { return Color(int.parse(sp.color!, radix: 16)); } catch (_) {}
    }
    return _defaultPalette[index % _defaultPalette.length];
  }

  String _displayName(SavedPlace sp) {
    if (sp.customName != null && sp.customName!.isNotEmpty) return sp.customName!;
    return sp.place.name;
  }

  EventController<Object?> _buildEventController(CalendarDataState dataState) {
    final controller = EventController<Object?>();
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));

    int colorIndex = 0;
    for (final sp in dataState.savedPlaces) {
      if (!dataState.checkedPlaceIds.contains(sp.place.tomtomId)) {
        colorIndex++;
        continue;
      }

      final color = _colorForPlace(sp, colorIndex).withValues(alpha: 0.7);
      final label = _displayName(sp);

      for (int weekOffset = -4; weekOffset <= 12; weekOffset++) {
        final weekStart = startOfWeek.add(Duration(days: weekOffset * 7));

        for (final hours in sp.place.hours) {
          final baseDate = weekStart.add(Duration(days: hours.dayOfWeek));
          final startTime = DateTime(baseDate.year, baseDate.month, baseDate.day, hours.openTime.hour, hours.openTime.minute);
          var endTime = DateTime(baseDate.year, baseDate.month, baseDate.day, hours.closeTime.hour, hours.closeTime.minute);
          if (endTime.isBefore(startTime)) endTime = endTime.add(const Duration(days: 1));

          controller.add(CalendarEventData(
            title: label,
            date: baseDate,
            startTime: startTime,
            endTime: endTime,
            color: color,
          ));
        }
      }
      colorIndex++;
    }

    controller.addAll(dataState.deviceEvents);
    controller.addAll(dataState.importedEvents);
    controller.addAll(dataState.remoteEvents);

    return controller;
  }
```

Update `_buildCalendar` to use `BlocBuilder<CalendarUiCubit, CalendarUiState>` and `BlocBuilder<CalendarDataBloc, CalendarDataState>`.

```dart
  Widget _buildCalendar(BuildContext context, bool use24HourFormat) {
    return BlocBuilder<CalendarUiCubit, CalendarUiState>(
      builder: (context, uiState) {
        return BlocBuilder<CalendarDataBloc, CalendarDataState>(
          builder: (context, dataState) {
            final controller = _buildEventController(dataState);
            // Re-implement the view building logic using uiState.currentView, uiState.baseDate, and controller
            // Replace setState calls with context.read<CalendarUiCubit>().changeViewType/navigateDate
            // ... (Copy existing logic but use uiState properties)
          }
        );
      }
    );
  }
```

Update sidebars to use `context.read<CalendarDataBloc>().add(...)` instead of `setState`.

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/calendar/calendar_screen.dart
git commit -m "refactor(frontend): implement UI logic with Blocs on CalendarScreen"
```

---

### Task 5: Refactor `CalendarScreen` (Part 3 - Complete Migration & Cleanup)

**Files:**
- Modify: `frontend/lib/screens/calendar/calendar_screen.dart`

- [ ] **Step 1: Write the minimal implementation**

Complete the migration of `_buildPlacesSidebar`, `_buildDeviceCalendarsSidebar`, `_buildRemoteSubscriptionSidebar`, and `_importIcalFile` to dispatch events to `CalendarDataBloc` and read state from `BlocBuilder`.

Example for `_importIcalFile` action in the UI:
```dart
IconButton(
  icon: dataState.status == CalendarDataStatus.loading ? const CircularProgressIndicator() : const Icon(Icons.file_upload),
  onPressed: () async {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['ics'], withData: true);
      if (result != null && result.files.single.bytes != null) {
        final icsString = utf8.decode(result.files.single.bytes!);
        context.read<CalendarDataBloc>().add(ImportIcalFile(icsString));
      }
  },
)
```

Remove all old unused code, variables, and imports. Fix any compilation errors caused by the transition to a `StatelessWidget`.

- [ ] **Step 2: Run test/app to verify it passes**

Run: `cd frontend && flutter test` to ensure we didn't break other things.
Run: `cd frontend && flutter analyze` to catch syntax errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/calendar/calendar_screen.dart
git commit -m "refactor(frontend): finalize calendar screen bloc migration"
```
