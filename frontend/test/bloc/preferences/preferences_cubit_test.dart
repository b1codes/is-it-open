import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/preferences/preferences_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PreferencesCubit', () {
    test('loads the stored 24-hour setting', () async {
      SharedPreferences.setMockInitialValues({
        PreferencesCubit.timeFormatKey: true,
      });
      final cubit = PreferencesCubit();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.use24HourFormat, isTrue);
      await cubit.close();
    });

    test(
      'reads and writes an injected store instead of the global one',
      () async {
        SharedPreferences.setMockInitialValues({
          PreferencesCubit.timeFormatKey: false,
        });
        final injected = _MapPreferences({
          PreferencesCubit.timeFormatKey: true,
        });
        final cubit = PreferencesCubit(prefs: injected);
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.use24HourFormat, isTrue);

        await cubit.toggle24HourFormat(false);
        expect(injected.getBool(PreferencesCubit.timeFormatKey), isFalse);
        await cubit.toggle24HourFormat(true);
        final global = await SharedPreferences.getInstance();
        expect(global.getBool(PreferencesCubit.timeFormatKey), isFalse);
        await cubit.close();
      },
    );
  });
}

/// Minimal map-backed store covering what PreferencesCubit touches.
class _MapPreferences implements SharedPreferences {
  _MapPreferences(Map<String, Object> initial) : _values = {...initial};

  final Map<String, Object> _values;

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  Future<bool> setBool(String key, bool value) async {
    _values[key] = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
