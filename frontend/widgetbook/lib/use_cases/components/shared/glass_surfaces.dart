import 'package:flutter/material.dart';
import 'package:frontend/components/shared/glass_card.dart';
import 'package:frontend/components/shared/glass_container.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/stage.dart';

Widget _sampleContent(BuildContext context) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Blue Bottle Coffee', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        '450 W 15th St, New York, NY',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ],
  );
}

@widgetbook.UseCase(name: 'Default', type: GlassCard)
Widget buildGlassCardUseCase(BuildContext context) {
  final useThemeDefaults = context.knobs.boolean(
    label: 'Use theme defaults',
    description: 'Blur and opacity fall back to the AppEffects extension.',
    initialValue: true,
  );
  return ComponentStage(
    backdrop: true,
    child: GlassCard(
      blur: useThemeDefaults
          ? null
          : context.knobs.double.slider(
              label: 'Blur',
              initialValue: 20,
              max: 40,
            ),
      opacity: useThemeDefaults
          ? null
          : context.knobs.double.slider(
              label: 'Opacity',
              initialValue: 0.05,
              max: 1,
              precision: 2,
            ),
      borderRadius: BorderRadius.circular(
        context.knobs.double.slider(
          label: 'Border radius',
          initialValue: 12,
          max: 40,
        ),
      ),
      child: _sampleContent(context),
    ),
  );
}

@widgetbook.UseCase(name: 'Default', type: GlassContainer)
Widget buildGlassContainerUseCase(BuildContext context) {
  return ComponentStage(
    backdrop: true,
    child: GlassContainer(
      blur: context.knobs.double.slider(
        label: 'Blur',
        initialValue: 10,
        max: 40,
      ),
      opacity: context.knobs.double.slider(
        label: 'Opacity',
        initialValue: 0.2,
        max: 1,
        precision: 2,
      ),
      color: context.knobs.color(label: 'Tint', initialValue: Colors.white),
      borderRadius: BorderRadius.circular(
        context.knobs.double.slider(
          label: 'Border radius',
          initialValue: 16,
          max: 40,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: _sampleContent(context),
    ),
  );
}
