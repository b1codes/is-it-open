import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_workspace/main.dart';
import 'package:widgetbook_workspace/main.directories.g.dart';

/// Every generated use case, in the slug format WidgetbookNode.path produces
/// (e.g. `components/places/statuspill/playground`).
final List<String> useCasePaths = _useCasePaths(directories).toList();

Iterable<String> _useCasePaths(
  List<WidgetbookNode> nodes, [
  String prefix = '',
]) sync* {
  for (final node in nodes) {
    final path = '$prefix${node.name.replaceAll(' ', '-').toLowerCase()}';
    if (node is WidgetbookUseCase) {
      yield path;
    } else {
      yield* _useCasePaths(node.children ?? const [], '$path/');
    }
  }
}

/// Opens the use case at [path] in the catalog's preview mode, with the theme
/// and text scale set through the addons' query parameters, as a deep link
/// into the catalog would. The view's size is left to the caller.
Future<void> pumpUseCase(
  WidgetTester tester,
  String path, {
  String theme = 'Light',
  double textScale = 1,
}) async {
  final route = Uri(
    path: '/',
    queryParameters: {
      'path': path,
      'preview': '',
      'theme': '{name:$theme}',
      'text-scale': '{factor:${textScale.toStringAsFixed(2)}}',
    },
  ).toString();
  await tester.pumpWidget(WidgetbookApp(initialRoute: route));
  // Let fake API responses (300ms) and entry animations land.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));

  // Guard against a silent pass on Widgetbook's home page when a path fails
  // to resolve.
  final state = tester
      .widget<WidgetbookScope>(find.byType(WidgetbookScope))
      .notifier!;
  expect(state.useCase, isNotNull, reason: 'No use case at $path');
}

/// Unmounts the catalog inside the test, so pending fake-API timers drain.
Future<void> unmountUseCase(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
