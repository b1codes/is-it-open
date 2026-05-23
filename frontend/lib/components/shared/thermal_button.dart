import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

class ThermalButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool isLoading;

  const ThermalButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
  });

  @override
  State<ThermalButton> createState() => _ThermalButtonState();
}

class _ThermalButtonState extends State<ThermalButton> with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  Offset? _tapPosition;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed == null || widget.isLoading) return;
    setState(() {
      _tapPosition = details.localPosition;
    });
    _glowController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final effects = Theme.of(context).extension<AppEffects>();
    final isEnabled = widget.onPressed != null && !widget.isLoading;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTap: () {
        if (isEnabled) {
          widget.onPressed!();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The base button
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: isEnabled ? AppColors.terracotta : AppColors.inkWarmMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Opacity(
              opacity: widget.isLoading ? 0.0 : 1.0,
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                child: widget.child,
              ),
            ),
          ),

          // Loading indicator
          if (widget.isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),

          // Thermal Glow Layer
          if (_tapPosition != null)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _ThermalGlowPainter(
                      position: _tapPosition!,
                      radius: _glowController.value * 150,
                      opacity: (1.0 - _glowController.value).clamp(0.0, 1.0),
                      gradient: effects?.thermalGlowGradient ??
                          const LinearGradient(
                            colors: [AppColors.thermalCore, AppColors.thermalCorona],
                          ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ThermalGlowPainter extends CustomPainter {
  final Offset position;
  final double radius;
  final double opacity;
  final Gradient gradient;

  _ThermalGlowPainter({
    required this.position,
    required this.radius,
    required this.opacity,
    required this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: position, radius: radius),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15)
      ..blendMode = BlendMode.screen
      ..color = Colors.white.withValues(alpha: opacity);

    canvas.drawCircle(position, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _ThermalGlowPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.radius != radius ||
        oldDelegate.opacity != opacity;
  }
}
