import 'package:flutter/material.dart';
import 'package:frontend/components/shared/auth0_universal_login_dialog.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/route_harness.dart';

@widgetbook.UseCase(name: 'Default', type: Auth0UniversalLoginDialog)
Widget buildAuth0UniversalLoginDialogUseCase(BuildContext context) {
  final connection = context.knobs.objectOrNull.dropdown<String>(
    label: 'Connection',
    options: const [
      'google-oauth2',
      'apple',
      'Username-Password-Authentication',
    ],
  );
  // Mirrors Auth0Service.login: the dialog sits over a dimmed barrier and
  // pops with the issued token.
  return RouteHarness(
    key: ValueKey(connection),
    builder: (_) => ColoredBox(
      color: Colors.black.withValues(alpha: 0.6),
      child: Auth0UniversalLoginDialog(connection: connection),
    ),
  );
}
