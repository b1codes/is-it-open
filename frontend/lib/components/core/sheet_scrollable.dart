import 'package:flutter/material.dart';

/// [child] scrolling on [controller], at least as tall as the space it's
/// given. A screen in the phone home sheet must always have a scrollable on
/// the sheet's controller, or the sheet detaches: it can't be dragged, and
/// tab changes can't move it. Its lists do; this is for the states without
/// one (loading, an error, nothing found). Without a controller (not in the
/// sheet), [child] as it is.
class SheetScrollable extends StatelessWidget {
  const SheetScrollable({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) return child;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        controller: controller,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}
