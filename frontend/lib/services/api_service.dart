import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/env_config.dart';
import '../models/place.dart';
import '../models/user.dart';
import '../models/saved_place.dart';

/// A failed API call. [toString] reads like the plain `Exception` this used
/// to be ("Exception: Failed to login: ..."), since screens show it as is.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  /// Wraps [e] as `[action]: detail`. The detail is the response body when
  /// there is one and [includeBody] is set, otherwise Dio's message.
  factory ApiException.from(
    String action,
    DioException e, {
    bool includeBody = true,
  }) {
    final detail = includeBody ? (e.response?.data ?? e.message) : e.message;
    return ApiException('$action: $detail', statusCode: e.response?.statusCode);
  }

  final String message;

  /// The HTTP status, or null when no response arrived (offline, timeout).
  final int? statusCode;

  /// The server rejected the credentials: the token expired or was revoked.
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'Exception: $message';
}

class ApiService {
  late final Dio _dio;
  String? _authToken;

  /// [httpClientAdapter] replaces Dio's transport, so tests can serve
  /// canned responses while the real interceptors and error mapping run.
  ApiService({@visibleForTesting HttpClientAdapter? httpClientAdapter}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: EnvConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 3),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    if (httpClientAdapter != null) _dio.httpClientAdapter = httpClientAdapter;

    // Add interceptors for logging and auth
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_authToken != null) {
            options.headers['Authorization'] = 'Bearer $_authToken';
          }
          return handler.next(options);
        },
      ),
    );

    _dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (object) => debugPrint(object.toString()),
      ),
    );
  }

  void setAuthToken(String? token) {
    _authToken = token;
  }

  Future<User> login(String username, String password) async {
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {'username': username, 'password': password},
      );
      return User.fromJson(response.data);
    } on DioException catch (e) {
      throw ApiException.from('Failed to login', e);
    }
  }

  Future<User> register(
    String username,
    String password, {
    String? email,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/register',
        data: {'username': username, 'password': password, 'email': email},
      );
      return User.fromJson(response.data);
    } on DioException catch (e) {
      throw ApiException.from('Failed to register', e);
    }
  }

  Future<List<Place>> searchPlaces(String query) async {
    try {
      final response = await _dio.get(
        '/places/search',
        queryParameters: {'query': query},
      );
      final List<dynamic> data = response.data;
      return data.map((json) => Place.fromJson(json)).toList();
    } on DioException catch (e) {
      throw ApiException.from('Failed to search places', e, includeBody: false);
    }
  }

  Future<List<Place>> getSuggestions(double? lat, double? lng) async {
    try {
      final queryParams = <String, dynamic>{};
      if (lat != null) queryParams['lat'] = lat;
      if (lng != null) queryParams['lng'] = lng;

      final response = await _dio.get(
        '/places/suggestions',
        queryParameters: queryParams,
      );
      final List<dynamic> data = response.data;
      return data.map((json) => Place.fromJson(json)).toList();
    } on DioException catch (e) {
      throw ApiException.from(
        'Failed to get suggestions',
        e,
        includeBody: false,
      );
    }
  }

  Future<List<Place>> getNearbyPlaces(
    double lat,
    double lng, {
    double radiusKm = 5.0,
  }) async {
    try {
      final response = await _dio.get(
        '/places/nearby',
        queryParameters: {'lat': lat, 'lng': lng, 'radius_km': radiusKm},
      );
      final List<dynamic> data = response.data;
      return data.map((json) => Place.fromJson(json)).toList();
    } on DioException catch (e) {
      throw ApiException.from(
        'Failed to get nearby places',
        e,
        includeBody: false,
      );
    }
  }

  Future<Place> savePlace(Place place) async {
    try {
      final response = await _dio.post('/places/', data: place.toJson());
      return Place.fromJson(response.data);
    } on DioException catch (e) {
      throw ApiException.from('Failed to save place', e, includeBody: false);
    }
  }

  Future<void> bookmarkPlace(String tomtomId, {String? customName}) async {
    try {
      final Map<String, dynamic> data = {'tomtom_id': tomtomId};
      if (customName != null && customName.isNotEmpty) {
        data['custom_name'] = customName;
      }
      await _dio.post('/places/bookmark', data: data);
    } on DioException catch (e) {
      throw ApiException.from('Failed to bookmark place', e);
    }
  }

  Future<void> deleteBookmark(String tomtomId) async {
    try {
      await _dio.delete('/places/bookmarks/$tomtomId');
    } on DioException catch (e) {
      throw ApiException.from('Failed to delete bookmark', e);
    }
  }

  Future<List<SavedPlace>> getBookmarks() async {
    try {
      final response = await _dio.get('/places/bookmarks');
      final List<dynamic> data = response.data;
      return data.map((json) => SavedPlace.fromJson(json)).toList();
    } on DioException catch (e) {
      throw ApiException.from('Failed to get bookmarks', e);
    }
  }

  Future<User> getProfile() async {
    try {
      final response = await _dio.get('/auth/me');
      return User.fromJson(response.data);
    } on DioException catch (e) {
      throw ApiException.from('Failed to get profile', e);
    }
  }

  Future<User> updateProfile(User user) async {
    try {
      final response = await _dio.put('/auth/me', data: user.toJson());
      return User.fromJson(response.data);
    } on DioException catch (e) {
      throw ApiException.from('Failed to update profile', e);
    }
  }

  Future<void> togglePinPlace(String tomtomId, bool isPinned) async {
    try {
      await _dio.patch(
        '/places/bookmarks/$tomtomId/pin',
        data: {'is_pinned': isPinned},
      );
    } on DioException catch (e) {
      throw ApiException.from('Failed to toggle pin for place', e);
    }
  }

  Future<void> toggleCheckItOut(String tomtomId, bool isCheckItOut) async {
    try {
      await _dio.patch(
        '/places/bookmarks/$tomtomId/check-it-out',
        data: {'is_check_it_out': isCheckItOut},
      );
    } on DioException catch (e) {
      throw ApiException.from('Failed to toggle check-it-out for place', e);
    }
  }

  Future<void> updateBookmarkGraphic(
    String tomtomId,
    String? icon,
    String? color, {
    String? customName,
  }) async {
    try {
      final Map<String, dynamic> data = {};
      if (icon != null) data['icon'] = icon;
      if (color != null) data['color'] = color;
      if (customName != null) data['custom_name'] = customName;

      await _dio.patch('/places/bookmarks/$tomtomId/graphic', data: data);
    } on DioException catch (e) {
      throw ApiException.from('Failed to update graphic', e);
    }
  }

  Future<void> updateVisitLength(String tomtomId, int? visitLength) async {
    try {
      await _dio.patch(
        '/places/bookmarks/$tomtomId/visit-length',
        data: {'visit_length': visitLength},
      );
    } on DioException catch (e) {
      throw ApiException.from('Failed to update visit length', e);
    }
  }

  Future<String> getCalendarFromUrl(String url) async {
    try {
      final response = await _dio.get(
        '/calendar/proxy',
        queryParameters: {'url': url},
      );
      return response.data.toString();
    } on DioException catch (e) {
      throw ApiException.from('Failed to fetch remote calendar', e);
    }
  }
}
