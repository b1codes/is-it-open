import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/places/place_detail_screen.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/pump_app.dart';

void main() {
  group('PlaceDetailScreen', () {
    // Today's row in the hours table gets a dot and a bold label; on some
    // weekdays that overflowed its fixed-width label column.
    for (var day = 0; day < 7; day++) {
      final date = DateTime(2026, 10, 19 + day, 12); // Mon 19 Oct .. Sun 25 Oct
      testWidgets('lays out the hours table with ${_weekday(date)} as today', (
        tester,
      ) async {
        await withClock(Clock.fixed(date), () async {
          await tester.pumpApp(PlaceDetailScreen(place: coffeePlace));
          await tester.pumpAndSettle();
          expect(find.text('Hours'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.unmount();
        });
      });
    }
  });
}

String _weekday(DateTime d) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
