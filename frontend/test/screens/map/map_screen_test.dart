import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:frontend/screens/map/map_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/services/api_service.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

void main() {
  testWidgets('MapScreen renders FlutterMap immediately without blocking', (
    WidgetTester tester,
  ) async {
    final mockAuthBloc = MockAuthBloc();
    final mockApiService = MockApiService();
    when(() => mockAuthBloc.state).thenReturn(AuthInitial());
    when(() => mockApiService.getBookmarks()).thenAnswer((_) async => []);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [BlocProvider<AuthBloc>.value(value: mockAuthBloc)],
          child: RepositoryProvider<ApiService>.value(
            value: mockApiService,
            child: const MapScreen(),
          ),
        ),
      ),
    );

    // Initial pump to trigger build
    await tester.pump();

    // Should find FlutterMap immediately
    expect(find.byType(FlutterMap), findsOneWidget);

    // It's okay if there's a loader in the sidebar, but the main screen should NOT be JUST a loader
    // In the new implementation, the map is always part of the body.
  });
}
