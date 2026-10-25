import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/place.dart';
import '../../bloc/search/search_bloc.dart';
import '../../bloc/search/search_event.dart';
import '../shared/glass_container.dart';
import '../../screens/places/place_detail_screen.dart';

class SearchResultGridCard extends StatelessWidget {
  final Place place;

  const SearchResultGridCard({super.key, required this.place});

  static const _nameSize = 16.0;
  static const _addressSize = 12.0;

  /// The height a card needs for a two-line name and a line of its address
  /// at the user's text size, and at least [minimum]. A fixed height
  /// overflowed with large text.
  static double extent(BuildContext context, {required double minimum}) {
    final scaler = MediaQuery.textScalerOf(context);
    // The card's text inherits its line height from bodyMedium, the
    // Material default (the caller may be above the Scaffold that sets it).
    final lineHeight = Theme.of(context).textTheme.bodyMedium?.height ?? 1.0;
    // Rounded up per line, as text lays out on whole pixels.
    double lines(double fontSize, int count) =>
        count * (scaler.scale(fontSize) * lineHeight).ceilToDouble();
    final needed =
        2 * 8 + // margin
        2 * 1 + // border
        2 * 12 + // padding
        lines(_nameSize, 2) +
        8 +
        lines(_addressSize, 1);
    return math.max(minimum, needed);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return GlassContainer(
      margin: const EdgeInsets.all(8),
      borderRadius: BorderRadius.circular(16),
      color: isDarkTheme ? Colors.black : Colors.white,
      opacity: isDarkTheme ? 0.3 : 0.7,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          context.read<SearchBloc>().add(AddRecentPlace(place));
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlaceDetailScreen(place: place),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                place.name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: _nameSize,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  place.address,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: _addressSize,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
