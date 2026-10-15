import 'package:flutter/material.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import 'package:frontend/screens/profile/settings_screen.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../../mocks/sample_data.dart';
import '../../support/embedded.dart';
import '../../support/route_harness.dart';

User _userKnob(BuildContext context) {
  return context.knobs.object.segmented<User>(
    label: 'User',
    options: [demoUser, minimalUser],
    labelBuilder: (u) => u == demoUser ? 'Complete profile' : 'New account',
  );
}

@widgetbook.UseCase(name: 'Default', type: MeScreen)
Widget buildMeScreenUseCase(BuildContext context) {
  final embedded = embeddedKnob(context);
  final user = _userKnob(context);
  final apiFails = context.knobs.boolean(
    label: 'Save fails',
    description: 'Saving the profile emits ProfileUpdateFailure.',
  );
  return MockAppScope(
    authState: AuthAuthenticated(user: user),
    apiFails: apiFails,
    child: embedIfNeeded(
      embedded: embedded,
      child: MeScreen(embedded: embedded),
    ),
  );
}

@widgetbook.UseCase(name: 'Default', type: SettingsScreen)
Widget buildSettingsScreenUseCase(BuildContext context) {
  final user = _userKnob(context);
  final use24HourFormat = context.knobs.boolean(label: '24-hour clock');
  // Pushed from MeScreen and SideMenu in the app.
  return MockAppScope(
    authState: AuthAuthenticated(user: user),
    use24HourFormat: use24HourFormat,
    child: RouteHarness(builder: (_) => const SettingsScreen()),
  );
}
