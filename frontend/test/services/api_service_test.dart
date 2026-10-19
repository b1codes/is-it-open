import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/api_service.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/fixtures.dart';

Map<String, dynamic> _placeJson(String tomtomId) => {
  'id': 1,
  'tomtom_id': tomtomId,
  'name': 'Place $tomtomId',
  'address': '1 Main St',
  'location': {'lat': 40.0, 'lng': -74.0},
  'categories': ['cafe'],
  'hours': [
    {'day_of_week': 0, 'open_time': '09:00', 'close_time': '17:00'},
  ],
};

Map<String, dynamic> _userJson({String? token = 'tok'}) => {
  'id': 1,
  'username': 'avery',
  'email': 'avery@example.com',
  'token': ?token,
};

void main() {
  late FakeHttpAdapter http;
  late ApiService api;
  DebugPrintCallback? originalDebugPrint;

  setUp(() {
    // Dio's LogInterceptor prints every request and response body.
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    http = FakeHttpAdapter();
    api = ApiService(httpClientAdapter: http);
  });

  tearDown(() => debugPrint = originalDebugPrint!);

  group('auth header', () {
    test('is absent until a token is set', () async {
      http.on('GET', '/places/bookmarks', const FakeResponse(200, []));
      await api.getBookmarks();
      expect(http.last.headers, isNot(contains('Authorization')));
    });

    test('carries the bearer token once set', () async {
      http.on('GET', '/places/bookmarks', const FakeResponse(200, []));
      api.setAuthToken('abc123');
      await api.getBookmarks();
      expect(http.last.headers['Authorization'], 'Bearer abc123');
    });

    test('is dropped again after the token is cleared', () async {
      http.on('GET', '/places/bookmarks', const FakeResponse(200, []));
      api.setAuthToken('abc123');
      api.setAuthToken(null);
      await api.getBookmarks();
      expect(http.last.headers, isNot(contains('Authorization')));
    });

    test('sends JSON', () async {
      http.on('POST', '/auth/login', FakeResponse(200, _userJson()));
      await api.login('avery', 'pw');
      expect(http.last.contentType, startsWith('application/json'));
    });
  });

  group('endpoints', () {
    test('login posts credentials and parses the user', () async {
      http.on('POST', '/auth/login', FakeResponse(200, _userJson()));
      final user = await api.login('avery', 'pw');
      expect(http.lastBody, {'username': 'avery', 'password': 'pw'});
      expect(user.username, 'avery');
      expect(user.token, 'tok');
    });

    test('register posts credentials and email', () async {
      http.on('POST', '/auth/register', FakeResponse(200, _userJson()));
      final user = await api.register('avery', 'pw', email: 'a@b.c');
      expect(http.lastBody, {
        'username': 'avery',
        'password': 'pw',
        'email': 'a@b.c',
      });
      expect(user.id, 1);
    });

    test('searchPlaces sends the query', () async {
      http.on(
        'GET',
        '/places/search',
        FakeResponse(200, [_placeJson('a'), _placeJson('b')]),
      );
      final places = await api.searchPlaces('coffee & tea');
      expect(http.last.queryParameters, {'query': 'coffee & tea'});
      expect(places.map((p) => p.tomtomId), ['a', 'b']);
      expect(places.first.hours, hasLength(1));
    });

    test('getSuggestions sends only the coordinates it has', () async {
      http.on('GET', '/places/suggestions', const FakeResponse(200, []));
      await api.getSuggestions(null, null);
      expect(http.last.queryParameters, isEmpty);
      await api.getSuggestions(1.5, null);
      expect(http.last.queryParameters, {'lat': 1.5});
      await api.getSuggestions(1.5, 2.5);
      expect(http.last.queryParameters, {'lat': 1.5, 'lng': 2.5});
    });

    test('getNearbyPlaces sends the radius', () async {
      http.on('GET', '/places/nearby', FakeResponse(200, [_placeJson('n')]));
      final places = await api.getNearbyPlaces(1, 2, radiusKm: 3);
      expect(http.last.queryParameters, {'lat': 1, 'lng': 2, 'radius_km': 3});
      expect(places.single.tomtomId, 'n');
      await api.getNearbyPlaces(1, 2);
      expect(http.last.queryParameters['radius_km'], 5.0);
    });

    test('savePlace posts the place JSON', () async {
      http.on('POST', '/places/', FakeResponse(201, _placeJson('tt_coffee')));
      final saved = await api.savePlace(coffeePlace);
      expect(http.lastBody, coffeePlace.toJson());
      expect(saved, isA<Place>());
    });

    test('bookmarkPlace omits a blank custom name', () async {
      http.on('POST', '/places/bookmark', const FakeResponse(200, {}));
      await api.bookmarkPlace('tt_1');
      expect(http.lastBody, {'tomtom_id': 'tt_1'});
      await api.bookmarkPlace('tt_1', customName: '');
      expect(http.lastBody, {'tomtom_id': 'tt_1'});
      await api.bookmarkPlace('tt_1', customName: 'Gym');
      expect(http.lastBody, {'tomtom_id': 'tt_1', 'custom_name': 'Gym'});
    });

    test('deleteBookmark deletes by tomtom id', () async {
      http.on('DELETE', '/places/bookmarks/tt_1', const FakeResponse(204));
      await api.deleteBookmark('tt_1');
      expect(http.last.method, 'DELETE');
    });

    test('getBookmarks parses saved places', () async {
      http.on(
        'GET',
        '/places/bookmarks',
        FakeResponse(200, [
          {'id': 5, 'place': _placeJson('a'), 'is_pinned': true},
        ]),
      );
      final bookmarks = await api.getBookmarks();
      expect(bookmarks.single, isA<SavedPlace>());
      expect(bookmarks.single.isPinned, isTrue);
    });

    test('getProfile and updateProfile use /auth/me', () async {
      http.on('GET', '/auth/me', FakeResponse(200, _userJson()));
      http.on('PUT', '/auth/me', FakeResponse(200, _userJson()));
      expect((await api.getProfile()).username, 'avery');
      final updated = await api.updateProfile(demoUser);
      expect(http.lastBody, demoUser.toJson());
      expect(updated, isA<User>());
    });

    test('bookmark PATCH endpoints send their fields', () async {
      http.on('PATCH', '/places/bookmarks/tt_1/pin', const FakeResponse(200));
      http.on(
        'PATCH',
        '/places/bookmarks/tt_1/check-it-out',
        const FakeResponse(200),
      );
      http.on(
        'PATCH',
        '/places/bookmarks/tt_1/visit-length',
        const FakeResponse(200),
      );
      await api.togglePinPlace('tt_1', true);
      expect(http.lastBody, {'is_pinned': true});
      await api.toggleCheckItOut('tt_1', false);
      expect(http.lastBody, {'is_check_it_out': false});
      await api.updateVisitLength('tt_1', null);
      expect(http.lastBody, {'visit_length': null});
      await api.updateVisitLength('tt_1', 30);
      expect(http.lastBody, {'visit_length': 30});
    });

    test('updateBookmarkGraphic sends only the fields given', () async {
      http.on(
        'PATCH',
        '/places/bookmarks/tt_1/graphic',
        const FakeResponse(200),
      );
      await api.updateBookmarkGraphic('tt_1', null, null);
      expect(http.lastBody, isEmpty);
      await api.updateBookmarkGraphic('tt_1', 'star', 'ff000000');
      expect(http.lastBody, {'icon': 'star', 'color': 'ff000000'});
      await api.updateBookmarkGraphic('tt_1', null, null, customName: '');
      expect(http.lastBody, {'custom_name': ''});
    });

    test('getCalendarFromUrl proxies the URL and returns the body', () async {
      http.on(
        'GET',
        '/calendar/proxy',
        const FakeResponse(200, 'BEGIN:VCALENDAR\r\nEND:VCALENDAR'),
      );
      final ics = await api.getCalendarFromUrl('https://cal.example/a.ics');
      expect(http.last.queryParameters, {'url': 'https://cal.example/a.ics'});
      expect(ics, startsWith('BEGIN:VCALENDAR'));
    });
  });

  group('error mapping', () {
    test('includes the server detail where the endpoint reports it', () async {
      http.on(
        'POST',
        '/auth/login',
        const FakeResponse(401, {'detail': 'Invalid credentials'}),
      );
      final error = await _error(() => api.login('a', 'b'));
      expect(error.statusCode, 401);
      expect(error.isUnauthorized, isTrue);
      expect(error.toString(), startsWith('Exception: Failed to login: '));
      expect(error.toString(), contains('Invalid credentials'));
    });

    test('uses Dio\'s message for search errors', () async {
      http.on('GET', '/places/search', const FakeResponse(500, {'x': 'y'}));
      final error = await _error(() => api.searchPlaces('q'));
      expect(error.statusCode, 500);
      expect(error.isUnauthorized, isFalse);
      expect(error.message, startsWith('Failed to search places: '));
      expect(error.message, isNot(contains('{x: y}')));
    });

    test('reports no status when the request never got a response', () async {
      http.on(
        'GET',
        '/auth/me',
        const FakeResponse.error(DioExceptionType.connectionTimeout),
      );
      final error = await _error(api.getProfile);
      expect(error.statusCode, isNull);
      expect(error.isUnauthorized, isFalse);
      expect(error.message, contains('connectionTimeout'));
    });

    test('an expired token surfaces as unauthorized', () async {
      http.on(
        'GET',
        '/places/bookmarks',
        const FakeResponse(401, {'detail': 'Unauthorized'}),
      );
      api.setAuthToken('expired');
      final error = await _error(api.getBookmarks);
      expect(error.isUnauthorized, isTrue);
    });

    // Every call maps a failure to an ApiException with its own prefix.
    final calls = <String, Future<Object?> Function(ApiService)>{
      'Failed to register': (a) => a.register('u', 'p'),
      'Failed to get suggestions': (a) => a.getSuggestions(1, 2),
      'Failed to get nearby places': (a) => a.getNearbyPlaces(1, 2),
      'Failed to save place': (a) => a.savePlace(coffeePlace),
      'Failed to bookmark place': (a) => a.bookmarkPlace('x'),
      'Failed to delete bookmark': (a) => a.deleteBookmark('x'),
      'Failed to get bookmarks': (a) => a.getBookmarks(),
      'Failed to get profile': (a) => a.getProfile(),
      'Failed to update profile': (a) => a.updateProfile(demoUser),
      'Failed to toggle pin for place': (a) => a.togglePinPlace('x', true),
      'Failed to toggle check-it-out for place': (a) =>
          a.toggleCheckItOut('x', true),
      'Failed to update graphic': (a) => a.updateBookmarkGraphic('x', 'a', 'b'),
      'Failed to update visit length': (a) => a.updateVisitLength('x', 1),
      'Failed to fetch remote calendar': (a) => a.getCalendarFromUrl('u'),
    };
    for (final MapEntry(key: prefix, value: call) in calls.entries) {
      test('maps failures: $prefix', () async {
        // Nothing is routed, so every request gets the adapter's 404.
        final error = await _error(() => call(api));
        expect(error.message, startsWith('$prefix: '));
        expect(error.statusCode, 404);
      });
    }
  });
}

Future<ApiException> _error(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('Expected an ApiException');
}
