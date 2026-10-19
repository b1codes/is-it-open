import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../models/place.dart';
import 'search_event.dart';
import 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final ApiService apiClient;
  static const String _recentPlacesKey = 'recent_search_places';

  // The query the user most recently asked for. A slower response to an
  // earlier query is dropped, so it can't overwrite newer results or refill
  // a search the user has cleared.
  String _latestQuery = '';

  SearchBloc({required this.apiClient}) : super(const SearchState()) {
    on<SearchQueryChanged>(_onSearchQueryChanged);
    on<LoadSearchSuggestions>(_onLoadSearchSuggestions);
    on<AddRecentPlace>(_onAddRecentPlace);
  }

  Future<void> _onSearchQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    _latestQuery = event.query;
    if (event.query.isEmpty) {
      emit(state.copyWith(status: SearchStatus.initial, places: []));
      return;
    }

    emit(state.copyWith(status: SearchStatus.loading));

    try {
      final places = await apiClient.searchPlaces(event.query);
      if (event.query != _latestQuery) return;
      emit(state.copyWith(status: SearchStatus.success, places: places));
    } catch (e) {
      if (event.query != _latestQuery) return;
      emit(state.copyWith(status: SearchStatus.failure, error: e.toString()));
    }
  }

  Future<void> _onLoadSearchSuggestions(
    LoadSearchSuggestions event,
    Emitter<SearchState> emit,
  ) async {
    // Load recent places from local storage
    final prefs = await SharedPreferences.getInstance();
    final List<String> recentJson = prefs.getStringList(_recentPlacesKey) ?? [];
    final List<Place> recentPlaces = recentJson
        .map((s) => Place.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();

    emit(state.copyWith(recentPlaces: recentPlaces));

    // Fetch trending/nearby suggestions from backend
    try {
      final suggestions = await apiClient.getSuggestions(event.lat, event.lng);
      emit(state.copyWith(suggestions: suggestions));
    } catch (e) {
      // Non-critical error, suggestions might be empty
    }
  }

  Future<void> _onAddRecentPlace(
    AddRecentPlace event,
    Emitter<SearchState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> recentJson = prefs.getStringList(_recentPlacesKey) ?? [];

    // Remove if already exists to move to top
    recentJson.removeWhere((s) {
      final p = Place.fromJson(jsonDecode(s) as Map<String, dynamic>);
      return p.tomtomId == event.place.tomtomId;
    });

    // Add to top
    recentJson.insert(0, jsonEncode(event.place.toJson()));

    // Keep only last 10
    if (recentJson.length > 10) {
      recentJson.removeLast();
    }

    await prefs.setStringList(_recentPlacesKey, recentJson);

    final List<Place> updatedRecent = recentJson
        .map((s) => Place.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();

    emit(state.copyWith(recentPlaces: updatedRecent));
  }
}
