import 'package:calendar_view/calendar_view.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/calendar/calendar_ui_cubit.dart';
import 'package:frontend/bloc/calendar/calendar_ui_state.dart';
import 'package:frontend/components/calendar/calendar_event_tile.dart';
import 'package:frontend/components/calendar/calendar_view_stack.dart';
import 'package:frontend/components/calendar/event_details_popup.dart';
import 'package:frontend/utils/app_theme.dart';

import '../../helpers/pump_app.dart';

// Wednesday 21 Oct 2026, mid-morning.
final _now = DateTime(2026, 10, 21, 10, 30);

void main() {
  late CalendarUiCubit cubit;
  late EventController<Object?> controller;

  setUp(() {
    controller = EventController<Object?>()
      ..addAll([
        CalendarEventData(
          title: 'Standup',
          date: DateTime(2026, 10, 21),
          startTime: DateTime(2026, 10, 21, 9),
          endTime: DateTime(2026, 10, 21, 9, 30),
          color: Colors.teal,
        ),
        CalendarEventData(
          title: 'Holiday',
          date: DateTime(2026, 10, 22),
          color: Colors.orange,
        ),
      ]);
  });

  Future<void> pump(
    WidgetTester tester,
    CalendarViewType view, {
    DateTime? base,
    bool use24 = false,
    Size size = desktopSize,
    double textScale = 1,
  }) async {
    tester.setViewport(size);
    cubit = CalendarUiCubit(initialDate: base ?? _now)..changeViewType(view);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      CalendarControllerProvider<Object?>(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: BlocBuilder<CalendarUiCubit, CalendarUiState>(
                builder: (_, state) => CalendarViewStackWidget(
                  uiState: state,
                  controller: controller,
                  checkedPlacesCount: 0,
                  textColor: Colors.black,
                  textSmallColor: Colors.grey,
                  use24HourFormat: use24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the week view shows Monday to Sunday with today marked', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester, CalendarViewType.week);
      expect(find.byType(WeekView<Object?>), findsOneWidget);
      expect(find.text('Oct 19 – 25, 2026'), findsOneWidget);
      for (final day in ['MON', 'WED', 'SUN']) {
        expect(find.text(day), findsOneWidget);
      }
      // Today is on screen, so no "Today" shortcut.
      expect(find.widgetWithText(TextButton, 'Today'), findsNothing);
      expect(find.text('Standup'), findsOneWidget);
    });
  });

  // The E2E run on an Android emulator found the day headers overflowing.
  testWidgets('the week day headers fit a narrow phone with large text', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(
        tester,
        CalendarViewType.week,
        size: const Size(320, 640),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('WED'), findsOneWidget);
    });
  });

  testWidgets('arrows move a week, three days or one day', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      for (final (view, days) in [
        (CalendarViewType.week, 7),
        (CalendarViewType.threeDay, 3),
        (CalendarViewType.singleDay, 1),
      ]) {
        await pump(tester, view);
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();
        expect(cubit.state.baseDate, _now.add(Duration(days: days)));
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byIcon(Icons.chevron_left));
          await tester.pumpAndSettle();
        }
        expect(cubit.state.baseDate, _now.subtract(Duration(days: days)));
      }
    });
  });

  testWidgets('"Today" appears only when today is off screen', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      // Today is the third of three days shown.
      await pump(
        tester,
        CalendarViewType.threeDay,
        base: DateTime(2026, 10, 19, 18),
      );
      expect(find.widgetWithText(TextButton, 'Today'), findsNothing);

      // Later in the same week, from a base date later in the day than now.
      await pump(
        tester,
        CalendarViewType.week,
        base: DateTime(2026, 10, 24, 23),
      );
      expect(find.widgetWithText(TextButton, 'Today'), findsNothing);

      await pump(tester, CalendarViewType.week, base: DateTime(2026, 11, 3));
      await tester.tap(find.widgetWithText(TextButton, 'Today'));
      await tester.pumpAndSettle();
      expect(DateUtils.isSameDay(cubit.state.baseDate, _now), isTrue);
    });
  });

  testWidgets('tapping an event opens its details', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester, CalendarViewType.singleDay);
      expect(find.byType(DayView<Object?>), findsOneWidget);
      expect(find.text('Wednesday, Oct 21, 2026'), findsOneWidget);
      await tester.tap(find.text('Standup'));
      await tester.pumpAndSettle();
      expect(find.byType(EventDetailsPopup), findsOneWidget);
    });
  });

  testWidgets('all-day events open in a sheet from the day header', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(
        tester,
        CalendarViewType.singleDay,
        base: DateTime(2026, 10, 22),
      );
      expect(find.text('1 All-Day Event(s)'), findsOneWidget);
      await tester.tap(find.text('1 All-Day Event(s)'));
      await tester.pumpAndSettle();
      expect(find.text('All-Day Events for 10/22'), findsOneWidget);
      expect(find.text('Holiday'), findsOneWidget);

      Navigator.of(tester.element(find.text('Holiday'))).pop();
      await pump(tester, CalendarViewType.week);
      await tester.tap(find.text('THU'));
      await tester.pumpAndSettle();
      expect(find.text('All-Day Events for 10/22'), findsOneWidget);
    });
  });

  testWidgets('time labels follow the 24-hour setting', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester, CalendarViewType.singleDay, use24: true);
      expect(find.text('10:00'), findsWidgets);
      await pump(tester, CalendarViewType.singleDay);
      expect(find.text('10 AM'), findsWidgets);
    });
  });

  testWidgets('event tiles render through CalendarEventTileWidget', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester, CalendarViewType.week);
      expect(find.byType(CalendarEventTileWidget), findsWidgets);
    });
  });
}
