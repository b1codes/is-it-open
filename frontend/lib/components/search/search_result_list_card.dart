import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/place.dart';
import '../../bloc/search/search_bloc.dart';
import '../../bloc/search/search_event.dart';
import '../shared/glass_container.dart';
import '../../screens/places/place_detail_screen.dart';

class SearchResultListCard extends StatelessWidget {
  final Place place;

  const SearchResultListCard({super.key, required this.place});

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      borderRadius: BorderRadius.circular(12),
      color: isDarkTheme ? Colors.black : Colors.white,
      opacity: isDarkTheme ? 0.3 : 0.7,
      child: ListTile(
        title: Text(
          place.name,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          place.address,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () {
          context.read<SearchBloc>().add(AddRecentPlace(place));
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlaceDetailScreen(place: place),
            ),
          );
        },
      ),
    );
  }
}
