import 'package:flutter/material.dart' show TimeOfDay;

import '../models/hours.dart';
import '../models/place.dart';
import 'places_theme.dart' show PlaceStatusKind;

class PlaceStatus {
  const PlaceStatus({
    required this.kind,
    required this.supporting,
    this.nextChange,
  });

  final PlaceStatusKind kind;

  // The fragment that follows the leading "Open"/"Closes"/"Closed" word in the
  // pill — e.g. "until 7:00pm" / "in 28 min" / "opens 9am Tue". Empty when
  // unknown. Composition happens in the widget, not here.
  final String supporting;

  // When the kind will next change (close time for open, open time for closed).
  // Used to sort groups by "closing soonest" / "opening soonest".
  final DateTime? nextChange;
}

class PlaceStatusCalculator {
  static const closingSoonThreshold = Duration(minutes: 60);

  static const _day = 24 * 60;
  static const _week = 7 * _day;

  // Backend uses Python/Django weekday convention: Mon=0..Sun=6. Flutter's
  // DateTime.weekday is Mon=1..Sun=7. One-line conversion isolates the
  // assumption if it turns out the backend ships ISO instead.
  static int _modelDayOfWeek(DateTime dt) => dt.weekday - 1;

  static PlaceStatus compute(
    Place place, {
    required DateTime now,
    bool use24HourFormat = false,
  }) {
    if (place.hours.isEmpty) {
      return const PlaceStatus(kind: PlaceStatusKind.unknown, supporting: '');
    }

    // Everything below is in wall-clock minutes from Monday 00:00 of this
    // week, so midnight, week wrap-around and DST changes need no special
    // cases.
    final spans = _weekSpans(place.hours);
    final nowMin = _modelDayOfWeek(now) * _day + now.hour * 60 + now.minute;

    if (_openAt(spans, nowMin)) {
      // Follow back-to-back and overlapping blocks to the real closing time.
      var closeMin = nowMin;
      while (closeMin < nowMin + _week) {
        final next = _openUntil(spans, closeMin);
        if (next == null) break;
        closeMin = next;
      }
      if (closeMin >= nowMin + _week) {
        return const PlaceStatus(
          kind: PlaceStatusKind.open,
          supporting: '24 hours',
        );
      }
      final remaining = closeMin - nowMin;
      final closeAt = _wallClockAfter(now, remaining);
      if (remaining <= closingSoonThreshold.inMinutes) {
        return PlaceStatus(
          kind: PlaceStatusKind.closingSoon,
          supporting: 'in $remaining min',
          nextChange: closeAt,
        );
      }
      return PlaceStatus(
        kind: PlaceStatusKind.open,
        supporting: 'until ${_fmtMin(closeMin, use24HourFormat)}',
        nextChange: closeAt,
      );
    }

    // Closed: the next opening is the earliest span starting after now. The
    // spans repeat weekly, so there always is one within a week.
    final openMin = spans
        .map((s) => s.startMin)
        .where((start) => start > nowMin)
        .reduce((a, b) => a < b ? a : b);
    final next = _wallClockAfter(now, openMin - nowMin);
    return PlaceStatus(
      kind: PlaceStatusKind.closed,
      supporting: 'opens ${_fmtFuture(next, now, use24HourFormat)}',
      nextChange: next,
    );
  }

  /// Each block as a span of week minutes. A block that closes at or before
  /// it opens runs past midnight. Each span is repeated a week earlier and
  /// later, so Sunday-night blocks cover early Monday and next week's
  /// openings are found.
  static List<_Span> _weekSpans(List<BusinessHours> hours) => [
    for (final h in hours)
      for (final shift in const [-_week, 0, _week])
        () {
          final open = _minutesOf(h.openTime);
          final close = _minutesOf(h.closeTime);
          final start = h.dayOfWeek * _day + open + shift;
          final length = close > open ? close - open : close - open + _day;
          return _Span(start, start + length);
        }(),
  ];

  static bool _openAt(List<_Span> spans, int minute) =>
      spans.any((s) => s.startMin <= minute && minute < s.endMin);

  /// The furthest end of any span open at [minute], or null if none is.
  static int? _openUntil(List<_Span> spans, int minute) {
    int? end;
    for (final s in spans) {
      if (s.startMin <= minute && minute < s.endMin) {
        if (end == null || s.endMin > end) end = s.endMin;
      }
    }
    return end;
  }

  static int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  /// The wall-clock time [minutes] after [now]. Built from calendar fields
  /// rather than by adding a Duration, so a DST change in between doesn't
  /// shift it by an hour.
  static DateTime _wallClockAfter(DateTime now, int minutes) =>
      DateTime(now.year, now.month, now.day, now.hour, now.minute + minutes);

  static String _fmtMin(int minutes, bool use24) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return _fmtClock(h, m, use24);
  }

  static String _fmtClock(int h, int m, bool use24) {
    if (use24) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final suffix = h < 12 ? 'am' : 'pm';
    if (m == 0) return '$hour12$suffix';
    return '$hour12:${m.toString().padLeft(2, '0')}$suffix';
  }

  static String _fmtFuture(DateTime when, DateTime now, bool use24) {
    // Calendar days in UTC, where every day is 24 hours long.
    final daysAhead = DateTime.utc(
      when.year,
      when.month,
      when.day,
    ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    final clock = _fmtClock(when.hour, when.minute, use24);
    if (daysAhead == 0) return clock;
    if (daysAhead == 1) return '$clock tomorrow';
    return '$clock ${_shortDay(when.weekday)}';
  }

  static String _shortDay(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];
}

class _Span {
  const _Span(this.startMin, this.endMin);
  final int startMin;
  final int endMin;
}
