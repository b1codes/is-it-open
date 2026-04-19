import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../models/saved_place.dart';
import '../../../services/api_service.dart';
import '../shared/glass_container.dart';
import '../../screens/places/place_detail_screen.dart';
import '../../../utils/graphics_helper.dart';

class SavedPlaceListCard extends StatelessWidget {
  final SavedPlace savedPlace;
  final VoidCallback onRefresh;

  const SavedPlaceListCard({
    super.key,
    required this.savedPlace,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      borderRadius: BorderRadius.circular(12),
      color: isDarkTheme ? Colors.black : Colors.white,
      opacity: isDarkTheme ? 0.3 : 0.7,
      child: ListTile(
        leading: GraphicsHelper.buildProfileGraphic(savedPlace),
        title: Text(
          savedPlace.customName ?? savedPlace.place.name,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          savedPlace.place.address,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                savedPlace.isCheckItOut
                    ? Icons.visibility
                    : Icons.visibility_off,
              ),
              color: savedPlace.isCheckItOut
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              tooltip: savedPlace.isCheckItOut ? 'Mark as Visited' : 'Check It Out',
              onPressed: () async {
                try {
                  await context.read<ApiService>().toggleCheckItOut(
                        savedPlace.place.tomtomId,
                        !savedPlace.isCheckItOut,
                      );
                  onRefresh();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to update: $e')),
                    );
                  }
                }
              },
            ),
            IconButton(
              icon: Icon(
                savedPlace.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              color: savedPlace.isPinned
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              onPressed: () async {
                try {
                  await context.read<ApiService>().togglePinPlace(
                    savedPlace.place.tomtomId,
                    !savedPlace.isPinned,
                  );
                  onRefresh();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to pin place: $e')),
                    );
                  }
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Theme.of(context).colorScheme.error,
              onPressed: () async {
                try {
                  await context.read<ApiService>().deleteBookmark(
                    savedPlace.place.tomtomId,
                  );
                  onRefresh();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Place removed from bookmarks'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to remove place: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlaceDetailScreen(place: savedPlace.place),
            ),
          ).then((_) {
            // Refresh bookmarks when returning from details screen
            onRefresh();
          });
        },
      ),
    );
  }
}
