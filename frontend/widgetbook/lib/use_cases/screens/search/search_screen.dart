import 'package:flutter/material.dart';
import 'package:frontend/screens/search/search_screen.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../support/embedded.dart';

// Suggestions load on open; type a query such as "coffee", "gym" or "NY"
// to get results from the fake API.
@widgetbook.UseCase(name: 'Default', type: SearchScreen)
Widget buildSearchScreenUseCase(BuildContext context) {
  final embedded = embeddedKnob(context);
  final apiFails = context.knobs.boolean(
    label: 'Search fails',
    description: 'Queries resolve to SearchStatus.failure.',
  );
  return MockAppScope(
    apiFails: apiFails,
    child: embedIfNeeded(
      embedded: embedded,
      child: SearchScreen(embedded: embedded),
    ),
  );
}
