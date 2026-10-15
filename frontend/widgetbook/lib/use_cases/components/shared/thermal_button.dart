import 'package:flutter/material.dart';
import 'package:frontend/components/shared/thermal_button.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/stage.dart';

@widgetbook.UseCase(name: 'Default', type: ThermalButton)
Widget buildThermalButtonUseCase(BuildContext context) {
  final enabled = context.knobs.boolean(label: 'Enabled', initialValue: true);
  final loading = context.knobs.boolean(label: 'Loading');
  final label = context.knobs.string(label: 'Label', initialValue: 'Sign in');
  return ComponentStage(
    child: Center(
      child: Builder(
        builder: (context) => ThermalButton(
          isLoading: loading,
          onPressed: enabled ? () => logAction(context, 'Pressed') : null,
          child: Text(label),
        ),
      ),
    ),
  );
}

@widgetbook.UseCase(name: 'Loading', type: ThermalButton)
Widget buildThermalButtonLoadingUseCase(BuildContext context) {
  return ComponentStage(
    child: Center(
      child: ThermalButton(
        isLoading: true,
        onPressed: () {},
        child: const Text('Sign in'),
      ),
    ),
  );
}

@widgetbook.UseCase(name: 'Disabled', type: ThermalButton)
Widget buildThermalButtonDisabledUseCase(BuildContext context) {
  return const ComponentStage(
    child: Center(
      child: ThermalButton(onPressed: null, child: Text('Sign in')),
    ),
  );
}
