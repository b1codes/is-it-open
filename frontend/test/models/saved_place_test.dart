import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/saved_place.dart';

void main() {
  test('SavedPlace parses is_check_it_out from json', () {
    final json = {
      'id': 1,
      'place': {
        'id': 1,
        'tomtom_id': '123',
        'name': 'Test',
        'address': '123',
        'latitude': 0.0,
        'longitude': 0.0,
      },
      'is_pinned': false,
      'is_check_it_out': true,
    };
    
    final savedPlace = SavedPlace.fromJson(json);
    expect(savedPlace.isCheckItOut, true);
  });
}
