import 'package:flutter/material.dart';
import 'package:frontend/components/places/status_pill.dart';
import 'package:frontend/utils/place_status.dart';
import 'package:frontend/utils/places_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/sample_data.dart';
import '../../support/stage.dart';

@widgetbook.UseCase(name: 'Playground', type: StatusPill)
Widget buildStatusPillPlaygroundUseCase(BuildContext context) {
  final kind = context.knobs.object.segmented<PlaceStatusKind>(
    label: 'Kind',
    options: PlaceStatusKind.values,
    labelBuilder: (kind) => kind.name,
  );
  final supporting = context.knobs.string(
    label: 'Supporting text',
    description: 'Ignored for the unknown kind.',
    initialValue: sampleStatuses[kind]!.supporting,
  );
  final size = context.knobs.object.segmented<StatusPillSize>(
    label: 'Size',
    options: StatusPillSize.values,
    labelBuilder: (size) => size.name,
  );
  return ComponentStage(
    child: Center(
      child: StatusPill(
        status: PlaceStatus(kind: kind, supporting: supporting),
        size: size,
      ),
    ),
  );
}

@widgetbook.UseCase(name: 'All states', type: StatusPill)
Widget buildStatusPillAllStatesUseCase(BuildContext context) {
  return ComponentStage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final size in StatusPillSize.values) ...[
          Text(size.name, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in sampleStatuses.values)
                StatusPill(status: status, size: size),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ],
    ),
  );
}
