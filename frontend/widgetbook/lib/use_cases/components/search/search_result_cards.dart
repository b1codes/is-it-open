import 'package:flutter/material.dart';
import 'package:frontend/components/search/search_result_grid_card.dart';
import 'package:frontend/components/search/search_result_list_card.dart';
import 'package:frontend/models/place.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../../mocks/sample_data.dart';
import '../../support/stage.dart';

Place _placeKnob(BuildContext context) {
  return context.knobs.object.dropdown<Place>(
    label: 'Place',
    options: samplePlaces,
    labelBuilder: (p) => p.name,
  );
}

// Tapping a card records a recent search and pushes PlaceDetailScreen, so
// both cards run inside the mock app scope.

@widgetbook.UseCase(name: 'Default', type: SearchResultListCard)
Widget buildSearchResultListCardUseCase(BuildContext context) {
  final place = _placeKnob(context);
  return MockAppScope(
    child: ComponentStage(
      backdrop: true,
      child: SearchResultListCard(place: place),
    ),
  );
}

@widgetbook.UseCase(name: 'Results list', type: SearchResultListCard)
Widget buildSearchResultListCardListUseCase(BuildContext context) {
  return MockAppScope(
    child: ComponentStage(
      backdrop: true,
      child: Column(
        children: [
          for (final place in samplePlaces) SearchResultListCard(place: place),
        ],
      ),
    ),
  );
}

@widgetbook.UseCase(name: 'Default', type: SearchResultGridCard)
Widget buildSearchResultGridCardUseCase(BuildContext context) {
  final place = _placeKnob(context);
  return MockAppScope(
    child: ComponentStage(
      backdrop: true,
      child: Center(
        // The address is Expanded, so the card needs a bounded grid cell.
        child: SizedBox(
          width: 200,
          height: 160,
          child: SearchResultGridCard(place: place),
        ),
      ),
    ),
  );
}

@widgetbook.UseCase(name: 'Results grid', type: SearchResultGridCard)
Widget buildSearchResultGridCardGridUseCase(BuildContext context) {
  return MockAppScope(
    child: Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackdrop()),
          GridView.count(
            padding: const EdgeInsets.all(8),
            crossAxisCount: 2,
            childAspectRatio: 1.2,
            children: [
              for (final place in samplePlaces)
                SearchResultGridCard(place: place),
            ],
          ),
        ],
      ),
    ),
  );
}
