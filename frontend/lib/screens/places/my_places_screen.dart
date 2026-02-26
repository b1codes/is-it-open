import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../services/api_service.dart';
import '../../../models/saved_place.dart';
import '../../../components/places/saved_place_list_card.dart';
import '../../../components/places/saved_place_grid_card.dart';

class MyPlacesScreen extends StatefulWidget {
  const MyPlacesScreen({super.key});

  @override
  State<MyPlacesScreen> createState() => _MyPlacesScreenState();
}

class _MyPlacesScreenState extends State<MyPlacesScreen> {
  late Future<List<SavedPlace>> _bookmarksFuture;
  bool _isGridView = false;

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
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
            tooltip: _isGridView ? 'List View' : 'Grid View',
          ),
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
              child: _isGridView
                  ? GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.85,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: places.length,
                      itemBuilder: (context, index) {
                        return SavedPlaceGridCard(
                          savedPlace: places[index],
                          onRefresh: _refreshBookmarks,
                        );
                      },
                    )
                  : ListView.builder(
                      itemCount: places.length,
                      itemBuilder: (context, index) {
                        final savedPlace = places[index];
                        return SavedPlaceListCard(
                          savedPlace: savedPlace,
                          onRefresh: _refreshBookmarks,
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
