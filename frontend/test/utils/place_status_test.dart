import 'dart:math' show min;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/hours.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/utils/place_status.dart';
import 'package:frontend/utils/places_theme.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUp, setUpAll, tearDown, tearDownAll;
import 'package:latlong2/latlong.dart';

// PlaceStatusCalculator works on the wall clock: hours are local times and
// day-of-week is Mon=0..Sun=6. The model below answers "is it open?" from
// minutes-of-the-week, independently of the calculator, and the property
// tests check the calculator against it. Run locally (or in CI, which uses
// America/New_York) they also cross the US DST changes.

const _week = 7 * 24 * 60;

Place _place(List<BusinessHours> hours) => Place(
  tomtomId: 't',
  name: 'Test',
  address: '',
  location: const LatLng(0, 0),
  hours: hours,
);

BusinessHours _hours(int day, int open, int close) => BusinessHours(
  dayOfWeek: day,
  openTime: TimeOfDay(hour: open ~/ 60, minute: open % 60),
  closeTime: TimeOfDay(hour: close ~/ 60, minute: close % 60),
);

BusinessHours _h(int day, String open, String close) =>
    BusinessHours(dayOfWeek: day, openTime: _tod(open), closeTime: _tod(close));

TimeOfDay _tod(String hhmm) => TimeOfDay(
  hour: int.parse(hhmm.split(':')[0]),
  minute: int.parse(hhmm.split(':')[1]),
);

/// Open spans in minutes from Monday 00:00; a block that closes at or before
/// it opens runs past midnight. Repeated a week either side so spans that
/// wrap from Sunday into Monday are found.
List<(int, int)> _spans(List<BusinessHours> hours) => [
  for (final h in hours)
    for (final shift in const [-_week, 0, _week])
      () {
        final open = h.openTime.hour * 60 + h.openTime.minute;
        final close = h.closeTime.hour * 60 + h.closeTime.minute;
        final start = h.dayOfWeek * 1440 + open + shift;
        final length = close > open ? close - open : close - open + 1440;
        return (start, start + length);
      }(),
];

bool _openAt(List<(int, int)> spans, int minute) =>
    spans.any((s) => s.$1 <= minute && minute < s.$2);

/// Minutes since Monday 00:00 of [dt]'s week, on the wall clock.
int _weekMinute(DateTime dt) =>
    (dt.weekday - 1) * 1440 + dt.hour * 60 + dt.minute;

/// Span starts and ends within a week after [from], in order: the only
/// minutes where open/closed can change.
List<int> _boundariesAfter(List<(int, int)> spans, int from) => {
  for (final (start, end) in spans) ...[start, end],
}.where((m) => m > from && m <= from + _week).toList()..sort();

/// [now] plus [minutes] on the wall clock, as the device represents it: a
/// time skipped by a spring-forward lands an hour later.
DateTime _wallClockAfter(DateTime now, int minutes) =>
    DateTime(now.year, now.month, now.day, now.hour, now.minute + minutes);

bool _isOpen(PlaceStatus s) =>
    s.kind == PlaceStatusKind.open || s.kind == PlaceStatusKind.closingSoon;

// Mondays of an ordinary week and of the weeks with US and EU DST changes.
final _mondays = [
  DateTime(2026, 10, 19),
  DateTime(2026, 3, 2), // US spring forward Sun 8 Mar
  DateTime(2026, 3, 23), // EU spring forward Sun 29 Mar
  DateTime(2026, 10, 26), // US fall back Sun 1 Nov
];

final _anyBlock = any.combine3(
  any.intInRange(0, 7),
  any.intInRange(0, 96), // quarter hours, so blocks often touch
  any.intInRange(0, 96),
  (int day, int open, int close) => _hours(day, open * 15, close * 15),
);

final _anyHours = any.listWithLengthInRange(1, 6, _anyBlock);

final _anyNow = any.combine2(
  any.choose(_mondays),
  any.intInRange(0, _week),
  (DateTime monday, int minute) => DateTime(
    monday.year,
    monday.month,
    monday.day + minute ~/ 1440,
    0,
    minute % 1440,
  ),
);

// A fresh config (and so a fresh seeded Random) per property, so each one
// sees the same inputs however the tests are filtered or ordered.
ExploreConfig get _explore => ExploreConfig(numRuns: 500);

void main() {
  group('PlaceStatusCalculator properties', () {
    Glados2(_anyHours, _anyNow, _explore).test(
      'is open exactly when the hours say so',
      (hours, now) {
        final status = PlaceStatusCalculator.compute(_place(hours), now: now);
        expect(_isOpen(status), _openAt(_spans(hours), _weekMinute(now)));
      },
    );

    Glados2(_anyHours, _anyNow, _explore).test(
      'when open, nextChange is when it next closes',
      (hours, now) {
        final status = PlaceStatusCalculator.compute(_place(hours), now: now);
        if (!_isOpen(status)) return;
        final spans = _spans(hours);
        final from = _weekMinute(now);
        final closes = _boundariesAfter(
          spans,
          from,
        ).where((m) => !_openAt(spans, m)).firstOrNull;
        if (closes == null) {
          // Open through every boundary for the next week: never closes.
          expect(status.nextChange, isNull);
          expect(status.supporting, '24 hours');
          return;
        }
        final left = closes - from;
        expect(status.nextChange, _wallClockAfter(now, left));
        expect(status.kind == PlaceStatusKind.closingSoon, left <= 60);
        expect(
          status.supporting,
          left <= 60 ? 'in $left min' : startsWith('until '),
        );
      },
    );

    Glados2(_anyHours, _anyNow, _explore).test(
      'when closed, nextChange is the next opening',
      (hours, now) {
        final status = PlaceStatusCalculator.compute(_place(hours), now: now);
        if (_isOpen(status)) return;
        expect(status.kind, PlaceStatusKind.closed);
        final from = _weekMinute(now);
        final opens = _spans(
          hours,
        ).map((s) => s.$1).where((start) => start > from).reduce(min);
        expect(opens - from, inInclusiveRange(1, _week));
        expect(status.nextChange, _wallClockAfter(now, opens - from));
        expect(status.supporting, startsWith('opens '));
      },
    );
  });

  group('PlaceStatusCalculator examples', () {
    // Monday 19 Oct 2026.
    DateTime mon(int hour, [int minute = 0]) =>
        DateTime(2026, 10, 19, hour, minute);
    final nineToFive = _place([
      for (var d = 0; d < 5; d++) _h(d, '09:00', '17:00'),
    ]);

    PlaceStatus status(Place p, DateTime now, {bool use24 = false}) =>
        PlaceStatusCalculator.compute(p, now: now, use24HourFormat: use24);

    test('no hours is unknown', () {
      final s = status(_place([]), mon(12));
      expect(s.kind, PlaceStatusKind.unknown);
      expect(s.supporting, '');
      expect(s.nextChange, isNull);
    });

    test('open with time to spare', () {
      final s = status(nineToFive, mon(12));
      expect(s.kind, PlaceStatusKind.open);
      expect(s.supporting, 'until 5pm');
      expect(s.nextChange, mon(17));
      expect(
        status(nineToFive, mon(12), use24: true).supporting,
        'until 17:00',
      );
    });

    test('closing soon within the hour', () {
      final s = status(nineToFive, mon(16, 15));
      expect(s.kind, PlaceStatusKind.closingSoon);
      expect(s.supporting, 'in 45 min');
      expect(status(nineToFive, mon(16)).kind, PlaceStatusKind.closingSoon);
      expect(status(nineToFive, mon(15, 59)).kind, PlaceStatusKind.open);
    });

    test('opens at the open minute and closes at the close minute', () {
      expect(status(nineToFive, mon(9)).kind, PlaceStatusKind.open);
      expect(status(nineToFive, mon(17)).kind, PlaceStatusKind.closed);
    });

    test('closed before opening today', () {
      final s = status(nineToFive, mon(7, 30));
      expect(s.kind, PlaceStatusKind.closed);
      expect(s.supporting, 'opens 9am');
      expect(s.nextChange, mon(9));
    });

    test('closed in the evening opens tomorrow', () {
      final s = status(nineToFive, mon(18));
      expect(s.supporting, 'opens 9am tomorrow');
      expect(s.nextChange, DateTime(2026, 10, 20, 9));
    });

    test('closed for the weekend names the day', () {
      final s = status(nineToFive, DateTime(2026, 10, 23, 18)); // Friday
      expect(s.supporting, 'opens 9am Mon');
      expect(s.nextChange, DateTime(2026, 10, 26, 9));
    });

    test('formats minutes, noon and midnight', () {
      final odd = _place([_h(0, '00:00', '12:30')]);
      expect(status(odd, mon(1)).supporting, 'until 12:30pm');
      expect(status(odd, mon(13), use24: true).supporting, 'opens 00:00 Mon');
      expect(status(odd, mon(13)).supporting, 'opens 12am Mon');
    });

    test('a bar open past midnight is open until it closes', () {
      final bar = _place([_h(0, '18:00', '02:00')]);
      final lateMonday = status(bar, mon(23, 30));
      expect(lateMonday.kind, PlaceStatusKind.open);
      expect(lateMonday.supporting, 'until 2am');
      expect(lateMonday.nextChange, DateTime(2026, 10, 20, 2));

      final earlyTuesday = status(bar, DateTime(2026, 10, 20, 1, 30));
      expect(earlyTuesday.kind, PlaceStatusKind.closingSoon);
      expect(earlyTuesday.supporting, 'in 30 min');
    });

    test('a Sunday late shift is still open early on Monday', () {
      final club = _place([_h(6, '22:00', '04:00')]);
      expect(status(club, mon(2)).kind, PlaceStatusKind.open);
      expect(status(club, mon(3)).kind, PlaceStatusKind.closingSoon);
      expect(status(club, mon(5)).kind, PlaceStatusKind.closed);
    });

    test('back-to-back blocks count as one opening', () {
      final split = _place([_h(0, '09:00', '12:00'), _h(0, '12:00', '17:00')]);
      final s = status(split, mon(11, 30));
      expect(s.kind, PlaceStatusKind.open);
      expect(s.nextChange, mon(17));
    });

    test('a lunch closure reopens the same day', () {
      final library = _place([
        _h(0, '09:00', '12:30'),
        _h(0, '13:30', '18:00'),
      ]);
      final s = status(library, mon(13));
      expect(s.kind, PlaceStatusKind.closed);
      expect(s.supporting, 'opens 1:30pm');
    });

    test('a weekly slot that just ended opens again in a week', () {
      final market = _place([_h(0, '09:00', '10:00')]);
      final s = status(market, mon(11));
      expect(s.kind, PlaceStatusKind.closed);
      expect(s.nextChange, DateTime(2026, 10, 26, 9));
      expect(s.supporting, 'opens 9am Mon');
    });

    test('a place open around the clock never closes', () {
      final always = _place([
        for (var d = 0; d < 7; d++) _h(d, '00:00', '00:00'),
      ]);
      final s = status(always, mon(12));
      expect(s.kind, PlaceStatusKind.open);
      expect(s.nextChange, isNull);
      expect(s.supporting, '24 hours');
    });

    test('the day after a spring-forward is still "tomorrow"', () {
      final s = status(nineToFive, DateTime(2026, 3, 8, 18)); // Sun 8 Mar
      expect(s.nextChange, DateTime(2026, 3, 9, 9));
      expect(s.supporting, 'opens 9am tomorrow');
    });

    test('just after midnight on a fall-back day, tomorrow is Monday', () {
      final s = status(nineToFive, DateTime(2026, 11, 1, 0, 30)); // Sun 1 Nov
      expect(s.nextChange, DateTime(2026, 11, 2, 9));
      expect(s.supporting, 'opens 9am tomorrow');
    });
  });
}
