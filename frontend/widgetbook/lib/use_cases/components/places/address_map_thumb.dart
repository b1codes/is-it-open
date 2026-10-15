import 'package:flutter/material.dart';
import 'package:frontend/components/places/address_map_thumb.dart';
import 'package:frontend/models/place.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/sample_data.dart';
import '../../support/stage.dart';

// Map tiles load from OpenStreetMap / CARTO, so this preview needs network.
@widgetbook.UseCase(name: 'Default', type: AddressMapThumb)
Widget buildAddressMapThumbUseCase(BuildContext context) {
  final place = context.knobs.object.dropdown<Place>(
    label: 'Place',
    options: samplePlaces,
    labelBuilder: (p) => p.name,
  );
  final size = context.knobs.double.slider(
    label: 'Size',
    initialValue: 84,
    min: 48,
    max: 240,
  );
  return ComponentStage(
    child: Center(
      child: AddressMapThumb(
        key: ValueKey(place.tomtomId),
        location: place.location,
        size: size,
      ),
    ),
  );
}
