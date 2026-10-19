import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/hours.dart';
import 'package:frontend/models/place.dart';
import 'package:latlong2/latlong.dart';

import '../helpers/fixtures.dart';

void main() {
  group('Place', () {
    test('parses a full API payload', () {
      final place = Place.fromJson({
        'id': 7,
        'tomtom_id': 'tt_1',
        'name': 'Cafe',
        'address': '1 Main St',
        'location': {'lat': 40.5, 'lng': -73.25},
        'phone': '+1 555',
        'website': 'https://cafe.example',
        'categories': ['cafe', 'bakery'],
        'hours': [
          {'day_of_week': 0, 'open_time': '08:00', 'close_time': '16:00'},
        ],
      });
      expect(place.id, 7);
      expect(place.tomtomId, 'tt_1');
      expect(place.location, const LatLng(40.5, -73.25));
      expect(place.phone, '+1 555');
      expect(place.website, 'https://cafe.example');
      expect(place.categories, ['cafe', 'bakery']);
      expect(place.hours, [
        const BusinessHours(
          dayOfWeek: 0,
          openTime: TimeOfDay(hour: 8, minute: 0),
          closeTime: TimeOfDay(hour: 16, minute: 0),
        ),
      ]);
    });

    test('accepts integer coordinates', () {
      final place = Place.fromJson({
        'tomtom_id': 'tt_1',
        'name': 'Origin',
        'address': '',
        'location': {'lat': 0, 'lng': 1},
      });
      expect(place.location, const LatLng(0, 1));
    });

    test('defaults missing optional fields', () {
      final place = Place.fromJson({
        'tomtom_id': 'tt_1',
        'name': 'Bare',
        'address': 'Somewhere',
        'location': {'lat': 1.0, 'lng': 2.0},
      });
      expect(place.id, isNull);
      expect(place.phone, isNull);
      expect(place.website, isNull);
      expect(place.categories, isEmpty);
      expect(place.hours, isEmpty);
    });

    test('falls back to the numeric id when tomtom_id is missing', () {
      final place = Place.fromJson({
        'id': 42,
        'name': 'Custom',
        'address': 'Here',
        'location': {'lat': 1.0, 'lng': 2.0},
      });
      expect(place.tomtomId, '42');
    });

    test('stringifies non-string categories', () {
      final place = Place.fromJson({
        'tomtom_id': 'tt_1',
        'name': 'Mixed',
        'address': '',
        'location': {'lat': 1.0, 'lng': 2.0},
        'categories': [7311, 'shop'],
      });
      expect(place.categories, ['7311', 'shop']);
    });

    test('round-trips every fixture place through JSON', () {
      for (final place in samplePlaces) {
        expect(Place.fromJson(place.toJson()), place, reason: place.name);
      }
    });

    test('equality compares coordinates by value', () {
      final a = Place(
        tomtomId: 'x',
        name: 'A',
        address: '',
        location: const LatLng(1, 2),
      );
      final b = Place(
        tomtomId: 'x',
        name: 'A',
        address: '',
        location: LatLng(1, 2),
      );
      expect(a, b);
      expect(
        a,
        isNot(
          Place(
            tomtomId: 'x',
            name: 'A',
            address: '',
            location: const LatLng(1, 2.0001),
          ),
        ),
      );
    });
  });
}
