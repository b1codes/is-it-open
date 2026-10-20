import 'package:flutter/material.dart';

import '../../models/saved_place.dart';
import '../../utils/graphics_helper.dart';
import '../../utils/place_status.dart';
import '../../utils/places_theme.dart';
import 'status_pill.dart';

// Flat row presentation of a saved place. No card chrome, no decorative
// shadow, no glass. The row is content with a divider; lift comes from
// state, not at-rest decoration (DESIGN.md §4 Flat-At-Rest Rule).

class SavedPlaceRow extends StatelessWidget {
  const SavedPlaceRow({
    super.key,
    required this.savedPlace,
    required this.status,
    required this.isOnToday,
    required this.onTap,
    required this.onToggleToday,
    required this.onLongPress,
    this.showDivider = true,
  });

  final SavedPlace savedPlace;
  final PlaceStatus status;
  final bool isOnToday;
  final VoidCallback onTap;
  final VoidCallback onToggleToday;
  final VoidCallback onLongPress;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final name = savedPlace.customName ?? savedPlace.place.name;
    final address = savedPlace.place.address;

    return Material(
      color: theme.paper,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: theme.anchor.withValues(alpha: 0.06),
        highlightColor: theme.anchor.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PlacesSpacing.lg,
            PlacesSpacing.md,
            PlacesSpacing.md,
            PlacesSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: GraphicsHelper.buildProfileGraphic(
                      savedPlace,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: PlacesSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: PlacesType.title(theme.ink),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: PlacesSpacing.xs),
                        Text(
                          address,
                          style: PlacesType.bodySmall(theme.inkMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: PlacesSpacing.sm),
                        StatusPill(status: status),
                      ],
                    ),
                  ),
                  const SizedBox(width: PlacesSpacing.sm),
                  _TodayToggle(isOnToday: isOnToday, onTap: onToggleToday),
                ],
              ),
              if (showDivider)
                Padding(
                  padding: const EdgeInsets.only(
                    top: PlacesSpacing.md,
                    left: 28 + PlacesSpacing.md, // align under name
                  ),
                  child: Container(height: 1, color: theme.ashSoft),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayToggle extends StatelessWidget {
  const _TodayToggle({required this.isOnToday, required this.onTap});

  final bool isOnToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;

    // TextButton is its own semantics node, so the spoken label goes on its
    // text; a Semantics wrapper around the button would be dropped.
    return SizedBox(
      height: 48,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: PlacesSpacing.md,
            vertical: PlacesSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PlacesRadius.pill),
          ),
          backgroundColor: isOnToday
              ? theme.anchor.withValues(alpha: 0.12)
              : Colors.transparent,
          foregroundColor: theme.anchor,
          side: isOnToday
              ? BorderSide.none
              : BorderSide(color: theme.anchor.withValues(alpha: 0.5)),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOnToday ? Icons.check_rounded : Icons.add_rounded,
              size: 16,
              color: theme.anchor,
            ),
            const SizedBox(width: PlacesSpacing.xs),
            Text(
              isOnToday ? 'On Today' : 'Today',
              semanticsLabel: isOnToday
                  ? 'Remove from today\'s route'
                  : 'Add to today\'s route',
              style: TextStyle(
                color: theme.anchor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
