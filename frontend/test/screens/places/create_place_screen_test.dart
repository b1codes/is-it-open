import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/places/create_place_screen.dart';
import 'package:frontend/screens/places/place_detail_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('saving a new place opens its details', (tester) async {
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CreatePlaceScreen())),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add a place'), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Trailhead',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Address'),
      '1 Forest Rd',
    );
    await tester.tap(find.text('Save place'));
    await tester.pumpAndSettle();

    expect(find.byType(CreatePlaceScreen), findsNothing);
    expect(find.byType(PlaceDetailScreen), findsOneWidget);
    expect(find.text('Trailhead'), findsWidgets);
    await tester.unmount();
  });
}
