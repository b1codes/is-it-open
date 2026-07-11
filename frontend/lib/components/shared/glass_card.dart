import 'dart:ui';
import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final double? blur;
  final double? opacity;
  final Color? color;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Border? border;

  const GlassCard({
    super.key,
    required this.child,
    this.blur,
    this.opacity,
    this.color,
    this.borderRadius,
    this.padding,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final effects = Theme.of(context).extension<AppEffects>();
    final effectiveBlur = blur ?? effects?.glassBlur ?? 20.0;
    final effectiveOpacity = opacity ?? effects?.glassOpacity ?? 0.05;
    final effectiveColor = color ?? AppColors.glassSurface;
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(12);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
          child: Container(
            padding: padding ?? const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: effectiveOpacity),
              borderRadius: effectiveBorderRadius,
              border: border ??
                  Border.all(
                    color: AppColors.glassBorder.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
