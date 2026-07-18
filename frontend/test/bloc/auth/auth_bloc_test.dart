import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/api_service.dart';
import 'package:mocktail/mocktail.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  group('AuthBloc', () {
    late AuthBloc authBloc;
    late MockApiService mockApiService;

    setUp(() {
      mockApiService = MockApiService();
      authBloc = AuthBloc(apiClient: mockApiService);
    });

    tearDown(() {
      authBloc.close();
    });

    test('loads full user from JSON on AppStarted when offline', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'dummy_token',
        'auth_user_json': jsonEncode({
          'id': 1,
          'username': 'testuser',
          'email': 'test@example.com',
          'home_lat': 12.34,
          'home_lng': 56.78,
          'token': 'dummy_token',
        }),
      });

      when(() => mockApiService.setAuthToken(any())).thenReturn(null);
      when(() => mockApiService.getProfile()).thenThrow(Exception('Offline'));

      authBloc.add(AppStarted());

      await expectLater(
        authBloc.stream,
        emitsInOrder([
          isA<AuthLoading>(),
          isA<AuthAuthenticated>().having(
            (state) => state.user.homeLat,
            'homeLat',
            12.34,
          ),
        ]),
      );
    });

    test('saves full user to JSON on _saveUser', () async {
      SharedPreferences.setMockInitialValues({});
      when(() => mockApiService.login(any(), any())).thenAnswer(
        (_) async => User(
          id: 1,
          username: 'testuser',
          homeLat: 45.67,
          token: 'token123',
        ),
      );
      when(() => mockApiService.setAuthToken(any())).thenReturn(null);

      authBloc.add(LoginRequested(username: 'test', password: 'password'));

      await expectLater(
        authBloc.stream,
        emitsInOrder([isA<AuthLoading>(), isA<AuthAuthenticated>()]),
      );

      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('auth_user_json');
      expect(userJson, isNotNull);
      final decoded = jsonDecode(userJson!);
      expect(decoded['home_lat'], 45.67);
    });

    test(
      'emits Authenticated when Auth0LoginRequested is successful',
      () async {
        SharedPreferences.setMockInitialValues({});
        final mockUser = User(
          id: 2,
          username: 'auth0|mock_123',
          email: 'auth0@example.com',
          token: 'mock_jwt_token',
        );

        when(() => mockApiService.setAuthToken(any())).thenReturn(null);
        when(
          () => mockApiService.getProfile(),
        ).thenAnswer((_) async => mockUser);

        authBloc.add(const Auth0LoginRequested(token: 'mock_jwt_token'));

        await expectLater(
          authBloc.stream,
          emitsInOrder([
            isA<AuthLoading>(),
            isA<AuthAuthenticated>().having(
              (state) => state.user.username,
              'username',
              'auth0|mock_123',
            ),
          ]),
        );

        verify(() => mockApiService.setAuthToken('mock_jwt_token')).called(1);
        verify(() => mockApiService.getProfile()).called(1);
      },
    );
  });
}
