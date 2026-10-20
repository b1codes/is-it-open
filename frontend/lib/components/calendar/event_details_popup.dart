import 'package:flutter/material.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:intl/intl.dart';
import '../../utils/places_theme.dart';
import '../shared/glass_card.dart';

class EventDetailsPopup extends StatelessWidget {
  final CalendarEventData event;

  const EventDetailsPopup({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final startTime = event.startTime;
    final endTime = event.endTime;
    String timeRange = '';

    if (startTime != null && endTime != null) {
      final timeFormat = DateFormat.jm();
      timeRange =
          '${timeFormat.format(startTime)} - ${timeFormat.format(endTime)}';
    } else {
      timeRange = 'All Day';
    }

    // Opaque, so the text color can be chosen for the event's color; with
    // the backdrop showing through, white text could be under 3:1.
    final background = Color.alphaBlend(
      event.color,
      context.places.paperRaised,
    );
    final onEvent = PlacesTheme.onColor(background);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: GlassCard(
        color: background,
        opacity: 1,
        blur: 15,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: event.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: onEvent,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: onEvent),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: onEvent.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, color: onEvent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    timeRange,
                    style: TextStyle(
                      color: onEvent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                event.description!,
                style: TextStyle(color: onEvent, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
