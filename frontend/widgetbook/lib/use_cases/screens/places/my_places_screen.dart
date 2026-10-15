import 'package:flutter/material.dart';
import 'package:frontend/screens/places/my_places_screen.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../../mocks/sample_data.dart';
import '../../support/embedded.dart';

@widgetbook.UseCase(name: 'Default', type: MyPlacesScreen)
Widget buildMyPlacesScreenUseCase(BuildContext context) {
  final embedded = embeddedKnob(context);
  final todayCount = context.knobs.int.slider(
    label: 'Stops on today\'s route',
    initialValue: 2,
    max: sampleSavedPlaces.length,
  );
  final use24HourFormat = context.knobs.boolean(label: '24-hour clock');
  return MockAppScope(
    use24HourFormat: use24HourFormat,
    todayRouteIds: [
      for (final sp in sampleSavedPlaces.take(todayCount)) sp.place.tomtomId,
    ],
    child: embedIfNeeded(
      embedded: embedded,
      child: MyPlacesScreen(embedded: embedded),
    ),
  );
}

@widgetbook.UseCase(name: 'Empty', type: MyPlacesScreen)
Widget buildMyPlacesScreenEmptyUseCase(BuildContext context) {
  return const MockAppScope(bookmarks: [], child: MyPlacesScreen());
}

@widgetbook.UseCase(name: 'Loading', type: MyPlacesScreen)
Widget buildMyPlacesScreenLoadingUseCase(BuildContext context) {
  // Requests never resolve, so the skeleton stays up.
  return const MockAppScope(
    apiLatency: null,
    child: MyPlacesScreen(),
  );
}

@widgetbook.UseCase(name: 'Error', type: MyPlacesScreen)
Widget buildMyPlacesScreenErrorUseCase(BuildContext context) {
  return const MockAppScope(apiFails: true, child: MyPlacesScreen());
}
