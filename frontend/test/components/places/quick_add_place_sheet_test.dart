import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/places/quick_add_place_sheet.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/services/api_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

void main() {
  late MockApiService api;
  late List<Place> saved;
  late Object? popped;

  setUpAll(() {
    registerFallbacks();
    registerFallbackValue(
      const Place(
        tomtomId: 'x',
        name: 'x',
        address: 'x',
        location: LatLng(0, 0),
      ),
    );
  });

  setUp(() {
    api = MockApiService();
    saved = [];
    popped = null;
  });

  Future<void> open(WidgetTester tester, {bool withOnSaved = false}) async {
    await tester.pumpApp(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              popped = await showModalBottomSheet<Place>(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    QuickAddPlaceSheet(onSaved: withOnSaved ? saved.add : null),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
      api: api,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String name, String address) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), name);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Address'),
      address,
    );
  }

  testWidgets('asks for a name and an address', (tester) async {
    await open(tester);
    expect(find.text('Add a place'), findsOneWidget);
    await tester.tap(find.text('Save place'));
    await tester.pump();
    expect(find.text('Give the place a name.'), findsOneWidget);
    expect(find.text('Add an address.'), findsOneWidget);
    await fill(tester, '   ', 'Somewhere');
    await tester.tap(find.text('Save place'));
    await tester.pump();
    expect(find.text('Give the place a name.'), findsOneWidget);
    verifyNever(() => api.savePlace(any()));
  });

  testWidgets('saves a custom place, bookmarks it and closes', (tester) async {
    when(
      () => api.savePlace(any()),
    ).thenAnswer((call) async => (call.positionalArguments.single as Place));
    when(() => api.bookmarkPlace(any())).thenAnswer((_) async {});
    await open(tester);
    await fill(tester, '  Trailhead ', ' 1 Forest Rd ');
    await tester.tap(find.text('Save place'));
    await tester.pumpAndSettle();

    final place =
        verify(() => api.savePlace(captureAny())).captured.single as Place;
    expect(place.tomtomId, startsWith('custom_'));
    expect(place.name, 'Trailhead');
    expect(place.address, '1 Forest Rd');
    verify(() => api.bookmarkPlace(place.tomtomId)).called(1);
    expect(popped, place);
    expect(find.byType(QuickAddPlaceSheet), findsNothing);
  });

  testWidgets('with onSaved, hands the place over instead of popping', (
    tester,
  ) async {
    when(
      () => api.savePlace(any()),
    ).thenAnswer((call) async => (call.positionalArguments.single as Place));
    when(() => api.bookmarkPlace(any())).thenAnswer((_) async {});
    await open(tester, withOnSaved: true);
    await fill(tester, 'Trailhead', '1 Forest Rd');
    await tester.tap(find.text('Save place'));
    await tester.pumpAndSettle();
    expect(saved.single.name, 'Trailhead');
    expect(find.byType(QuickAddPlaceSheet), findsOneWidget);
  });

  testWidgets('stays open and explains a failed save', (tester) async {
    when(() => api.savePlace(any())).thenThrow(ApiException('down'));
    await open(tester);
    await fill(tester, 'Trailhead', '1 Forest Rd');
    await tester.tap(find.text('Save place'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save place."), findsOneWidget);
    expect(find.byType(QuickAddPlaceSheet), findsOneWidget);
    expect(find.text('Save place'), findsOneWidget); // spinner is gone
    expect(saved, isEmpty);
  });

  testWidgets('cancel closes without saving', (tester) async {
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddPlaceSheet), findsNothing);
    expect(popped, isNull);
    verifyZeroInteractions(api);
  });
}
