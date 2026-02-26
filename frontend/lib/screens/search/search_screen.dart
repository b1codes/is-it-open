import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../services/api_service.dart';
import '../../../bloc/search/search_bloc.dart';
import '../../../bloc/search/search_event.dart';
import '../../../bloc/search/search_state.dart';

import 'package:frontend/screens/places/place_detail_screen.dart'; // Will be created next
import 'package:frontend/screens/places/create_place_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(BuildContext context) {
    final query = _searchController.text;
    if (query.isNotEmpty) {
      context.read<SearchBloc>().add(SearchQueryChanged(query));
    }
  }

  void _clearSearch(BuildContext context) {
    _searchController.clear();
    context.read<SearchBloc>().add(const SearchQueryChanged(''));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SearchBloc(apiClient: context.read<ApiService>()),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Builder(
                  builder: (context) {
                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search for a place...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => _clearSearch(context),
                              ),
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(
                                context,
                              ).cardColor.withValues(alpha: 0.9),
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _performSearch(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _performSearch(context),
                          child: const Text('Search'),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Expanded(
                child: BlocBuilder<SearchBloc, SearchState>(
                  builder: (context, state) {
                    if (state.status == SearchStatus.loading) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (state.status == SearchStatus.failure) {
                      return Center(child: Text('Error: ${state.error}'));
                    } else if (state.status == SearchStatus.success) {
                      if (state.places.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('No results found'),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const CreatePlaceScreen(),
                                    ),
                                  );
                                },
                                child: const Text('Create a New Place'),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: state.places.length + 1,
                        itemBuilder: (context, index) {
                          if (index == state.places.length) {
                            return Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const CreatePlaceScreen(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  "Don't see it? Create a New Place",
                                ),
                              ),
                            );
                          }
                          final place = state.places[index];
                          return Card(
                            color: Theme.of(
                              context,
                            ).cardColor.withValues(alpha: 0.9),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: ListTile(
                              title: Text(place.name),
                              subtitle: Text(place.address),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        PlaceDetailScreen(place: place),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    }
                    return Center(
                      child: Text(
                        'Enter a query and press Search',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
