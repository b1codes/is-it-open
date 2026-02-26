import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../services/api_service.dart';
import '../../../models/saved_place.dart';
import '../../../components/shared/glass_container.dart';
import 'place_detail_screen.dart';

class MyPlacesScreen extends StatefulWidget {
  const MyPlacesScreen({super.key});

  @override
  State<MyPlacesScreen> createState() => _MyPlacesScreenState();
}

class _MyPlacesScreenState extends State<MyPlacesScreen> {
  late Future<List<SavedPlace>> _bookmarksFuture;

  @override
  void initState() {
    super.initState();
    _bookmarksFuture = context.read<ApiService>().getBookmarks();
  }

  Future<void> _refreshBookmarks() async {
    setState(() {
      _bookmarksFuture = context.read<ApiService>().getBookmarks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('My Saved Places'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshBookmarks,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<SavedPlace>>(
          future: _bookmarksFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Error: ${snapshot.error}'),
                    ElevatedButton(
                      onPressed: _refreshBookmarks,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Text(
                  'No saved places yet',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                  ),
                ),
              );
            }

            final places = snapshot.data!;
            return RefreshIndicator(
              onRefresh: _refreshBookmarks,
              child: ListView.builder(
                itemCount: places.length,
                itemBuilder: (context, index) {
                  final savedPlace = places[index];
                  final isDarkTheme =
                      Theme.of(context).brightness == Brightness.dark;
                  return GlassContainer(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: isDarkTheme ? Colors.black : Colors.white,
                    opacity: isDarkTheme ? 0.3 : 0.7,
                    child: ListTile(
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
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                PlaceDetailScreen(place: savedPlace.place),
                          ),
                        ).then((_) {
                          // Refresh bookmarks when returning from details screen
                          _refreshBookmarks();
                        });
                      },
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
