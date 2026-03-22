import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb and debugPrint
import 'dart:io'; // For Platform check
import '../models/place.dart';
import '../models/user.dart';
import '../models/saved_place.dart';

class ApiService {
  late final Dio _dio;
  String? _authToken;

  ApiService() {
    // Determine Base URL based on platform
    String baseUrl;
    if (kIsWeb) {
      // Web runs on the same machine as the server
      baseUrl = 'http://127.0.0.1:8000/api';
    } else if (Platform.isAndroid) {
      // Android emulator uses 10.0.2.2 to reach host machine
      baseUrl = 'http://10.0.2.2:8000/api';
    } else if (Platform.isIOS) {
      // Physical iOS device needs the Mac's local network IP
      // Simulator can use 127.0.0.1 but the local IP works for both
      baseUrl = 'http://192.168.1.168:8000/api';
    } else {
      // macOS desktop
      baseUrl = 'http://127.0.0.1:8000/api';
    }

    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 3),
        headers: {'Content-Type': 'application/json'},
      ),
    );

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
      throw Exception('Failed to login: ${e.response?.data ?? e.message}');
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
      throw Exception('Failed to register: ${e.response?.data ?? e.message}');
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
      throw Exception('Failed to search places: ${e.message}');
    }
  }

  Future<Place> savePlace(Place place) async {
    try {
      final response = await _dio.post('/places/', data: place.toJson());
      return Place.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception('Failed to save place: ${e.message}');
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
      throw Exception(
        'Failed to bookmark place: ${e.response?.data ?? e.message}',
      );
    }
  }

  Future<void> deleteBookmark(String tomtomId) async {
    try {
      await _dio.delete('/places/bookmarks/$tomtomId');
    } on DioException catch (e) {
      throw Exception(
        'Failed to delete bookmark: ${e.response?.data ?? e.message}',
      );
    }
  }

  Future<List<SavedPlace>> getBookmarks() async {
    try {
      final response = await _dio.get('/places/bookmarks');
      final List<dynamic> data = response.data;
      return data.map((json) => SavedPlace.fromJson(json)).toList();
    } on DioException catch (e) {
      throw Exception(
        'Failed to get bookmarks: ${e.response?.data ?? e.message}',
      );
    }
  }

  Future<User> getProfile() async {
    try {
      final response = await _dio.get('/auth/me');
      return User.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(
        'Failed to get profile: ${e.response?.data ?? e.message}',
      );
    }
  }

  Future<User> updateProfile(User user) async {
    try {
      final response = await _dio.put('/auth/me', data: user.toJson());
      return User.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(
        'Failed to update profile: ${e.response?.data ?? e.message}',
      );
    }
  }

  Future<void> togglePinPlace(String tomtomId, bool isPinned) async {
    try {
      await _dio.patch(
        '/places/bookmarks/$tomtomId/pin',
        data: {'is_pinned': isPinned},
      );
    } on DioException catch (e) {
      throw Exception(
        'Failed to toggle pin for place: ${e.response?.data ?? e.message}',
      );
    }
  }

  Future<void> updateBookmarkGraphic(String tomtomId, String? icon, String? color, {String? customName}) async {
    try {
      final Map<String, dynamic> data = {};
      if (icon != null) data['icon'] = icon;
      if (color != null) data['color'] = color;
      if (customName != null) data['custom_name'] = customName;
      
      await _dio.patch(
        '/places/bookmarks/$tomtomId/graphic',
        data: data,
      );
    } on DioException catch (e) {
      throw Exception(
        'Failed to update graphic: ${e.response?.data ?? e.message}',
      );
    }
  }

  Future<void> updateVisitLength(String tomtomId, int? visitLength) async {
    try {
      await _dio.patch(
        '/places/bookmarks/$tomtomId/visit-length',
        data: {'visit_length': visitLength},
      );
    } on DioException catch (e) {
      throw Exception(
        'Failed to update visit length: ${e.response?.data ?? e.message}',
      );
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
      throw Exception(
        'Failed to fetch remote calendar: ${e.response?.data ?? e.message}',
      );
    }
  }
}
