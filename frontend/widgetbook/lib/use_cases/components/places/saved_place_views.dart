import 'package:flutter/material.dart';
import 'package:frontend/components/places/saved_place_row.dart';
import 'package:frontend/components/places/saved_place_tile.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/utils/places_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/sample_data.dart';
import '../../support/stage.dart';

SavedPlace _placeKnob(BuildContext context) {
  return context.knobs.object.dropdown<SavedPlace>(
    label: 'Saved place',
    options: sampleSavedPlaces,
    labelBuilder: (sp) => sp.customName ?? sp.place.name,
  );
}

PlaceStatusKind _statusKnob(BuildContext context) {
  return context.knobs.object.segmented<PlaceStatusKind>(
    label: 'Status',
    options: PlaceStatusKind.values,
    labelBuilder: (kind) => kind.name,
  );
}

@widgetbook.UseCase(name: 'Default', type: SavedPlaceRow)
Widget buildSavedPlaceRowUseCase(BuildContext context) {
  final savedPlace = _placeKnob(context);
  final status = sampleStatuses[_statusKnob(context)]!;
  final isOnToday = context.knobs.boolean(label: 'On today');
  final showDivider = context.knobs.boolean(
    label: 'Show divider',
    initialValue: true,
  );
  return ComponentStage(
    padding: EdgeInsets.zero,
    child: Builder(
      builder: (context) => SavedPlaceRow(
        savedPlace: savedPlace,
        status: status,
        isOnToday: isOnToday,
        showDivider: showDivider,
        onTap: () => logAction(context, 'onTap'),
        onLongPress: () => logAction(context, 'onLongPress'),
        onToggleToday: () => logAction(context, 'onToggleToday'),
      ),
    ),
  );
}

@widgetbook.UseCase(name: 'List', type: SavedPlaceRow)
Widget buildSavedPlaceRowListUseCase(BuildContext context) {
  final statuses = sampleStatuses.values.toList();
  return ComponentStage(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = 0; i < sampleSavedPlaces.length; i++)
          SavedPlaceRow(
            savedPlace: sampleSavedPlaces[i],
            status: statuses[i % statuses.length],
            isOnToday: i.isEven,
            showDivider: i < sampleSavedPlaces.length - 1,
            onTap: () {},
            onLongPress: () {},
            onToggleToday: () {},
          ),
      ],
    ),
  );
}

@widgetbook.UseCase(name: 'Default', type: SavedPlaceTile)
Widget buildSavedPlaceTileUseCase(BuildContext context) {
  final savedPlace = _placeKnob(context);
  final status = sampleStatuses[_statusKnob(context)]!;
  final isOnToday = context.knobs.boolean(label: 'On today');
  // The tile uses a Spacer, so it needs the bounded height a grid cell gives.
  final width = context.knobs.double.slider(
    label: 'Cell width',
    initialValue: 200,
    min: 140,
    max: 320,
  );
  final height = context.knobs.double.slider(
    label: 'Cell height',
    initialValue: 200,
    min: 160,
    max: 320,
  );
  return ComponentStage(
    child: Center(
      child: SizedBox(
        width: width,
        height: height,
        child: Builder(
          builder: (context) => SavedPlaceTile(
            savedPlace: savedPlace,
            status: status,
            isOnToday: isOnToday,
            onTap: () => logAction(context, 'onTap'),
            onLongPress: () => logAction(context, 'onLongPress'),
            onToggleToday: () => logAction(context, 'onToggleToday'),
          ),
        ),
      ),
    ),
  );
}

@widgetbook.UseCase(name: 'Grid', type: SavedPlaceTile)
Widget buildSavedPlaceTileGridUseCase(BuildContext context) {
  final statuses = sampleStatuses.values.toList();
  return Scaffold(
    body: GridView.builder(
      padding: const EdgeInsets.all(PlacesSpacing.lg),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 200,
        crossAxisSpacing: PlacesSpacing.md,
        mainAxisSpacing: PlacesSpacing.md,
      ),
      itemCount: sampleSavedPlaces.length,
      itemBuilder: (context, i) => SavedPlaceTile(
        savedPlace: sampleSavedPlaces[i],
        status: statuses[i % statuses.length],
        isOnToday: i.isEven,
        onTap: () {},
        onLongPress: () {},
        onToggleToday: () {},
      ),
    ),
  );
}
