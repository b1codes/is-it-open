import 'package:flutter/material.dart';

import '../../utils/place_status.dart';
import '../../utils/places_theme.dart';

enum StatusPillSize { small, medium }

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.status,
    this.size = StatusPillSize.small,
  });

  final PlaceStatus status;
  final StatusPillSize size;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final isMedium = size == StatusPillSize.medium;
    final fontSize = isMedium ? 14.0 : 12.0;
    final dotSize = isMedium ? 8.0 : 6.0;
    final hPad = isMedium ? 12.0 : 10.0;
    final vPad = isMedium ? 6.0 : 4.0;
    final gap = isMedium ? 8.0 : 6.0;

    if (status.kind == PlaceStatusKind.unknown) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(color: theme.unknownOutline, width: 1),
          borderRadius: BorderRadius.circular(PlacesRadius.pill),
        ),
        child: Text(
          'Hours unknown',
          style: TextStyle(
            color: theme.inkMuted,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            height: 1.0,
          ),
        ),
      );
    }

    final bg = theme.statusColor(status.kind);
    final fg = theme.statusOnContrast(status.kind);
    final leading = _leadingWord(status.kind);
    final supporting = status.supporting.isEmpty
        ? ''
        : ' · ${status.supporting}';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PlacesRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.95),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: gap),
          Flexible(
            child: Text(
              '$leading$supporting',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _leadingWord(PlaceStatusKind kind) => switch (kind) {
    PlaceStatusKind.open => 'Open',
    PlaceStatusKind.closingSoon => 'Closes',
    PlaceStatusKind.closed => 'Closed',
    PlaceStatusKind.unknown => '',
  };
}
