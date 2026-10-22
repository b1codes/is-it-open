import 'dart:collection';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/calendar/calendar_data_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_event.dart';
import 'package:frontend/bloc/calendar/calendar_data_state.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/ical_parser_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/fixtures.dart';
import '../../helpers/mocks.dart';

const _ics = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//EN
BEGIN:VEVENT
SUMMARY:Imported
DTSTART:20261020T150000Z
DTEND:20261020T160000Z
END:VEVENT
BEGIN:VEVENT
SUMMARY:Trip
DTSTART;VALUE=DATE:20261023
DTEND;VALUE=DATE:20261026
END:VEVENT
END:VCALENDAR''';

Result<T> _ok<T>(T data) => Result<T>()..data = data;

Result<T> _err<T>() =>
    Result<T>()..errors.add(const ResultError(500, 'native failure'));

void main() {
  late MockApiService api;
  late MockDeviceCalendarPlugin plugin;

  setUpAll(registerFallbacks);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = MockApiService();
    plugin = MockDeviceCalendarPlugin();
  });

  CalendarDataBloc build({bool supportsDeviceCalendar = true}) =>
      CalendarDataBloc(
        apiService: api,
        icalParserService: IcalParserService(),
        deviceCalendarPlugin: plugin,
        supportsDeviceCalendar: supportsDeviceCalendar,
      );

  test('starts empty', () async {
    final bloc = build();
    expect(bloc.state, const CalendarDataState());
    await bloc.close();
  });

  group('LoadSavedPlaces', () {
    blocTest<CalendarDataBloc, CalendarDataState>(
      'emits loading then the bookmarks',
      build: () {
        when(
          () => api.getBookmarks(),
        ).thenAnswer((_) async => sampleSavedPlaces);
        return build();
      },
      act: (bloc) => bloc.add(LoadSavedPlaces()),
      expect: () => [
        const CalendarDataState(status: CalendarDataStatus.loading),
        CalendarDataState(
          status: CalendarDataStatus.loaded,
          savedPlaces: sampleSavedPlaces,
        ),
      ],
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'clears a previous error while loading and reports failures',
      build: () {
        when(() => api.getBookmarks()).thenThrow(ApiException('down'));
        return build();
      },
      seed: () => const CalendarDataState(errorMessage: 'old'),
      act: (bloc) => bloc.add(LoadSavedPlaces()),
      expect: () => [
        const CalendarDataState(status: CalendarDataStatus.loading),
        const CalendarDataState(
          status: CalendarDataStatus.error,
          errorMessage: 'Failed to load places: Exception: down',
        ),
      ],
    );
  });

  blocTest<CalendarDataBloc, CalendarDataState>(
    'TogglePlaceFilter adds then removes a place',
    build: build,
    act: (bloc) => bloc
      ..add(const TogglePlaceFilter('a'))
      ..add(const TogglePlaceFilter('b'))
      ..add(const TogglePlaceFilter('a')),
    expect: () => [
      const CalendarDataState(checkedPlaceIds: {'a'}),
      const CalendarDataState(checkedPlaceIds: {'a', 'b'}),
      const CalendarDataState(checkedPlaceIds: {'b'}),
    ],
  );

  group('ImportIcalFile', () {
    blocTest<CalendarDataBloc, CalendarDataState>(
      'parses, stores and persists the events',
      build: build,
      act: (bloc) => bloc.add(const ImportIcalFile(_ics)),
      verify: (bloc) async {
        expect(bloc.state.importedEvents.map((e) => e.title), [
          'Imported',
          'Trip',
        ]);
        final prefs = await SharedPreferences.getInstance();
        final stored = jsonDecode(
          prefs.getString('persisted_imported_events')!,
        );
        expect(stored, hasLength(2));
      },
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'reports a file that cannot be parsed',
      build: build,
      act: (bloc) => bloc.add(const ImportIcalFile('not a calendar')),
      expect: () => [
        isA<CalendarDataState>().having(
          (s) => s.errorMessage,
          'errorMessage',
          startsWith('Error importing iCal:'),
        ),
      ],
    );

    test(
      'imported events survive a restart, multi-day ones included',
      () async {
        final first = build()..add(const ImportIcalFile(_ics));
        await Future<void>.delayed(Duration.zero);
        await first.close();

        final second = build();
        await Future<void>.delayed(Duration.zero);
        final restored = second.state.importedEvents;
        expect(restored.map((e) => e.title), ['Imported', 'Trip']);
        final trip = restored.last;
        expect(trip.date, DateTime(2026, 10, 23));
        expect(trip.endDate, DateTime(2026, 10, 25));
        expect(trip.isFullDayEvent, isTrue);
        final imported = restored.first;
        expect(imported.startTime!.toUtc(), DateTime.utc(2026, 10, 20, 15));
        expect(imported.endTime!.toUtc(), DateTime.utc(2026, 10, 20, 16));
        await second.close();
      },
    );

    test('ignores corrupt persisted events', () async {
      SharedPreferences.setMockInitialValues({
        'persisted_imported_events': '{broken',
      });
      final bloc = build();
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.importedEvents, isEmpty);
      await bloc.close();
    });
  });

  blocTest<CalendarDataBloc, CalendarDataState>(
    'ClearImportedEvents empties and persists the list',
    build: build,
    seed: () => CalendarDataState(importedEvents: currentWeekEvents),
    act: (bloc) => bloc.add(ClearImportedEvents()),
    expect: () => [const CalendarDataState()],
    verify: (_) async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('persisted_imported_events'), '[]');
    },
  );

  blocTest<CalendarDataBloc, CalendarDataState>(
    'ClearCalendarData resets everything on sign-out',
    build: build,
    seed: () => CalendarDataState(
      status: CalendarDataStatus.loaded,
      savedPlaces: sampleSavedPlaces,
      checkedPlaceIds: const {'tt_coffee'},
      importedEvents: currentWeekEvents,
    ),
    act: (bloc) => bloc.add(ClearCalendarData()),
    expect: () => [const CalendarDataState()],
  );

  group('LoadRemoteEvents', () {
    blocTest<CalendarDataBloc, CalendarDataState>(
      'ignores an empty URL',
      build: build,
      act: (bloc) => bloc.add(const LoadRemoteEvents('')),
      expect: () => <CalendarDataState>[],
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'fetches through the proxy and parses the events',
      build: () {
        when(
          () => api.getCalendarFromUrl('https://cal.example/a.ics'),
        ).thenAnswer((_) async => _ics);
        return build();
      },
      act: (bloc) =>
          bloc.add(const LoadRemoteEvents('https://cal.example/a.ics')),
      expect: () => [
        const CalendarDataState(isLoadingRemote: true),
        isA<CalendarDataState>()
            .having((s) => s.isLoadingRemote, 'isLoadingRemote', isFalse)
            .having((s) => s.remoteEvents, 'remoteEvents', hasLength(2)),
      ],
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'reports a fetch failure',
      build: () {
        when(
          () => api.getCalendarFromUrl(any()),
        ).thenThrow(ApiException('Failed to fetch remote calendar: 502'));
        return build();
      },
      act: (bloc) => bloc.add(const LoadRemoteEvents('https://x')),
      expect: () => [
        const CalendarDataState(isLoadingRemote: true),
        const CalendarDataState(
          errorMessage:
              'Error fetching remote calendar: '
              'Exception: Failed to fetch remote calendar: 502',
        ),
      ],
    );
  });

  group('InitDeviceCalendar', () {
    final work = Calendar(id: 'work', name: 'Work', color: 0xFF2196F3);
    final home = Calendar(id: 'home', name: 'Home');

    blocTest<CalendarDataBloc, CalendarDataState>(
      'does nothing where device calendars are unsupported',
      build: () => build(supportsDeviceCalendar: false),
      act: (bloc) => bloc.add(const InitDeviceCalendar(fromButton: true)),
      expect: () => <CalendarDataState>[],
      verify: (_) => verifyZeroInteractions(plugin),
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'loads calendars when permission is already granted',
      build: () {
        when(() => plugin.hasPermissions()).thenAnswer((_) async => _ok(true));
        when(
          () => plugin.retrieveCalendars(),
        ).thenAnswer((_) async => _ok(UnmodifiableListView([work, home])));
        return build();
      },
      act: (bloc) => bloc.add(const InitDeviceCalendar()),
      expect: () => [
        const CalendarDataState(hasCalendarPermission: true),
        CalendarDataState(
          hasCalendarPermission: true,
          deviceCalendars: [work, home],
        ),
      ],
      verify: (_) => verifyNever(() => plugin.requestPermissions()),
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'asks for permission when it has not been granted',
      build: () {
        when(() => plugin.hasPermissions()).thenAnswer((_) async => _ok(false));
        when(
          () => plugin.requestPermissions(),
        ).thenAnswer((_) async => _ok(true));
        when(() => plugin.retrieveCalendars()).thenAnswer((_) async => _err());
        return build();
      },
      act: (bloc) => bloc.add(const InitDeviceCalendar()),
      expect: () => [const CalendarDataState(hasCalendarPermission: true)],
      verify: (_) => verify(() => plugin.requestPermissions()).called(1),
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'stays quiet about a denial at startup',
      build: () {
        when(() => plugin.hasPermissions()).thenAnswer((_) async => _ok(false));
        when(
          () => plugin.requestPermissions(),
        ).thenAnswer((_) async => _ok(false));
        return build();
      },
      act: (bloc) => bloc.add(const InitDeviceCalendar()),
      expect: () => <CalendarDataState>[],
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'explains a denial when the user tapped the button',
      build: () {
        when(() => plugin.hasPermissions()).thenAnswer((_) async => _ok(false));
        when(
          () => plugin.requestPermissions(),
        ).thenAnswer((_) async => _ok(false));
        return build();
      },
      act: (bloc) => bloc.add(const InitDeviceCalendar(fromButton: true)),
      expect: () => [
        const CalendarDataState(
          errorMessage:
              'Calendar permission denied. Please enable in Settings.',
        ),
      ],
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'reports a plugin exception',
      build: () {
        when(() => plugin.hasPermissions()).thenThrow(Exception('boom'));
        return build();
      },
      act: (bloc) => bloc.add(const InitDeviceCalendar()),
      expect: () => [
        const CalendarDataState(
          errorMessage: 'Error initializing device calendar: Exception: boom',
        ),
      ],
    );
  });

  group('ToggleDeviceCalendar', () {
    final work = Calendar(id: 'work', name: 'Work', color: 0xFF2196F3);
    final ny = tz.getLocation('America/New_York');

    Event event(
      String title,
      tz.TZDateTime start,
      tz.TZDateTime end, {
      bool allDay = false,
    }) => Event('work', title: title, start: start, end: end, allDay: allDay);

    blocTest<CalendarDataBloc, CalendarDataState>(
      'loads the checked calendar\'s events in its color',
      build: () {
        when(() => plugin.retrieveEvents('work', any())).thenAnswer(
          (_) async => _ok(
            UnmodifiableListView([
              event(
                'Standup',
                tz.TZDateTime(ny, 2026, 10, 20, 9),
                tz.TZDateTime(ny, 2026, 10, 20, 9, 15),
              ),
              event(
                'Offsite',
                tz.TZDateTime(ny, 2026, 10, 22),
                tz.TZDateTime(ny, 2026, 10, 24),
                allDay: true,
              ),
              event(
                'Late shift',
                tz.TZDateTime(ny, 2026, 10, 20, 22),
                tz.TZDateTime(ny, 2026, 10, 21, 2),
              ),
              Event('work', title: 'No end', start: tz.TZDateTime(ny, 2026)),
            ]),
          ),
        );
        return build();
      },
      seed: () => CalendarDataState(deviceCalendars: [work]),
      act: (bloc) => bloc.add(const ToggleDeviceCalendar('work')),
      skip: 1, // the checked id lands before the fetch
      expect: () => [
        isA<CalendarDataState>().having(
          (s) => s.deviceEvents,
          'deviceEvents',
          hasLength(3),
        ),
      ],
      verify: (bloc) {
        expect(bloc.state.checkedCalendarIds, {'work'});
        final [standup, offsite, lateShift] = bloc.state.deviceEvents;
        expect(standup.title, 'Standup');
        expect(standup.startTime, isNotNull);
        expect(standup.color, const Color(0xFF2196F3).withValues(alpha: 0.7));
        expect(offsite.isFullDayEvent, isTrue);
        expect(offsite.endDate, DateTime(2026, 10, 23));
        // Shown on both days it covers.
        expect(lateShift.date, DateTime(2026, 10, 20));
        expect(lateShift.endDate, DateTime(2026, 10, 21));
      },
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'unchecking the last calendar clears its events',
      build: build,
      seed: () => CalendarDataState(
        deviceCalendars: [work],
        checkedCalendarIds: const {'work'},
        deviceEvents: currentWeekEvents,
      ),
      act: (bloc) => bloc.add(const ToggleDeviceCalendar('work')),
      verify: (bloc) {
        expect(bloc.state.checkedCalendarIds, isEmpty);
        expect(bloc.state.deviceEvents, isEmpty);
        verifyNever(() => plugin.retrieveEvents(any(), any()));
      },
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'skips a calendar whose events fail to load',
      build: () {
        when(
          () => plugin.retrieveEvents(any(), any()),
        ).thenAnswer((_) async => _err());
        return build();
      },
      act: (bloc) => bloc.add(const ToggleDeviceCalendar('missing')),
      verify: (bloc) {
        expect(bloc.state.checkedCalendarIds, {'missing'});
        expect(bloc.state.deviceEvents, isEmpty);
      },
    );
  });

  test('state copyWith keeps fields and clearError drops only the error', () {
    final state = CalendarDataState(
      status: CalendarDataStatus.loaded,
      savedPlaces: sampleSavedPlaces,
      errorMessage: 'x',
      isLoadingRemote: true,
    );
    final cleared = state.clearError();
    expect(cleared.errorMessage, isNull);
    expect(cleared.copyWith(), cleared);
    expect(cleared.savedPlaces, sampleSavedPlaces);
    expect(cleared.isLoadingRemote, isTrue);
    // copyWith without errorMessage drops it, so stale errors don't linger.
    expect(
      state.copyWith(status: CalendarDataStatus.error).errorMessage,
      isNull,
    );
  });

  test('events compare by value', () {
    expect(const TogglePlaceFilter('a'), const TogglePlaceFilter('a'));
    expect(const ToggleDeviceCalendar('a').props, ['a']);
    expect(const ImportIcalFile('x').props, ['x']);
    expect(const LoadRemoteEvents('u').props, ['u']);
    expect(const InitDeviceCalendar(fromButton: true).props, [true]);
    expect(LoadSavedPlaces().props, isEmpty);
  });
}
