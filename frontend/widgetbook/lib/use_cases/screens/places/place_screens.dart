import 'package:flutter/material.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/screens/places/create_place_screen.dart';
import 'package:frontend/screens/places/place_detail_screen.dart';
import 'package:frontend/screens/places/plan_visit_screen.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../../mocks/sample_data.dart';
import '../../support/route_harness.dart';

// These screens are always pushed in the app, so each runs on the route
// harness: back buttons behave and pops (remove place, save) are reported.

List<SavedPlace> _bookmarksWithout(Place place) => sampleSavedPlaces
    .where((sp) => sp.place.tomtomId != place.tomtomId)
    .toList();

Widget _placeDetail({
  required Place place,
  required bool saved,
  bool onToday = false,
  bool use24HourFormat = false,
}) {
  return MockAppScope(
    bookmarks: saved ? sampleSavedPlaces : _bookmarksWithout(place),
    todayRouteIds: onToday ? [place.tomtomId] : const [],
    use24HourFormat: use24HourFormat,
    child: RouteHarness(builder: (_) => PlaceDetailScreen(place: place)),
  );
}

@widgetbook.UseCase(name: 'Playground', type: PlaceDetailScreen)
Widget buildPlaceDetailScreenPlaygroundUseCase(BuildContext context) {
  final place = context.knobs.object.dropdown<Place>(
    label: 'Place',
    options: samplePlaces,
    labelBuilder: (p) => p.name,
  );
  return _placeDetail(
    place: place,
    saved: context.knobs.boolean(label: 'Saved', initialValue: true),
    onToday: context.knobs.boolean(label: 'On today\'s route'),
    use24HourFormat: context.knobs.boolean(label: '24-hour clock'),
  );
}

@widgetbook.UseCase(name: 'Saved place', type: PlaceDetailScreen)
Widget buildPlaceDetailScreenSavedUseCase(BuildContext context) {
  return _placeDetail(place: coffeePlace, saved: true);
}

@widgetbook.UseCase(name: 'Not saved yet', type: PlaceDetailScreen)
Widget buildPlaceDetailScreenUnsavedUseCase(BuildContext context) {
  return _placeDetail(place: bistroPlace, saved: false);
}

@widgetbook.UseCase(name: 'On today\'s route', type: PlaceDetailScreen)
Widget buildPlaceDetailScreenOnTodayUseCase(BuildContext context) {
  return _placeDetail(place: gymPlace, saved: true, onToday: true);
}

@widgetbook.UseCase(name: 'Split hours', type: PlaceDetailScreen)
Widget buildPlaceDetailScreenSplitHoursUseCase(BuildContext context) {
  return _placeDetail(place: libraryPlace, saved: true);
}

@widgetbook.UseCase(name: 'Custom place, no hours', type: PlaceDetailScreen)
Widget buildPlaceDetailScreenCustomUseCase(BuildContext context) {
  return _placeDetail(place: hardwarePlace, saved: true);
}

@widgetbook.UseCase(name: 'Default', type: PlanVisitScreen)
Widget buildPlanVisitScreenUseCase(BuildContext context) {
  final saved = context.knobs.object.dropdown<SavedPlace>(
    label: 'Saved place',
    options: sampleSavedPlaces,
    labelBuilder: (sp) => sp.customName ?? sp.place.name,
  );
  final use24HourFormat = context.knobs.boolean(label: '24-hour clock');
  final apiFails = context.knobs.boolean(
    label: 'Update fails',
    description: 'Changing the visit length reverts with a snackbar.',
  );
  return MockAppScope(
    use24HourFormat: use24HourFormat,
    apiFails: apiFails,
    child: RouteHarness(
      builder: (_) => PlanVisitScreen(
        key: ValueKey(saved.id),
        place: saved.place,
        saved: saved,
      ),
    ),
  );
}

@widgetbook.UseCase(name: 'Default', type: CreatePlaceScreen)
Widget buildCreatePlaceScreenUseCase(BuildContext context) {
  return MockAppScope(
    child: RouteHarness(builder: (_) => const CreatePlaceScreen()),
  );
}
