import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/today/today_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TodayRouteCubit', () {
    test('persistedValues uses the stored key names and yyyy-MM-dd', () {
      expect(
        TodayRouteCubit.persistedValues(['a', 'b'], DateTime(2026, 3, 7)),
        {
          'today_route_ids': jsonEncode(['a', 'b']),
          'today_route_date': '2026-03-07',
        },
      );
    });

    test('hydrates a route seeded via persistedValues for today', () async {
      SharedPreferences.setMockInitialValues(
        TodayRouteCubit.persistedValues(['x', 'y'], DateTime.now()),
      );
      final cubit = TodayRouteCubit();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.tomtomIds, ['x', 'y']);
      expect(cubit.state.autoClearedFrom, isNull);
      await cubit.close();
    });

    test('resets a route persisted on an earlier day', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      SharedPreferences.setMockInitialValues(
        TodayRouteCubit.persistedValues(['x'], yesterday),
      );
      final cubit = TodayRouteCubit();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.tomtomIds, isEmpty);
      expect(cubit.state.autoClearedFrom, isNotNull);
      await cubit.close();
    });

    test(
      'reads and writes an injected store instead of the global one',
      () async {
        SharedPreferences.setMockInitialValues(
          TodayRouteCubit.persistedValues(['global'], DateTime.now()),
        );
        final injected = _MapPreferences(
          TodayRouteCubit.persistedValues(['injected'], DateTime.now()),
        );
        final cubit = TodayRouteCubit(prefs: injected);
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.tomtomIds, ['injected']);

        await cubit.add('added');
        expect(
          injected.getString('today_route_ids'),
          jsonEncode(['injected', 'added']),
        );
        final global = await SharedPreferences.getInstance();
        expect(global.getString('today_route_ids'), jsonEncode(['global']));
        await cubit.close();
      },
    );

    group('editing', () {
      late SharedPreferences prefs;
      late TodayRouteCubit cubit;
      final monday = DateTime(2026, 10, 19, 9);

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
      });

      Future<void> start(List<String> ids) async {
        await prefs.clear();
        for (final e in TodayRouteCubit.persistedValues(ids, monday).entries) {
          await prefs.setString(e.key, e.value);
        }
        cubit = TodayRouteCubit(prefs: prefs);
        await Future<void>.delayed(Duration.zero);
      }

      List<String> stored() =>
          (jsonDecode(prefs.getString('today_route_ids')!) as List)
              .cast<String>();

      test('add appends once and persists', () async {
        await withClock(Clock.fixed(monday), () async {
          await start(['a']);
          await cubit.add('b');
          await cubit.add('b');
          expect(cubit.state.tomtomIds, ['a', 'b']);
          expect(cubit.state.contains('b'), isTrue);
          expect(stored(), ['a', 'b']);
          expect(prefs.getString('today_route_date'), '2026-10-19');
        });
      });

      test('remove drops the place and ignores unknown ids', () async {
        await withClock(Clock.fixed(monday), () async {
          await start(['a', 'b']);
          await cubit.remove('c');
          await cubit.remove('a');
          expect(cubit.state.tomtomIds, ['b']);
          expect(stored(), ['b']);
          await cubit.remove('b');
          expect(cubit.state.isEmpty, isTrue);
        });
      });

      test('reorder follows ReorderableListView indices', () async {
        await withClock(Clock.fixed(monday), () async {
          await start(['a', 'b', 'c']);
          await cubit.reorder(0, 3); // drag the first item to the end
          expect(cubit.state.tomtomIds, ['b', 'c', 'a']);
          await cubit.reorder(2, 0); // and back to the top
          expect(cubit.state.tomtomIds, ['a', 'b', 'c']);
          await cubit.reorder(1, 1);
          expect(stored(), ['a', 'b', 'c']);
        });
      });

      test('refresh clears a route left open past midnight', () async {
        await withClock(Clock.fixed(monday), () => start(['a']));
        final tuesday = DateTime(2026, 10, 20, 0, 5);
        await withClock(Clock.fixed(tuesday), () async {
          await cubit.refresh();
          expect(cubit.state.tomtomIds, isEmpty);
          expect(cubit.state.autoClearedFrom, DateTime(2026, 10, 19));
          expect(prefs.getString('today_route_date'), '2026-10-20');

          // The next edit dismisses the reset note.
          await cubit.add('b');
          expect(cubit.state.autoClearedFrom, isNull);
        });
      });

      test('refresh on the same day keeps the route', () async {
        await withClock(Clock.fixed(monday), () async {
          await start(['a']);
          await cubit.refresh();
          expect(cubit.state.tomtomIds, ['a']);
          expect(cubit.state.autoClearedFrom, isNull);
        });
      });

      test('dismissResetNote clears only the note', () async {
        await withClock(Clock.fixed(monday), () async {
          await start([]);
          await cubit.dismissResetNote(); // nothing to dismiss
          expect(cubit.state.autoClearedFrom, isNull);
        });
        await withClock(
          Clock.fixed(monday.add(const Duration(days: 1))),
          () async {
            await cubit.refresh();
            expect(cubit.state.autoClearedFrom, isNotNull);
            await cubit.dismissResetNote();
            expect(cubit.state.autoClearedFrom, isNull);
            expect(cubit.state.tomtomIds, isEmpty);
          },
        );
      });

      test('a route from yesterday resets with a note on launch', () async {
        await withClock(Clock.fixed(DateTime(2026, 10, 20, 8)), () async {
          await start(['a']);
          expect(cubit.state.tomtomIds, isEmpty);
          expect(cubit.state.autoClearedFrom, DateTime(2026, 10, 19));
          expect(stored(), isEmpty);
        });
      });

      test('starts empty with nothing stored', () async {
        await withClock(Clock.fixed(monday), () async {
          final empty = TodayRouteCubit(prefs: prefs);
          await Future<void>.delayed(Duration.zero);
          expect(empty.state.tomtomIds, isEmpty);
          expect(empty.state.touchedOn, DateTime(2026, 10, 19));
        });
      });
    });

    test('copyWith keeps or clears the reset note', () {
      final state = TodayRouteState(
        tomtomIds: const ['a'],
        touchedOn: DateTime(2026),
        autoClearedFrom: DateTime(2025),
      );
      expect(state.copyWith().autoClearedFrom, DateTime(2025));
      expect(state.copyWith(clearAutoCleared: true).autoClearedFrom, isNull);
      expect(state.copyWith(tomtomIds: ['b']).tomtomIds, ['b']);
    });
  });
}

/// Minimal map-backed store covering what TodayRouteCubit touches.
class _MapPreferences implements SharedPreferences {
  _MapPreferences(Map<String, Object> initial) : _values = {...initial};

  final Map<String, Object> _values;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    _values[key] = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
