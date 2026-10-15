import 'package:flutter/material.dart';
import 'package:frontend/components/places/quick_add_place_sheet.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../support/route_harness.dart';

@widgetbook.UseCase(name: 'Bottom sheet', type: QuickAddPlaceSheet)
Widget buildQuickAddPlaceSheetUseCase(BuildContext context) {
  final apiFails = context.knobs.boolean(
    label: 'Save fails',
    description: 'Simulate a backend error when saving.',
  );
  // Presented the way my_places' showModalBottomSheet does: the sheet
  // draws its own rounded surface over a scrim. Saving pops the route with
  // the new place, which the harness reports.
  return MockAppScope(
    apiFails: apiFails,
    child: RouteHarness(
      builder: (_) => const Scaffold(
        backgroundColor: Colors.black54,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: QuickAddPlaceSheet(),
        ),
      ),
    ),
  );
}
