import 'dart:convert';

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
