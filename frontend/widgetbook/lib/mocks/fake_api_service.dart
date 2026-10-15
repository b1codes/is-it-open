import 'dart:async';

import 'package:frontend/models/place.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/api_service.dart';

import 'sample_data.dart';

/// In-memory stand-in for [ApiService] so screens render without a backend.
///
/// Mutations (bookmark, pin, visit length, ...) update the in-memory list, so
/// flows like "save place" or "add to today" behave end to end inside a use
/// case. Set [fail] to exercise error states, and a null [latency] to hold
/// loading states on screen indefinitely.
class FakeApiService extends ApiService {
  FakeApiService({
    List<SavedPlace>? bookmarks,
    User? user,
    this.latency = const Duration(milliseconds: 300),
    this.fail = false,
  }) : _bookmarks = [...(bookmarks ?? sampleSavedPlaces)],
       _user = user ?? demoUser;

  /// Delay before each response; null never responds.
  final Duration? latency;
  final bool fail;

  final List<SavedPlace> _bookmarks;
  User _user;
  int _nextId = 1000;

  Future<T> _respond<T>(T Function() body) async {
    final latency = this.latency;
    if (latency == null) {
      // No timer, so nothing is left pending when the scope is torn down.
      return Completer<T>().future;
    }
    await Future<void>.delayed(latency);
    if (fail) {
      throw Exception('Widgetbook: simulated network failure');
    }
    return body();
  }

  int _indexOf(String tomtomId) =>
      _bookmarks.indexWhere((sp) => sp.place.tomtomId == tomtomId);

  void _replace(
    String tomtomId,
    SavedPlace Function(SavedPlace current) update,
  ) {
    final index = _indexOf(tomtomId);
    if (index != -1) _bookmarks[index] = update(_bookmarks[index]);
  }

  @override
  Future<User> login(String username, String password) => _respond(() => _user);

  @override
  Future<User> register(String username, String password, {String? email}) =>
      _respond(
        () => _user = User(
          id: _user.id,
          username: username,
          email: email,
          token: _user.token,
        ),
      );

  @override
  Future<List<Place>> searchPlaces(String query) => _respond(() {
    final q = query.toLowerCase();
    return samplePlaces
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.address.toLowerCase().contains(q) ||
              p.categories.any((c) => c.toLowerCase().contains(q)),
        )
        .toList();
  });

  @override
  Future<List<Place>> getSuggestions(double? lat, double? lng) =>
      _respond(() => samplePlaces.take(3).toList());

  @override
  Future<List<Place>> getNearbyPlaces(
    double lat,
    double lng, {
    double radiusKm = 5.0,
  }) => _respond(() => samplePlaces);

  @override
  Future<Place> savePlace(Place place) => _respond(
    () => Place(
      id: _nextId++,
      tomtomId: place.tomtomId,
      name: place.name,
      address: place.address,
      location: place.location,
      phone: place.phone,
      website: place.website,
      categories: place.categories,
      hours: place.hours,
    ),
  );

  @override
  Future<void> bookmarkPlace(String tomtomId, {String? customName}) =>
      _respond(() {
        if (_indexOf(tomtomId) != -1) return;
        final place = samplePlaces.firstWhere(
          (p) => p.tomtomId == tomtomId,
          orElse: () => Place(
            tomtomId: tomtomId,
            name: customName ?? 'New place',
            address: 'Address pending',
            location: coffeePlace.location,
          ),
        );
        _bookmarks.add(
          SavedPlace(id: _nextId++, place: place, customName: customName),
        );
      });

  @override
  Future<void> deleteBookmark(String tomtomId) => _respond(
    () => _bookmarks.removeWhere((sp) => sp.place.tomtomId == tomtomId),
  );

  @override
  Future<List<SavedPlace>> getBookmarks() =>
      _respond(() => List.unmodifiable(_bookmarks));

  @override
  Future<User> getProfile() => _respond(() => _user);

  @override
  Future<User> updateProfile(User user) => _respond(() => _user = user);

  @override
  Future<void> togglePinPlace(String tomtomId, bool isPinned) =>
      _respond(() => _replace(tomtomId, (sp) => _copy(sp, isPinned: isPinned)));

  @override
  Future<void> toggleCheckItOut(String tomtomId, bool isCheckItOut) => _respond(
    () => _replace(tomtomId, (sp) => _copy(sp, isCheckItOut: isCheckItOut)),
  );

  @override
  Future<void> updateBookmarkGraphic(
    String tomtomId,
    String? icon,
    String? color, {
    String? customName,
  }) => _respond(
    // Mirrors the real endpoint: null fields are omitted from the PATCH and
    // left unchanged, while a blank custom name clears it.
    () => _replace(
      tomtomId,
      (sp) => _copy(
        sp,
        icon: icon ?? _keep,
        color: color ?? _keep,
        customName: customName == null
            ? _keep
            : (customName.trim().isEmpty ? null : customName),
      ),
    ),
  );

  @override
  Future<void> updateVisitLength(String tomtomId, int? visitLength) => _respond(
    () =>
        _replace(tomtomId, (sp) => _copy(sp, averageVisitLength: visitLength)),
  );

  @override
  Future<String> getCalendarFromUrl(String url) =>
      _respond(() => sampleIcs(DateTime.now()));

  /// Marks a nullable [_copy] argument as "leave unchanged", so an explicit
  /// null can clear the field (e.g. `updateVisitLength(id, null)`).
  static const Object _keep = Object();

  static SavedPlace _copy(
    SavedPlace sp, {
    Object? customName = _keep,
    Object? icon = _keep,
    Object? color = _keep,
    bool? isPinned,
    bool? isCheckItOut,
    Object? averageVisitLength = _keep,
  }) {
    return SavedPlace(
      id: sp.id,
      place: sp.place,
      customName: identical(customName, _keep)
          ? sp.customName
          : customName as String?,
      icon: identical(icon, _keep) ? sp.icon : icon as String?,
      color: identical(color, _keep) ? sp.color : color as String?,
      isPinned: isPinned ?? sp.isPinned,
      isCheckItOut: isCheckItOut ?? sp.isCheckItOut,
      averageVisitLength: identical(averageVisitLength, _keep)
          ? sp.averageVisitLength
          : averageVisitLength as int?,
    );
  }
}
