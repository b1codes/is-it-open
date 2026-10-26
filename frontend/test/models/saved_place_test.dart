import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/saved_place.dart';

import '../helpers/fixtures.dart';

Map<String, dynamic> _placeJson() => {
  'id': 1,
  'tomtom_id': '123',
  'name': 'Test',
  'address': '123',
  'location': {'lat': 0.0, 'lng': 0.0},
};

void main() {
  group('SavedPlace', () {
    test('parses every field', () {
      final saved = SavedPlace.fromJson({
        'id': 9,
        'place': _placeJson(),
        'custom_name': 'Office',
        'icon': 'work',
        'color': 'ff112233',
        'is_pinned': true,
        'is_check_it_out': true,
        'average_visit_length': 45,
      });
      expect(saved.id, 9);
      expect(saved.place.tomtomId, '123');
      expect(saved.customName, 'Office');
      expect(saved.icon, 'work');
      expect(saved.color, 'ff112233');
      expect(saved.isPinned, isTrue);
      expect(saved.isCheckItOut, isTrue);
      expect(saved.averageVisitLength, 45);
    });

    test('defaults flags and optional fields', () {
      final saved = SavedPlace.fromJson({'id': 1, 'place': _placeJson()});
      expect(saved.customName, isNull);
      expect(saved.icon, isNull);
      expect(saved.color, isNull);
      expect(saved.isPinned, isFalse);
      expect(saved.isCheckItOut, isFalse);
      expect(saved.averageVisitLength, isNull);
    });

    test('treats null flags as false', () {
      final saved = SavedPlace.fromJson({
        'id': 1,
        'place': _placeJson(),
        'is_pinned': null,
        'is_check_it_out': null,
      });
      expect(saved.isPinned, isFalse);
      expect(saved.isCheckItOut, isFalse);
    });

    test('round-trips every fixture through JSON', () {
      for (final saved in sampleSavedPlaces) {
        final copy = SavedPlace.fromJson(saved.toJson());
        expect(copy.toJson(), saved.toJson());
        expect(copy.place, saved.place);
      }
    });
  });
}
