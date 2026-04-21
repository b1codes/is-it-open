import 'package:flutter/material.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:intl/intl.dart';
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

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: GlassCard(
        color: event.color,
        opacity: 0.4,
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
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    timeRange,
                    style: const TextStyle(
                      color: Colors.white,
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
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
