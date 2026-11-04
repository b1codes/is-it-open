import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/user.dart';

import '../helpers/fixtures.dart';

void main() {
  group('User', () {
    test('round-trips every field through JSON', () {
      final copy = User.fromJson(demoUser.toJson());
      expect(copy.toJson(), demoUser.toJson());
      expect(copy.homeCity, 'New York');
      expect(copy.workZip, '10007');
      expect(copy.calendarSubscriptionUrl, demoUser.calendarSubscriptionUrl);
    });

    test('defaults optional fields for a minimal payload', () {
      final user = User.fromJson({'id': 3, 'username': 'min'});
      expect(user.id, 3);
      expect(user.username, 'min');
      expect(user.email, isNull);
      expect(user.homeLat, isNull);
      expect(user.useCurrentLocation, isFalse);
      expect(user.token, isNull);
    });

    test('accepts integer coordinates', () {
      final user = User.fromJson({
        'id': 1,
        'username': 'u',
        'home_lat': 40,
        'home_lng': -74,
        'work_lat': 41,
        'work_lng': -73,
      });
      expect(user.homeLat, 40.0);
      expect(user.homeLng, -74.0);
      expect(user.workLat, 41.0);
      expect(user.workLng, -73.0);
    });

    test('serializes use_current_location and the token', () {
      final json = User(
        id: 1,
        username: 'u',
        useCurrentLocation: true,
        token: 'abc',
      ).toJson();
      expect(json['use_current_location'], isTrue);
      expect(json['token'], 'abc');
    });
  });
}
