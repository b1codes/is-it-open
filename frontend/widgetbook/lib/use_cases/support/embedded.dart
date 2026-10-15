import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

/// Knob for screens HomeScreen also hosts inside its draggable sheet.
bool embeddedKnob(BuildContext context) => context.knobs.boolean(
  label: 'Embedded',
  description: 'Render as HomeScreen\'s bottom-sheet content (no app bar).',
);

/// Embedded screens drop their own Scaffold, so give them the Material
/// surface HomeScreen's sheet would.
Widget embedIfNeeded({required bool embedded, required Widget child}) {
  return embedded ? Scaffold(body: child) : child;
}
