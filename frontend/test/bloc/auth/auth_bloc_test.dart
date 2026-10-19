import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/api_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mocks.dart';

final _user = User(
  id: 1,
  username: 'avery',
  email: 'avery@example.com',
  homeStreet: '120 W 11th St',
  homeCity: 'New York',
  homeLat: 40.7,
  calendarSubscriptionUrl: 'https://cal.example/a.ics',
  token: 'tok',
);

Future<Map<String, Object?>> _stored() async {
  final prefs = await SharedPreferences.getInstance();
  return {for (final key in prefs.getKeys()) key: prefs.get(key)};
}

void main() {
  late MockApiService api;

  setUpAll(registerFallbacks);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = MockApiService();
  });

  AuthBloc build() => AuthBloc(apiClient: api);

  test('starts in AuthInitial', () {
    expect(build().state, isA<AuthInitial>());
  });

  group('AppStarted', () {
    blocTest<AuthBloc, AuthState>(
      'is unauthenticated without a stored token',
      build: build,
      act: (bloc) => bloc.add(AppStarted()),
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
      verify: (_) => verifyNever(() => api.getProfile()),
    );

    blocTest<AuthBloc, AuthState>(
      'refreshes the profile with the stored token and saves it',
      setUp: () =>
          SharedPreferences.setMockInitialValues({'auth_token': 'tok'}),
      build: () {
        when(() => api.getProfile()).thenAnswer((_) async => _user);
        return build();
      },
      act: (bloc) => bloc.add(AppStarted()),
      expect: () => [isA<AuthLoading>(), AuthAuthenticated(user: _user)],
      verify: (_) async {
        verify(() => api.setAuthToken('tok')).called(1);
        final stored = await _stored();
        expect(stored['auth_username'], 'avery');
        expect(stored['auth_calendar_url'], 'https://cal.example/a.ics');
        expect(
          jsonDecode(stored['auth_user_json'] as String)['home_city'],
          'New York',
        );
      },
    );

    blocTest<AuthBloc, AuthState>(
      'falls back to the cached profile when offline',
      setUp: () => SharedPreferences.setMockInitialValues({
        'auth_token': 'tok',
        'auth_user_json': jsonEncode(_user.toJson()),
      }),
      build: () {
        when(() => api.getProfile()).thenThrow(ApiException('offline'));
        return build();
      },
      act: (bloc) => bloc.add(AppStarted()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>()
            .having((s) => s.user.homeLat, 'homeLat', 40.7)
            .having((s) => s.user.homeStreet, 'homeStreet', '120 W 11th St'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'falls back to the legacy cached fields without a JSON profile',
      setUp: () => SharedPreferences.setMockInitialValues({
        'auth_token': 'tok',
        'auth_username': 'legacy',
        'auth_user_id': 9,
        'auth_user_email': 'l@example.com',
        'auth_calendar_url': 'https://cal.example/l.ics',
      }),
      build: () {
        when(() => api.getProfile()).thenThrow(ApiException('offline'));
        return build();
      },
      act: (bloc) => bloc.add(AppStarted()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>()
            .having((s) => s.user.id, 'id', 9)
            .having((s) => s.user.username, 'username', 'legacy')
            .having((s) => s.user.email, 'email', 'l@example.com')
            .having((s) => s.user.token, 'token', 'tok')
            .having(
              (s) => s.user.calendarSubscriptionUrl,
              'calendarSubscriptionUrl',
              'https://cal.example/l.ics',
            ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'is unauthenticated when offline with nothing cached',
      setUp: () =>
          SharedPreferences.setMockInitialValues({'auth_token': 'tok'}),
      build: () {
        when(() => api.getProfile()).thenThrow(ApiException('offline'));
        return build();
      },
      act: (bloc) => bloc.add(AppStarted()),
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'is unauthenticated when the cached JSON is corrupt',
      setUp: () => SharedPreferences.setMockInitialValues({
        'auth_token': 'tok',
        'auth_user_json': '{not json',
      }),
      build: () {
        when(() => api.getProfile()).thenThrow(ApiException('offline'));
        return build();
      },
      act: (bloc) => bloc.add(AppStarted()),
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'signs out and forgets the session when the token has expired',
      setUp: () => SharedPreferences.setMockInitialValues({
        'auth_token': 'expired',
        'auth_user_json': jsonEncode(_user.toJson()),
        'auth_username': 'avery',
        'auth_user_id': 1,
        'auth_calendar_url': 'https://cal.example/a.ics',
        'unrelated': 'kept',
      }),
      build: () {
        when(
          () => api.getProfile(),
        ).thenThrow(ApiException('Unauthorized', statusCode: 401));
        return build();
      },
      act: (bloc) => bloc.add(AppStarted()),
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
      verify: (_) async {
        verifyInOrder([
          () => api.setAuthToken('expired'),
          () => api.setAuthToken(null),
        ]);
        expect(await _stored(), {'unrelated': 'kept'});
      },
    );
  });

  group('LoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'authenticates, sets the token and persists the user',
      build: () {
        when(() => api.login('avery', 'pw')).thenAnswer((_) async => _user);
        return build();
      },
      act: (bloc) =>
          bloc.add(const LoginRequested(username: 'avery', password: 'pw')),
      expect: () => [isA<AuthLoading>(), AuthAuthenticated(user: _user)],
      verify: (_) async {
        verify(() => api.setAuthToken('tok')).called(1);
        final stored = await _stored();
        expect(stored['auth_token'], 'tok');
        expect(stored['auth_user_id'], 1);
        expect(stored['auth_user_email'], 'avery@example.com');
      },
    );

    blocTest<AuthBloc, AuthState>(
      'reports the API error',
      build: () {
        when(
          () => api.login(any(), any()),
        ).thenThrow(ApiException('Failed to login: bad', statusCode: 401));
        return build();
      },
      act: (bloc) =>
          bloc.add(const LoginRequested(username: 'avery', password: 'x')),
      expect: () => [
        isA<AuthLoading>(),
        const AuthFailure(error: 'Exception: Failed to login: bad'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'clears a stale calendar URL for a user without one',
      setUp: () => SharedPreferences.setMockInitialValues({
        'auth_calendar_url': 'https://old.example/x.ics',
      }),
      build: () {
        when(
          () => api.login(any(), any()),
        ).thenAnswer((_) async => User(id: 2, username: 'b', token: 't'));
        return build();
      },
      act: (bloc) =>
          bloc.add(const LoginRequested(username: 'b', password: 'p')),
      verify: (_) async {
        expect(await _stored(), isNot(contains('auth_calendar_url')));
      },
    );
  });

  group('RegisterRequested', () {
    blocTest<AuthBloc, AuthState>(
      'registers and authenticates',
      build: () {
        when(
          () => api.register('avery', 'pw', email: 'a@b.c'),
        ).thenAnswer((_) async => _user);
        return build();
      },
      act: (bloc) => bloc.add(
        const RegisterRequested(
          username: 'avery',
          password: 'pw',
          email: 'a@b.c',
        ),
      ),
      expect: () => [isA<AuthLoading>(), AuthAuthenticated(user: _user)],
      verify: (_) => verify(() => api.setAuthToken('tok')).called(1),
    );

    blocTest<AuthBloc, AuthState>(
      'reports a taken username',
      build: () {
        when(
          () => api.register(any(), any(), email: any(named: 'email')),
        ).thenThrow(ApiException('Failed to register: taken'));
        return build();
      },
      act: (bloc) =>
          bloc.add(const RegisterRequested(username: 'a', password: 'b')),
      expect: () => [
        isA<AuthLoading>(),
        const AuthFailure(error: 'Exception: Failed to register: taken'),
      ],
    );
  });

  group('Auth0LoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'uses the Auth0 token to load the profile',
      build: () {
        when(() => api.getProfile()).thenAnswer((_) async => _user);
        return build();
      },
      act: (bloc) => bloc.add(const Auth0LoginRequested(token: 'jwt')),
      expect: () => [isA<AuthLoading>(), AuthAuthenticated(user: _user)],
      verify: (_) => verify(() => api.setAuthToken('jwt')).called(1),
    );

    blocTest<AuthBloc, AuthState>(
      'fails when the profile cannot be loaded',
      build: () {
        when(() => api.getProfile()).thenThrow(ApiException('nope'));
        return build();
      },
      act: (bloc) => bloc.add(const Auth0LoginRequested(token: 'jwt')),
      expect: () => [
        isA<AuthLoading>(),
        const AuthFailure(error: 'Exception: nope'),
      ],
    );
  });

  group('LogoutRequested', () {
    blocTest<AuthBloc, AuthState>(
      'clears the token and every stored session key',
      setUp: () => SharedPreferences.setMockInitialValues({
        'auth_token': 'tok',
        'auth_user_json': jsonEncode(_user.toJson()),
        'auth_username': 'avery',
        'auth_user_id': 1,
        'auth_user_email': 'avery@example.com',
        'auth_calendar_url': 'https://cal.example/a.ics',
        'use_24_hour_format': true,
      }),
      build: build,
      seed: () => AuthAuthenticated(user: _user),
      act: (bloc) => bloc.add(LogoutRequested()),
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
      verify: (_) async {
        verify(() => api.setAuthToken(null)).called(1);
        expect(await _stored(), {'use_24_hour_format': true});
      },
    );
  });

  group('ProfileUpdateRequested', () {
    final edited = User.fromJson({..._user.toJson(), 'home_city': 'Brooklyn'});

    blocTest<AuthBloc, AuthState>(
      'is ignored when signed out',
      build: build,
      act: (bloc) => bloc.add(ProfileUpdateRequested(updatedUser: edited)),
      expect: () => <AuthState>[],
      verify: (_) => verifyNever(() => api.updateProfile(any())),
    );

    blocTest<AuthBloc, AuthState>(
      'saves the updated profile',
      build: () {
        when(() => api.updateProfile(edited)).thenAnswer((_) async => edited);
        return build();
      },
      seed: () => AuthAuthenticated(user: _user),
      act: (bloc) => bloc.add(ProfileUpdateRequested(updatedUser: edited)),
      expect: () => [isA<AuthLoading>(), ProfileUpdateSuccess(user: edited)],
      verify: (_) async {
        final stored = await _stored();
        expect(
          jsonDecode(stored['auth_user_json'] as String)['home_city'],
          'Brooklyn',
        );
      },
    );

    blocTest<AuthBloc, AuthState>(
      'keeps the token and every field when the response has no token',
      build: () {
        when(() => api.updateProfile(any())).thenAnswer(
          (_) async => User.fromJson({...demoUser.toJson(), 'token': null}),
        );
        return build();
      },
      seed: () => AuthAuthenticated(user: _user),
      act: (bloc) => bloc.add(ProfileUpdateRequested(updatedUser: demoUser)),
      expect: () => [
        isA<AuthLoading>(),
        isA<ProfileUpdateSuccess>().having((s) => s.user.toJson(), 'user', {
          ...demoUser.toJson(),
          'token': 'tok',
        }),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'keeps the current user and reports the error on failure',
      build: () {
        when(
          () => api.updateProfile(any()),
        ).thenThrow(ApiException('Failed to update profile: 422'));
        return build();
      },
      seed: () => AuthAuthenticated(user: _user),
      act: (bloc) => bloc.add(ProfileUpdateRequested(updatedUser: edited)),
      expect: () => [
        isA<AuthLoading>(),
        ProfileUpdateFailure(
          user: _user,
          error: 'Exception: Failed to update profile: 422',
        ),
      ],
    );
  });

  test('states and events compare by value', () {
    expect(AuthAuthenticated(user: _user), AuthAuthenticated(user: _user));
    expect(const AuthFailure(error: 'a'), isNot(const AuthFailure(error: 'b')));
    expect(const LoginRequested(username: 'a', password: 'b').props, [
      'a',
      'b',
    ]);
    expect(
      const RegisterRequested(username: 'a', password: 'b', email: 'c').props,
      ['a', 'b', 'c'],
    );
    expect(const Auth0LoginRequested(token: 't').props, ['t']);
    expect(ProfileUpdateRequested(updatedUser: _user).props, [_user]);
    expect(AppStarted().props, isEmpty);
    expect(ProfileUpdateFailure(user: _user, error: 'e').props, [_user, 'e']);
  });
}
