import 'package:flutter/material.dart';
import 'package:frontend/components/core/refractive_glass.dart';
import 'package:frontend/utils/places_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/stage.dart';

@widgetbook.UseCase(name: 'Default', type: RefractiveGlass)
Widget buildRefractiveGlassUseCase(BuildContext context) {
  return ComponentStage(
    backdrop: true,
    child: RefractiveGlass(
      borderRadius: context.knobs.double.slider(
        label: 'Border radius',
        initialValue: PlacesRadius.lg,
        max: 40,
      ),
      opacity: context.knobs.double.slider(
        label: 'Opacity',
        initialValue: 0.05,
        max: 0.5,
        precision: 2,
      ),
      blur: context.knobs.double.slider(
        label: 'Blur',
        initialValue: 20,
        max: 40,
      ),
      borderWidth: context.knobs.double.slider(
        label: 'Border width',
        initialValue: 0.5,
        max: 4,
      ),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Floating UI sits on refractive glass.',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    ),
  );
}
