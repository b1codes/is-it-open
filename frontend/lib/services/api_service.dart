import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb and debugPrint
import 'dart:io'; // For Platform check
import '../models/place.dart';
import '../models/user.dart';

class ApiService {
  late final Dio _dio;
  String? _authToken;

  ApiService() {
    // Determine Base URL based on platform
    String baseUrl = 'http://127.0.0.1:8000/api';
    if (!kIsWeb && Platform.isAndroid) {
      baseUrl = 'http://10.0.2.2:8000/api';
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
}
