import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/env_config.dart';
import '../../utils/places_theme.dart';

// Small non-interactive map render that sits beside the address on the place
// detail. Stays a thumbnail on purpose: a full-bleed map at the top of detail
// would push us into the "Generic Maps clone" anti-reference (PRODUCT.md).
class AddressMapThumb extends StatelessWidget {
  const AddressMapThumb({super.key, required this.location, this.size = 84});

  final LatLng location;
  final double size;

  static bool hasUsableLocation(LatLng location) =>
      !(location.latitude == 0 && location.longitude == 0);

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(PlacesRadius.md),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.ashSoft,
          border: Border.all(color: theme.ashSoft),
          borderRadius: BorderRadius.circular(PlacesRadius.md),
        ),
        child: IgnorePointer(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: location,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: EnvConfig.mapTileUrl(dark: isDark),
                userAgentPackageName: 'com.brandonlc.isitopen',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: location,
                    width: 28,
                    height: 28,
                    alignment: Alignment.topCenter,
                    child: _PinMark(color: theme.anchor),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinMark extends StatelessWidget {
  const _PinMark({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PinPainter(color: color),
      size: const Size(20, 24),
    );
  }
}

class _PinPainter extends CustomPainter {
  _PinPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final cx = size.width / 2;
    final radius = size.width * 0.32;
    final headCenter = Offset(cx, radius);

    final path = ui.Path()
      ..moveTo(cx - radius * 0.85, headCenter.dy + radius * 0.45)
      ..lineTo(cx, size.height)
      ..lineTo(cx + radius * 0.85, headCenter.dy + radius * 0.45)
      ..arcToPoint(
        Offset(cx - radius * 0.85, headCenter.dy + radius * 0.45),
        radius: Radius.circular(radius),
        clockwise: false,
      )
      ..close();

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    // Inner highlight dot to reinforce signal at small sizes.
    canvas.drawCircle(
      headCenter,
      radius * 0.35,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant _PinPainter old) => old.color != color;
}
