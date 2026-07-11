import 'package:flutter/material.dart';

import '../../models/saved_place.dart';
import '../../utils/graphics_helper.dart';
import '../../utils/place_status.dart';
import '../../utils/places_theme.dart';
import 'status_pill.dart';

// Grid presentation: same content as SavedPlaceRow, stacked. Stays flat;
// hierarchy comes from spacing and type, not card chrome.

class SavedPlaceTile extends StatelessWidget {
  const SavedPlaceTile({
    super.key,
    required this.savedPlace,
    required this.status,
    required this.isOnToday,
    required this.onTap,
    required this.onToggleToday,
    required this.onLongPress,
  });

  final SavedPlace savedPlace;
  final PlaceStatus status;
  final bool isOnToday;
  final VoidCallback onTap;
  final VoidCallback onToggleToday;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final name = savedPlace.customName ?? savedPlace.place.name;
    final address = savedPlace.place.address;

    return Material(
      color: theme.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlacesRadius.md),
        side: BorderSide(color: theme.ashSoft, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(PlacesRadius.md),
        splashColor: theme.anchor.withValues(alpha: 0.06),
        highlightColor: theme.anchor.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.all(PlacesSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GraphicsHelper.buildProfileGraphic(savedPlace, size: 24),
                  const SizedBox(width: PlacesSpacing.sm),
                  Expanded(
                    child: Text(
                      name,
                      style: PlacesType.title(theme.ink),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PlacesSpacing.sm),
              Text(
                address,
                style: PlacesType.bodySmall(
                  theme.inkMuted,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              const SizedBox(height: PlacesSpacing.sm),
              Row(
                children: [
                  Expanded(child: StatusPill(status: status)),
                  const SizedBox(width: PlacesSpacing.xs),
                  _TodayIconToggle(isOnToday: isOnToday, onTap: onToggleToday),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayIconToggle extends StatelessWidget {
  const _TodayIconToggle({required this.isOnToday, required this.onTap});

  final bool isOnToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Semantics(
      button: true,
      label: isOnToday ? 'Remove from today\'s route' : 'Add to today\'s route',
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: Material(
              color: isOnToday
                  ? theme.anchor.withValues(alpha: 0.12)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PlacesRadius.pill),
                side: isOnToday
                    ? BorderSide.none
                    : BorderSide(color: theme.anchor.withValues(alpha: 0.5)),
              ),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(PlacesRadius.pill),
                child: Icon(
                  isOnToday ? Icons.check_rounded : Icons.add_rounded,
                  size: 18,
                  color: theme.anchor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
