import 'package:flutter/material.dart';

/// Hosts [builder] as a pushed route on a nested Navigator.
///
/// Widgets that `Navigator.pop` themselves (dialogs, sheets, detail screens)
/// would otherwise pop the preview's only route and blank the canvas. Here
/// the pop lands on a launcher page that reports the result and can reopen
/// the route. Being a pushed route also gives app bars their real back
/// button, matching how these screens appear in the app.
class RouteHarness extends StatefulWidget {
  const RouteHarness({
    super.key,
    required this.builder,
    this.fullscreenDialog = false,
  });

  final WidgetBuilder builder;
  final bool fullscreenDialog;

  @override
  State<RouteHarness> createState() => _RouteHarnessState();
}

class _RouteHarnessState extends State<RouteHarness> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _lastResult = ValueNotifier<String?>(null);

  Route<Object?> _buildRoute() {
    final route = MaterialPageRoute<Object?>(
      // Resolved on every build, not captured: when knobs change, Navigator
      // rebuilds its routes and picks up the latest builder.
      builder: (context) => widget.builder(context),
      fullscreenDialog: widget.fullscreenDialog,
    );
    route.popped.then((result) {
      if (!mounted) return;
      _lastResult.value = result?.toString() ?? 'no result';
    });
    return route;
  }

  @override
  void dispose() {
    _lastResult.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navigatorKey,
      onGenerateInitialRoutes: (navigator, initialRoute) => [
        MaterialPageRoute<void>(builder: _buildLauncher),
        _buildRoute(),
      ],
    );
  }

  Widget _buildLauncher(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ValueListenableBuilder<String?>(
          valueListenable: _lastResult,
          builder: (context, result, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (result != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text('Closed with: $result'),
                ),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Reopen'),
                onPressed: () =>
                    _navigatorKey.currentState!.push(_buildRoute()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
