import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUp, setUpAll, tearDown, tearDownAll;
import 'package:frontend/utils/availability_calculator.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  test(
    'calculateAvailableWindows subtracts personal events from business hours',
    () {
      final businessBlocks = [
        {
          'id': 'place1',
          'startTime': DateTime(2026, 4, 21, 9, 0),
          'endTime': DateTime(2026, 4, 21, 17, 0),
        },
      ];

      final personalEvents = [
        {
          'startTime': DateTime(2026, 4, 21, 12, 0),
          'endTime': DateTime(2026, 4, 21, 13, 0),
        },
      ];

      final result = AvailabilityCalculator.calculateAvailableWindows(
        businessBlocks: businessBlocks,
        personalEvents: personalEvents,
      );

      // Note: New logic might subdivide differently, but for this case it should be 2 windows
      expect(result.length, 2);
      expect(result[0].startTime, DateTime(2026, 4, 21, 9, 0));
      expect(result[0].endTime, DateTime(2026, 4, 21, 12, 0));
      expect(result[1].startTime, DateTime(2026, 4, 21, 13, 0));
      expect(result[1].endTime, DateTime(2026, 4, 21, 17, 0));
    },
  );
  test('no business blocks means no windows', () {
    expect(
      AvailabilityCalculator.calculateAvailableWindows(
        businessBlocks: const [],
        personalEvents: [
          {'startTime': _at(9), 'endTime': _at(10)},
        ],
      ),
      isEmpty,
    );
  });

  test('splits where places open and close and counts them', () {
    final windows = AvailabilityCalculator.calculateAvailableWindows(
      businessBlocks: [
        {'id': 'cafe', 'startTime': _at(7), 'endTime': _at(12)},
        {'id': 'gym', 'startTime': _at(10), 'endTime': _at(20)},
      ],
      personalEvents: const [],
    );
    expect(
      windows.map(
        (w) => (w.startTime.hour, w.endTime.hour, w.placeIds.join(',')),
      ),
      [(7, 10, 'cafe'), (10, 12, 'cafe,gym'), (12, 20, 'gym')],
    );
    expect(windows[1].placeCount, 2);
    expect(windows.first.date, DateTime(2026, 10, 20));
  });

  test('clips to the 6am-11pm planning day', () {
    final windows = AvailabilityCalculator.calculateAvailableWindows(
      businessBlocks: [
        {'id': 'diner', 'startTime': _at(0), 'endTime': _at(23, 59)},
      ],
      personalEvents: const [],
    );
    expect(windows.single.startTime, _at(6));
    expect(windows.single.endTime, _at(23));
  });

  test('groups blocks and events by day', () {
    final tomorrow = DateTime(2026, 10, 21, 9);
    final windows = AvailabilityCalculator.calculateAvailableWindows(
      businessBlocks: [
        {'id': 'a', 'startTime': _at(9), 'endTime': _at(10)},
        {
          'id': 'a',
          'startTime': tomorrow,
          'endTime': tomorrow.add(const Duration(hours: 1)),
        },
      ],
      // Busy all of today's block, free tomorrow.
      personalEvents: [
        {'startTime': _at(8), 'endTime': _at(11)},
      ],
    );
    expect(windows.single.startTime, tomorrow);
  });

  group('properties', () {
    Glados2(_anyBlocks, _anyEvents, ExploreConfig(numRuns: 300)).test(
      'windows are free, inside the day, disjoint and list who is open',
      (blocks, events) {
        final windows = AvailabilityCalculator.calculateAvailableWindows(
          businessBlocks: [
            for (final (i, (start, end)) in blocks.indexed)
              {'id': 'p$i', 'startTime': _min(start), 'endTime': _min(end)},
          ],
          personalEvents: [
            for (final (start, end) in events)
              {'startTime': _min(start), 'endTime': _min(end)},
          ],
        );

        bool busy(int start, int end) =>
            events.any((e) => e.$1 < end && start < e.$2);
        Set<String> openThroughout(int start, int end) => {
          for (final (i, (s, e)) in blocks.indexed)
            if (s <= start && end <= e) 'p$i',
        };

        final spans = [
          for (final w in windows)
            (_minuteOf(w.startTime), _minuteOf(w.endTime)),
        ];
        for (final (i, (start, end)) in spans.indexed) {
          final w = windows[i];
          expect(start, lessThan(end));
          expect(start, greaterThanOrEqualTo(6 * 60));
          expect(end, lessThanOrEqualTo(23 * 60));
          expect(w.date, DateTime(2026, 10, 20));
          expect(busy(start, end), isFalse, reason: 'overlaps an event');
          expect(w.placeIds.toSet(), openThroughout(start, end));
          expect(w.placeIds, isNotEmpty);
          expect(w.placeCount, w.placeIds.length);
          if (i > 0) expect(spans[i - 1].$2, lessThanOrEqualTo(start));
        }

        // Every free quarter hour with a place open is in some window.
        for (var q = 6 * 60; q < 23 * 60; q += 15) {
          if (busy(q, q + 15) || openThroughout(q, q + 15).isEmpty) continue;
          expect(
            spans.any((s) => s.$1 <= q && q + 15 <= s.$2),
            isTrue,
            reason: 'free slot at ${q ~/ 60}:${q % 60} missing',
          );
        }
      },
    );
  });
}

DateTime _at(int hour, [int minute = 0]) =>
    DateTime(2026, 10, 20, hour, minute);

DateTime _min(int minuteOfDay) => _at(0, minuteOfDay);

int _minuteOf(DateTime dt) => dt.hour * 60 + dt.minute;

/// Non-empty [start, end) spans on one day, on quarter hours.
final _anySpan = any
    .combine2(
      any.intInRange(0, 96),
      any.intInRange(1, 40),
      (int start, int length) =>
          (start * 15, ((start + length).clamp(0, 96)) * 15),
    )
    .map((s) => s.$1 < s.$2 ? s : (s.$1 - 15, s.$2));

final _anyBlocks = any.listWithLengthInRange(1, 5, _anySpan);
final _anyEvents = any.listWithLengthInRange(0, 4, _anySpan);
