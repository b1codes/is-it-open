import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/search/search_bloc.dart';
import 'package:frontend/components/search/search_result_grid_card.dart';
import 'package:frontend/components/search/search_result_list_card.dart';
import 'package:frontend/screens/places/place_detail_screen.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/pump_app.dart';

// Covers both search_result_list_card.dart and search_result_grid_card.dart:
// the two layouts of one result.
void main() {
  final cards = <String, Widget Function()>{
    'list': () => SearchResultListCard(place: coffeePlace),
    'grid': () => SizedBox(
      width: 180,
      height: 160,
      child: SearchResultGridCard(place: coffeePlace),
    ),
  };

  for (final MapEntry(key: layout, value: card) in cards.entries) {
    group('$layout card', () {
      testWidgets('shows the name and address', (tester) async {
        await tester.pumpApp(Scaffold(body: Center(child: card())));
        expect(find.text(coffeePlace.name), findsOneWidget);
        expect(find.text(coffeePlace.address), findsOneWidget);
      });

      testWidgets('records a recent place and opens its details', (
        tester,
      ) async {
        await tester.pumpApp(Scaffold(body: Center(child: card())));
        final context = tester.element(find.text(coffeePlace.name));
        await tester.tap(find.text(coffeePlace.name));
        await tester.pumpAndSettle();
        expect(find.byType(PlaceDetailScreen), findsOneWidget);
        expect(
          context.read<SearchBloc>().state.recentPlaces.first.tomtomId,
          coffeePlace.tomtomId,
        );
        await tester.unmount();
      });

      testWidgets('renders on a dark theme', (tester) async {
        await tester.pumpApp(
          Scaffold(body: Center(child: card())),
          themeMode: ThemeMode.dark,
        );
        await tester.pumpAndSettle();
        expect(find.text(coffeePlace.name), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
