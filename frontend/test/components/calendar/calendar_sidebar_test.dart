import 'dart:collection';
import 'dart:convert';

import 'package:device_calendar/device_calendar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_state.dart';
import 'package:frontend/components/calendar/calendar_sidebar.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/ical_parser_service.dart';
import 'package:frontend/utils/graphics_helper.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

Result<T> _ok<T>(T data) => Result<T>()..data = data;

Widget _sidebar({bool collapsed = false}) =>
    BlocBuilder<CalendarDataBloc, CalendarDataState>(
      builder: (_, state) => CalendarSidebarWidget(
        dataState: state,
        colorForPlace: GraphicsHelper.colorForSavedPlace,
        availableIcons: GraphicsHelper.availableIcons,
        isCollapsed: collapsed,
      ),
    );

CalendarDataBloc _bloc(BuildContext context) =>
    context.read<CalendarDataBloc>();

void main() {
  setUpAll(registerFallbacks);

  testWidgets('displayName prefers a non-empty custom name', (tester) async {
    expect(displayName(sampleSavedPlaces[1]), 'Friday burger spot');
    expect(displayName(sampleSavedPlaces[0]), coffeePlace.name);
  });

  group('places', () {
    testWidgets('lists saved places and toggles their filter', (tester) async {
      await tester.pumpApp(Scaffold(body: _sidebar()), size: desktopSize);
      expect(find.text('Friday burger spot'), findsOneWidget);
      expect(find.text(gymPlace.name), findsOneWidget);
      final context = tester.element(find.byType(CalendarSidebarWidget));
      expect(_bloc(context).state.checkedPlaceIds, contains('tt_coffee'));

      await tester.tap(find.text(coffeePlace.name));
      await tester.tap(find.text(gymPlace.name));
      await tester.pump();
      expect(_bloc(context).state.checkedPlaceIds, {'tt_bistro', 'tt_gym'});
    });

    testWidgets('shows loading and empty states', (tester) async {
      await tester.pumpApp(
        Scaffold(body: _sidebar()),
        calendarData: const CalendarDataState(
          status: CalendarDataStatus.loading,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpApp(
        Scaffold(body: _sidebar()),
        calendarData: const CalendarDataState(
          status: CalendarDataStatus.loaded,
        ),
      );
      expect(find.text('No saved places yet'), findsOneWidget);
    });

    testWidgets('refresh reloads places from the API', (tester) async {
      await tester.pumpApp(
        Scaffold(body: _sidebar()),
        calendarData: const CalendarDataState(
          status: CalendarDataStatus.loaded,
        ),
      );
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(find.text('Friday burger spot'), findsOneWidget);
    });
  });

  group('device calendars', () {
    testWidgets('explain they are mobile-only elsewhere', (tester) async {
      await tester.pumpApp(Scaffold(body: _sidebar()));
      expect(
        find.textContaining('Device sync is available on Mobile only'),
        findsOneWidget,
      );
    });

    testWidgets('ask for permission, then list and toggle calendars', (
      tester,
    ) async {
      final plugin = MockDeviceCalendarPlugin();
      when(() => plugin.hasPermissions()).thenAnswer((_) async => _ok(false));
      when(
        () => plugin.requestPermissions(),
      ).thenAnswer((_) async => _ok(true));
      when(() => plugin.retrieveCalendars()).thenAnswer(
        (_) async => _ok(
          UnmodifiableListView([
            Calendar(id: 'work', name: 'Work', color: 0xFF2196F3),
            Calendar(id: 'home'),
          ]),
        ),
      );
      when(
        () => plugin.retrieveEvents(any(), any()),
      ).thenAnswer((_) async => _ok(UnmodifiableListView(<Event>[])));

      await tester.pumpApp(
        Builder(
          builder: (context) => BlocProvider<CalendarDataBloc>(
            create: (_) => CalendarDataBloc(
              apiService: context.read<ApiService>(),
              icalParserService: IcalParserService(),
              deviceCalendarPlugin: plugin,
              supportsDeviceCalendar: true,
            ),
            child: Scaffold(body: _sidebar()),
          ),
        ),
        size: desktopSize,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Grant permission to see your device calendars.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Grant Permission'));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Unnamed Calendar'), findsOneWidget);

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(CalendarSidebarWidget));
      expect(_bloc(context).state.checkedCalendarIds, {'work'});
      verify(() => plugin.retrieveEvents('work', any())).called(1);

      // The sync button re-reads the calendars.
      await tester.tap(find.byIcon(Icons.sync).first);
      await tester.pumpAndSettle();
      verify(() => plugin.retrieveCalendars()).called(2);
    });
  });

  group('remote subscription', () {
    testWidgets('explains how to subscribe without a URL', (tester) async {
      await tester.pumpApp(
        Scaffold(body: _sidebar()),
        authState: AuthAuthenticated(user: minimalUser),
        size: desktopSize,
      );
      expect(
        find.text(
          'No subscription URL set. Use a .ics URL for real-time sync.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('saving a URL updates only that field, then syncs', (
      tester,
    ) async {
      final user = User.fromJson({
        ...demoUser.toJson(),
        'calendar_subscription_url': null,
        'use_current_location': true,
      });
      await tester.pumpApp(
        Scaffold(body: _sidebar()),
        authState: AuthAuthenticated(user: user),
        size: desktopSize,
      );
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(find.text('Calendar Subscription'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'iCal URL'),
        'https://cal.example/me.ics',
      );
      await tester.tap(find.text('Save & Sync'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2)); // the delayed sync
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(CalendarSidebarWidget));
      final saved = (context.read<AuthBloc>().state as AuthAuthenticated).user;
      expect(saved.calendarSubscriptionUrl, 'https://cal.example/me.ics');
      expect(saved.useCurrentLocation, isTrue);
      expect(saved.homeCity, demoUser.homeCity);
      expect(find.text('Syncing with 1 events.'), findsOneWidget);
    });

    testWidgets('cancel leaves the subscription alone', (tester) async {
      await tester.pumpApp(Scaffold(body: _sidebar()), size: desktopSize);
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, demoUser.calendarSubscriptionUrl!),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Calendar Subscription'), findsNothing);
    });

    testWidgets('sync reloads the subscribed calendar', (tester) async {
      await tester.pumpApp(Scaffold(body: _sidebar()), size: desktopSize);
      expect(find.text('Syncing with 0 events.'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.sync));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Syncing with 1 events.'), findsOneWidget);
    });
  });

  group('imported events', () {
    testWidgets('imports a picked .ics file and clears it', (tester) async {
      final picker = FakeFilePicker.install(addTearDown, ics());
      await tester.pumpApp(
        Scaffold(body: _sidebar()),
        calendarData: CalendarDataState(
          status: CalendarDataStatus.loaded,
          savedPlaces: sampleSavedPlaces,
        ),
        size: desktopSize,
      );
      expect(find.textContaining('No events imported'), findsOneWidget);
      await tester.tap(find.byTooltip('Import .ics file'));
      await tester.pumpAndSettle();
      expect(picker.picks, 1);
      expect(find.text('Displaying 1 imported events.'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear Imported'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No events imported'), findsOneWidget);
    });

    testWidgets('a cancelled pick imports nothing', (tester) async {
      FakeFilePicker.install(addTearDown);
      await tester.pumpApp(
        Scaffold(body: _sidebar()),
        calendarData: const CalendarDataState(),
        size: desktopSize,
      );
      await tester.tap(find.byTooltip('Import .ics file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No events imported'), findsOneWidget);
    });
  });

  group('collapsed', () {
    testWidgets('shows an icon per place that toggles its filter', (
      tester,
    ) async {
      FakeFilePicker.install(addTearDown, null);
      await tester.pumpApp(
        Scaffold(body: SizedBox(width: 72, child: _sidebar(collapsed: true))),
      );
      expect(find.byIcon(Icons.local_cafe), findsOneWidget);
      expect(find.byTooltip('Friday burger spot'), findsOneWidget);
      final context = tester.element(find.byType(CalendarSidebarWidget));
      await tester.tap(find.byIcon(Icons.fitness_center));
      await tester.pump();
      expect(_bloc(context).state.checkedPlaceIds, contains('tt_gym'));
      await tester.tap(find.byTooltip('Import .ics file'));
      await tester.pumpAndSettle();
    });

    testWidgets('shows device calendars and imports files', (tester) async {
      FakeFilePicker.install(addTearDown, ics());
      final plugin = MockDeviceCalendarPlugin();
      when(
        () => plugin.retrieveEvents(any(), any()),
      ).thenAnswer((_) async => _ok(UnmodifiableListView(<Event>[])));
      await tester.pumpApp(
        Builder(
          builder: (context) => BlocProvider<CalendarDataBloc>(
            create: (_) => SeededCalendarDataBloc(
              apiService: context.read<ApiService>(),
              icalParserService: IcalParserService(),
              seed: CalendarDataState(
                status: CalendarDataStatus.loaded,
                deviceCalendars: [Calendar(id: 'work', name: 'Work')],
                hasCalendarPermission: true,
              ),
            ),
            child: Scaffold(
              body: SizedBox(width: 72, child: _sidebar(collapsed: true)),
            ),
          ),
        ),
      );
      expect(find.byTooltip('Work'), findsOneWidget);
      await tester.tap(find.byTooltip('Import .ics file'));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(CalendarSidebarWidget));
      expect(_bloc(context).state.importedEvents, hasLength(1));
    });
  });
}

FilePickerResult ics() => FilePickerResult([
  PlatformFile(
    name: 'cal.ics',
    size: 0,
    bytes: utf8.encode(sampleIcs(DateTime(2026, 10, 19))),
  ),
]);
