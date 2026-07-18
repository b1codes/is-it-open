import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import '../../../services/api_service.dart';
import '../../../bloc/search/search_bloc.dart';
import '../../../bloc/search/search_event.dart';
import '../../../bloc/search/search_state.dart';

import 'package:frontend/screens/places/create_place_screen.dart';
import '../../components/search/search_result_list_card.dart';
import '../../components/search/search_result_grid_card.dart';

class SearchScreen extends StatefulWidget {
  final bool embedded;
  final ScrollController? scrollController;

  const SearchScreen({super.key, this.embedded = false, this.scrollController});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    // Use a post-frame callback to trigger suggestions after the Bloc is initialized via BlocProvider
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions(BuildContext context) async {
    double? lat;
    double? lng;

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition();
        lat = position.latitude;
        lng = position.longitude;
      }
    } catch (e) {
      // Ignore location errors for suggestions
    }

    if (context.mounted) {
      context.read<SearchBloc>().add(LoadSearchSuggestions(lat: lat, lng: lng));
    }
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
    _loadSuggestions(context);
  }

  Widget _buildSuggestionsSection(
    SearchState state,
    ScrollController? scrollController,
  ) {
    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.recentPlaces.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Recent Searches',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: state.recentPlaces.length,
                itemBuilder: (context, index) {
                  final place = state.recentPlaces[index];
                  return SizedBox(
                    width: 200,
                    child: SearchResultGridCard(place: place),
                  );
                },
              ),
            ),
          ],
          if (state.suggestions.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                'Trending Nearby',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  mainAxisExtent: 140,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: state.suggestions.length,
                itemBuilder: (context, index) {
                  final place = state.suggestions[index];
                  return SearchResultGridCard(place: place);
                },
              ),
            ),
          ] else if (state.suggestions.isEmpty && state.recentPlaces.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No suggestions available.\nTry searching for something!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final bloc = SearchBloc(apiClient: context.read<ApiService>());
        _loadSuggestions(context);
        return bloc;
      },
      child: Builder(
        builder: (context) {
          final mainColumn = Column(
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
                            onChanged: (value) {
                              if (value.isEmpty) {
                                context.read<SearchBloc>().add(
                                  const SearchQueryChanged(''),
                                );
                                _loadSuggestions(context);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _performSearch(context),
                          child: const Text('Search'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            _isGridView ? Icons.view_list : Icons.grid_view,
                          ),
                          onPressed: () {
                            setState(() {
                              _isGridView = !_isGridView;
                            });
                          },
                          tooltip: _isGridView ? 'List View' : 'Grid View',
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
                    } else if (state.status == SearchStatus.initial) {
                      return _buildSuggestionsSection(
                        state,
                        widget.scrollController,
                      );
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
                      return _isGridView
                          ? GridView.builder(
                              controller: widget.scrollController,
                              padding: const EdgeInsets.all(8),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 300,
                                    mainAxisExtent: 140,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemCount: state.places.length + 1,
                              itemBuilder: (context, index) {
                                if (index == state.places.length) {
                                  return Card(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const CreatePlaceScreen(),
                                          ),
                                        );
                                      },
                                      child: const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(16.0),
                                          child: Text(
                                            "Don't see it?\nCreate a New Place",
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final place = state.places[index];
                                return SearchResultGridCard(place: place);
                              },
                            )
                          : ListView.builder(
                              controller: widget.scrollController,
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
                                return SearchResultListCard(place: place);
                              },
                            );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          );

          if (widget.embedded) {
            return mainColumn;
          }

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(child: mainColumn),
          );
        },
      ),
    );
  }
}
