import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../models/saved_place.dart';
import '../../../services/api_service.dart';
import '../shared/glass_container.dart';
import '../../screens/places/place_detail_screen.dart';
import '../../../utils/graphics_helper.dart';

class SavedPlaceGridCard extends StatelessWidget {
  final SavedPlace savedPlace;
  final VoidCallback onRefresh;

  const SavedPlaceGridCard({
    super.key,
    required this.savedPlace,
    required this.onRefresh,
  });

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
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GraphicsHelper.buildProfileGraphic(savedPlace, size: 32),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            savedPlace.customName ?? savedPlace.place.name,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      savedPlace.place.address,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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
                    iconSize: 20,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(right: 12),
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
                      savedPlace.isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                    ),
                    color: savedPlace.isPinned
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    iconSize: 20,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(right: 12),
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
                    iconSize: 20,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
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
                            SnackBar(
                              content: Text('Failed to remove place: $e'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
