import 'package:flutter/material.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../../mocks/sample_data.dart';

// The full signed-in shell: map underneath, tab content in the draggable
// sheet, side menu on wide viewports. Use the Viewport addon to compare the
// mobile and desktop layouts. Map tiles need network access.
@widgetbook.UseCase(name: 'Signed in', type: HomeScreen)
Widget buildHomeScreenUseCase(BuildContext context) {
  return MockAppScope(
    todayRouteIds: [sampleSavedPlaces.first.place.tomtomId],
    child: const HomeScreen(),
  );
}
