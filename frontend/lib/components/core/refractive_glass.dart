import 'dart:ui';
import 'package:flutter/material.dart';
import '../../utils/places_theme.dart';

/// The standard LLC optical material for floating UI.
/// Provides a sophisticated sense of hierarchy via Refractive Depth.
class RefractiveGlass extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double opacity;
  final double blur;
  final double borderWidth;

  const RefractiveGlass({
    super.key,
    required this.child,
    this.borderRadius = PlacesRadius.lg,
    this.opacity = 0.05,
    this.blur = 20.0,
    this.borderWidth = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: opacity * 2),
                width: borderWidth,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
