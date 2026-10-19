// Consumer verification: the app's API client and models agree with the
// backend's contract (contracts/openapi.json, see contracts/README.md).
//
// Every ApiService method runs against ContractAdapter, which checks each
// request against the contract and answers with responses generated from it.
// So these fail when the backend renames, removes, retypes or makes nullable a
// field the models read, or stops accepting what the app sends.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/hours.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/api_service.dart';
import 'package:latlong2/latlong.dart';

import 'openapi_contract.dart';

final _place = Place(
  id: 7,
  tomtomId: 'tt-1',
  name: "Joe's Pizza",
  address: '7 Carmine St',
  location: const LatLng(40.7306, -74.0021),
  phone: '+1 212-366-1182',
  website: 'https://joespizzanyc.com',
  categories: const ['Pizza'],
  hours: const [
    BusinessHours(
      dayOfWeek: 0,
      openTime: TimeOfDay(hour: 10, minute: 0),
      closeTime: TimeOfDay(hour: 23, minute: 30),
    ),
  ],
);

final _user = User(
  id: 1,
  username: 'avery',
  email: 'avery@example.com',
  firstName: 'Avery',
  lastName: 'Lee',
  homeAddress: '1 Main St, Springfield',
  homeStreet: '1 Main St',
  homeCity: 'Springfield',
  homeState: 'IL',
  homeZip: '62701',
  homeLat: 39.78,
  homeLng: -89.65,
  workAddress: '',
  useCurrentLocation: true,
  calendarSubscriptionUrl: 'https://example.com/cal.ics',
  token: 'tok',
);

/// One ApiService call per way the app uses each operation.
final _calls = <(String, String, Future<Object?> Function(ApiService))>[
  ('POST /api/auth/login', 'login', (api) => api.login('avery', 'pw')),
  (
    'POST /api/auth/register',
    'register',
    (api) => api.register('avery', 'pw', email: 'avery@example.com'),
  ),
  (
    'POST /api/auth/register',
    'register without an email',
    (api) => api.register('avery', 'pw'),
  ),
  ('GET /api/auth/me', 'getProfile', (api) => api.getProfile()),
  ('PUT /api/auth/me', 'updateProfile', (api) => api.updateProfile(_user)),
  (
    'PUT /api/auth/me',
    'updateProfile with only an id and username',
    (api) => api.updateProfile(User(id: 1, username: 'avery')),
  ),
  (
    'GET /api/places/search',
    'searchPlaces',
    (api) => api.searchPlaces('pizza'),
  ),
  (
    'GET /api/places/suggestions',
    'getSuggestions near a location',
    (api) => api.getSuggestions(40.73, -74.0),
  ),
  (
    'GET /api/places/suggestions',
    'getSuggestions without a location',
    (api) => api.getSuggestions(null, null),
  ),
  (
    'GET /api/places/nearby',
    'getNearbyPlaces',
    (api) => api.getNearbyPlaces(40.73, -74.0, radiusKm: 2.5),
  ),
  ('POST /api/places/', 'savePlace', (api) => api.savePlace(_place)),
  (
    'POST /api/places/bookmark',
    'bookmarkPlace',
    (api) => api.bookmarkPlace('tt-1', customName: 'Fave'),
  ),
  ('GET /api/places/bookmarks', 'getBookmarks', (api) => api.getBookmarks()),
  (
    'DELETE /api/places/bookmarks/{tomtom_id}',
    'deleteBookmark',
    (api) => api.deleteBookmark('tt-1'),
  ),
  (
    'PATCH /api/places/bookmarks/{tomtom_id}/pin',
    'togglePinPlace',
    (api) => api.togglePinPlace('tt-1', true),
  ),
  (
    'PATCH /api/places/bookmarks/{tomtom_id}/check-it-out',
    'toggleCheckItOut',
    (api) => api.toggleCheckItOut('tt-1', false),
  ),
  (
    'PATCH /api/places/bookmarks/{tomtom_id}/graphic',
    'updateBookmarkGraphic',
    (api) => api.updateBookmarkGraphic(
      'tt-1',
      'star',
      '#FF0000',
      customName: 'Fave',
    ),
  ),
  (
    'PATCH /api/places/bookmarks/{tomtom_id}/graphic',
    'updateBookmarkGraphic with nothing to change',
    (api) => api.updateBookmarkGraphic('tt-1', null, null),
  ),
  (
    'PATCH /api/places/bookmarks/{tomtom_id}/visit-length',
    'updateVisitLength',
    (api) => api.updateVisitLength('tt-1', 240),
  ),
  (
    'PATCH /api/places/bookmarks/{tomtom_id}/visit-length',
    'updateVisitLength clearing it',
    (api) => api.updateVisitLength('tt-1', null),
  ),
  (
    'GET /api/calendar/proxy',
    'getCalendarFromUrl',
    (api) => api.getCalendarFromUrl('https://example.com/cal.ics'),
  ),
];

/// Operations in the contract that the app doesn't call, and why.
const _notUsedByTheApp = {
  // Place details come with search results and bookmarks.
  'GET /api/places/{tomtom_id}',
};

/// Body fields the app sends that the contract doesn't define. The backend
/// ignores them; anything else unknown is likely a misspelled field.
const _ignoredFields = {
  // Place.toJson includes the server-assigned id.
  'POST /api/places/': {'id'},
  // User.toJson is the whole user, not just the editable profile fields.
  'PUT /api/auth/me': {'id', 'username', 'email', 'token'},
};

/// [model] (a model's toJson, or a list of them) has every value of the
/// response [body] it was parsed from, so no field was dropped or misread.
void _expectParsedFrom(Object? model, Object? body, [String at = r'$']) {
  if (body is Map) {
    expect(model, isA<Map>(), reason: at);
    for (final MapEntry(:key, :value) in body.entries) {
      _expectParsedFrom((model as Map)[key], value, '$at.$key');
    }
  } else if (body is List) {
    expect(model, isA<List>(), reason: at);
    expect((model as List).length, body.length, reason: at);
    for (var i = 0; i < body.length; i++) {
      _expectParsedFrom(model[i], body[i], '$at[$i]');
    }
  } else {
    expect(model, body, reason: at);
  }
}

Object? _toJson(Object? result) => switch (result) {
  Place() => result.toJson(),
  SavedPlace() => result.toJson(),
  User() => result.toJson(),
  List() => result.map(_toJson).toList(),
  _ => result,
};

void main() {
  final contract = OpenApiContract.load();
  late ContractAdapter backend;
  late ApiService api;
  DebugPrintCallback? originalDebugPrint;

  setUp(() {
    // Dio's LogInterceptor prints every request and response body.
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    backend = ContractAdapter(contract, allowUnknownFields: _ignoredFields);
    api = ApiService(httpClientAdapter: backend)..setAuthToken('tok');
  });

  tearDown(() => debugPrint = originalDebugPrint!);

  for (final (label, name, call) in _calls) {
    group('$name ($label)', () {
      for (final full in [true, false]) {
        final shape = full
            ? 'every response field set'
            : 'only required response fields, nullable ones null';

        test('sends what the contract accepts and reads $shape', () async {
          backend.full = full;

          final result = await call(api);

          expect(backend.violations, isEmpty);
          expect(backend.called, {label});
          // Methods returning void ignore the response body by design.
          if (full && result != null) {
            _expectParsedFrom(_toJson(result), backend.lastBody);
          }
        });
      }

      final operation = contract.operations.firstWhere((o) => o.label == label);
      for (final status in operation.errorStatuses) {
        test('turns a documented $status into an ApiException', () async {
          backend.status = status;

          await expectLater(
            call(api),
            throwsA(
              isA<ApiException>()
                  .having((e) => e.statusCode, 'statusCode', status)
                  .having(
                    (e) => e.isUnauthorized,
                    'isUnauthorized',
                    status == 401,
                  ),
            ),
          );
          expect(backend.violations, isEmpty);
        });
      }
    });
  }

  test(
    'every operation in the contract is used by the app or listed as unused',
    () {
      final used = {for (final (label, _, _) in _calls) label};
      final all = {for (final o in contract.operations) o.label};

      expect(
        used.difference(all),
        isEmpty,
        reason: 'calls to operations the contract lacks',
      );
      expect(
        all.difference(used),
        _notUsedByTheApp,
        reason: 'add a call above, or list the operation in _notUsedByTheApp',
      );
    },
  );

  group('ContractAdapter', () {
    test('reports a request the contract has no route for', () async {
      await expectLater(api.searchPlaces('x').then((_) {}), completes);
      backend.violations.clear();

      try {
        await api.deleteBookmark('a/b');
      } on ApiException {
        // Unrouted, so a 404.
      }

      expect(backend.violations.single, contains('not in the contract'));
    });

    test('reports a body field the contract lacks', () async {
      final strict = ContractAdapter(contract);
      await ApiService(httpClientAdapter: strict).updateProfile(_user);

      expect(
        strict.violations,
        containsAll([contains('body.token: not in the contract')]),
      );
    });

    test('reports a missing bearer token', () async {
      api.setAuthToken(null);

      await api.getBookmarks();

      expect(backend.violations.single, contains('needs a bearer token'));
    });

    test('reports a query value the contract rejects', () async {
      await api.getNearbyPlaces(91, 0);

      expect(backend.violations.single, contains('?lat: 91.0 is above 90'));
    });
  });
}
