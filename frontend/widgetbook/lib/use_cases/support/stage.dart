import 'package:flutter/material.dart';

/// Scaffold wrapper for component use cases: themed background, centered
/// content, and a ScaffoldMessenger target for [logAction].
class ComponentStage extends StatelessWidget {
  const ComponentStage({
    super.key,
    required this.child,
    this.maxWidth = 420,
    this.backdrop = false,
    this.padding = const EdgeInsets.all(24),
  });

  /// Marks the staged component, so the golden tests can crop to it.
  static const subjectKey = ValueKey('ComponentStage.subject');

  final Widget child;
  final double maxWidth;

  /// Paints a busy gradient behind the content so blur and translucency
  /// (glass surfaces) are visible.
  final bool backdrop;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (backdrop) const Positioned.fill(child: GlassBackdrop()),
          Center(
            child: SingleChildScrollView(
              padding: padding,
              child: ConstrainedBox(
                key: subjectKey,
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// High-contrast shapes that make backdrop blur readable in previews.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD66A4D), Color(0xFF2B4C7E), Color(0xFF5FB467)],
        ),
      ),
      child: Stack(
        children: const [
          Positioned(top: 40, left: 30, child: _Blob(160, Color(0xFFE7A23F))),
          Positioned(
            bottom: 60,
            right: 40,
            child: _Blob(220, Color(0xFF363430)),
          ),
          Positioned(top: 200, right: 120, child: _Blob(90, Colors.white)),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob(this.size, this.color);

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Surfaces a callback firing as a snackbar, so interactions are visible in
/// the catalog without wiring real navigation.
void logAction(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1200),
      ),
    );
}
