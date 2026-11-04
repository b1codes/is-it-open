import 'package:flutter/widgets.dart';

/// Closes [route] (a screen, sheet or dialog) once work it started has
/// finished, if it's still open.
///
/// By then the user may have closed it themselves (back, a swipe, a tap
/// outside a sheet). Calling `Navigator.pop` would then close the screen
/// under it, and on the first screen leave the app blank. Capture the route
/// with `ModalRoute.of(context)` before the first `await`.
void closeRoute<T>(NavigatorState navigator, Route<T>? route, [T? result]) {
  if (route == null || !route.isActive) return;
  if (route.isCurrent) {
    navigator.pop(result);
  } else {
    // Something was opened on top of it; take it out from underneath.
    navigator.removeRoute(route, result);
  }
}
