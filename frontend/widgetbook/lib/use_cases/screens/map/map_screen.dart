import 'package:flutter/material.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/screens/map/map_screen.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../../mocks/sample_data.dart';
import '../../support/stage.dart';

// Map tiles load from OpenStreetMap / CARTO, so these previews need network.
// The screen also asks for the device location; when that is unavailable it
// centers on the user's home (or NYC).

@widgetbook.UseCase(name: 'Default', type: MapScreen)
Widget buildMapScreenUseCase(BuildContext context) {
  final embedded = context.knobs.boolean(
    label: 'Embedded',
    description: 'Render as HomeScreen\'s background layer.',
  );
  final hasHome = context.knobs.boolean(
    label: 'User has home address',
    initialValue: true,
  );
  return MockAppScope(
    authState: AuthAuthenticated(user: hasHome ? demoUser : minimalUser),
    child: Scaffold(
      body: Builder(
        builder: (context) => MapScreen(
          embedded: embedded,
          onPlaceTapped: (sp) =>
              logAction(context, 'onPlaceTapped: ${sp.place.name}'),
        ),
      ),
    ),
  );
}

@widgetbook.UseCase(name: 'No saved places', type: MapScreen)
Widget buildMapScreenEmptyUseCase(BuildContext context) {
  return const MockAppScope(bookmarks: [], child: MapScreen());
}
