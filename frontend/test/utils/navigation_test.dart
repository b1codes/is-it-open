import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/navigation.dart';

void main() {
  late GlobalKey<NavigatorState> navigator;

  Future<Route<String>> pushScreen(WidgetTester tester, String name) async {
    final route = MaterialPageRoute<String>(builder: (_) => Text(name));
    navigator.currentState!.push(route);
    await tester.pumpAndSettle();
    return route;
  }

  setUp(() => navigator = GlobalKey<NavigatorState>());

  Future<void> start(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(navigatorKey: navigator, home: const Text('home')),
  );

  testWidgets('pops the route when it is on top, with the result', (
    tester,
  ) async {
    await start(tester);
    final route = await pushScreen(tester, 'detail');
    closeRoute(navigator.currentState!, route, 'done');
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(await route.popped, 'done');
  });

  testWidgets('takes it out from under a route opened on top', (tester) async {
    await start(tester);
    final detail = await pushScreen(tester, 'detail');
    await pushScreen(tester, 'plan');
    closeRoute(navigator.currentState!, detail);
    await tester.pumpAndSettle();
    expect(find.text('plan'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('does nothing once the user has closed it', (tester) async {
    await start(tester);
    final route = await pushScreen(tester, 'detail');
    navigator.currentState!.pop();
    await tester.pump(); // still animating out
    closeRoute(navigator.currentState!, route);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    closeRoute(navigator.currentState!, null);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
}
