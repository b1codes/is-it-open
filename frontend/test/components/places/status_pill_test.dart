import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/places/status_pill.dart';
import 'package:frontend/utils/place_status.dart';
import 'package:frontend/utils/places_theme.dart';

import '../../helpers/fixtures.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget pill) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: pill)),
    ),
  );

  final expected = {
    PlaceStatusKind.open: 'Open · until 6pm',
    PlaceStatusKind.closingSoon: 'Closes · in 25 min',
    PlaceStatusKind.closed: 'Closed · opens 9am tomorrow',
  };

  for (final MapEntry(key: kind, value: label) in expected.entries) {
    testWidgets('$kind reads "$label" on its status color', (tester) async {
      await pump(tester, StatusPill(status: sampleStatuses[kind]!));
      expect(find.text(label), findsOneWidget);
      final pill = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(StatusPill),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (pill.decoration! as BoxDecoration).color,
        PlacesTheme.light.statusColor(kind),
      );
    });
  }

  testWidgets('drops the separator without supporting text', (tester) async {
    await pump(
      tester,
      const StatusPill(
        status: PlaceStatus(kind: PlaceStatusKind.closed, supporting: ''),
      ),
    );
    expect(find.text('Closed'), findsOneWidget);
  });

  testWidgets('unknown hours is an outlined pill', (tester) async {
    await pump(tester, const StatusPill(status: unknownStatus));
    expect(find.text('Hours unknown'), findsOneWidget);
    final pill = tester.widget<Container>(
      find.descendant(
        of: find.byType(StatusPill),
        matching: find.byType(Container),
      ),
    );
    final decoration = pill.decoration! as BoxDecoration;
    expect(decoration.color, Colors.transparent);
    expect(decoration.border, isNotNull);
  });

  testWidgets('the medium size is larger', (tester) async {
    await pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(status: openStatus, key: Key('small')),
          StatusPill(
            status: openStatus,
            size: StatusPillSize.medium,
            key: Key('medium'),
          ),
        ],
      ),
    );
    final small = tester.getSize(find.byKey(const Key('small')));
    final medium = tester.getSize(find.byKey(const Key('medium')));
    expect(medium.height, greaterThan(small.height));
    expect(medium.width, greaterThan(small.width));
  });

  testWidgets('a long status ellipsizes instead of overflowing', (
    tester,
  ) async {
    await pump(
      tester,
      const SizedBox(
        width: 120,
        child: StatusPill(
          status: PlaceStatus(
            kind: PlaceStatusKind.closed,
            supporting: 'opens 10:30am on a very distant weekday',
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
