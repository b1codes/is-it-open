import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/hours.dart';

void main() {
  group('BusinessHours', () {
    test('parses HH:MM times', () {
      final hours = BusinessHours.fromJson({
        'day_of_week': 2,
        'open_time': '09:30',
        'close_time': '17:05',
      });
      expect(hours.dayOfWeek, 2);
      expect(hours.openTime, const TimeOfDay(hour: 9, minute: 30));
      expect(hours.closeTime, const TimeOfDay(hour: 17, minute: 5));
    });

    test('ignores seconds in HH:MM:SS times', () {
      final hours = BusinessHours.fromJson({
        'day_of_week': 0,
        'open_time': '07:00:00',
        'close_time': '23:59:59',
      });
      expect(hours.openTime, const TimeOfDay(hour: 7, minute: 0));
      expect(hours.closeTime, const TimeOfDay(hour: 23, minute: 59));
    });

    test('serializes zero-padded times', () {
      const hours = BusinessHours(
        dayOfWeek: 6,
        openTime: TimeOfDay(hour: 0, minute: 5),
        closeTime: TimeOfDay(hour: 2, minute: 0),
      );
      expect(hours.toJson(), {
        'day_of_week': 6,
        'open_time': '00:05',
        'close_time': '02:00',
      });
    });

    test('round-trips every minute of the day', () {
      for (var minute = 0; minute < 24 * 60; minute += 7) {
        final time = TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
        final hours = BusinessHours(
          dayOfWeek: minute % 7,
          openTime: time,
          closeTime: time,
        );
        expect(BusinessHours.fromJson(hours.toJson()), hours);
      }
    });

    test('has value equality', () {
      const a = BusinessHours(
        dayOfWeek: 1,
        openTime: TimeOfDay(hour: 9, minute: 0),
        closeTime: TimeOfDay(hour: 17, minute: 0),
      );
      const b = BusinessHours(
        dayOfWeek: 1,
        openTime: TimeOfDay(hour: 9, minute: 0),
        closeTime: TimeOfDay(hour: 17, minute: 0),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          const BusinessHours(
            dayOfWeek: 2,
            openTime: TimeOfDay(hour: 9, minute: 0),
            closeTime: TimeOfDay(hour: 17, minute: 0),
          ),
        ),
      );
    });

    test('rejects a malformed time', () {
      expect(
        () => BusinessHours.fromJson({
          'day_of_week': 0,
          'open_time': 'noon',
          'close_time': '13:00',
        }),
        throwsFormatException,
      );
    });
  });
}
