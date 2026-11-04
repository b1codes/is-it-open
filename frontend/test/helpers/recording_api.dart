import 'package:frontend/models/place.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/models/user.dart';

import 'fixtures.dart';

/// [FakeApiService] that records each request it receives, with its
/// arguments, so a test can check what reached the backend and how often.
class RecordingApi extends FakeApiService {
  RecordingApi({super.latency = Duration.zero, super.fail, super.bookmarks});

  final List<(String, List<Object?>)> requests = [];

  /// How many times [method] was called.
  int count(String method) => requests.where((r) => r.$1 == method).length;

  /// The arguments of the last call to [method].
  List<Object?> last(String method) =>
      requests.lastWhere((r) => r.$1 == method).$2;

  void _record(String method, [List<Object?> args = const []]) =>
      requests.add((method, args));

  @override
  Future<User> login(String username, String password) {
    _record('login', [username, password]);
    return super.login(username, password);
  }

  @override
  Future<User> register(String username, String password, {String? email}) {
    _record('register', [username, password, email]);
    return super.register(username, password, email: email);
  }

  @override
  Future<List<Place>> searchPlaces(String query) {
    _record('searchPlaces', [query]);
    return super.searchPlaces(query);
  }

  @override
  Future<Place> savePlace(Place place) {
    _record('savePlace', [place]);
    return super.savePlace(place);
  }

  @override
  Future<void> bookmarkPlace(String tomtomId, {String? customName}) {
    _record('bookmarkPlace', [tomtomId, customName]);
    return super.bookmarkPlace(tomtomId, customName: customName);
  }

  @override
  Future<void> deleteBookmark(String tomtomId) {
    _record('deleteBookmark', [tomtomId]);
    return super.deleteBookmark(tomtomId);
  }

  @override
  Future<List<SavedPlace>> getBookmarks() {
    _record('getBookmarks');
    return super.getBookmarks();
  }

  @override
  Future<User> updateProfileFields(Map<String, dynamic> fields) {
    _record('updateProfileFields', [fields]);
    return super.updateProfileFields(fields);
  }

  @override
  Future<void> updateVisitLength(String tomtomId, int? visitLength) {
    _record('updateVisitLength', [tomtomId, visitLength]);
    return super.updateVisitLength(tomtomId, visitLength);
  }
}
