import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TodayRouteState {
  const TodayRouteState({
    required this.tomtomIds,
    required this.touchedOn,
    this.autoClearedFrom,
  });

  // Ordered list of tomtom ids on today's plan. Order is user-meaningful
  // (drag-to-reorder in the UI).
  final List<String> tomtomIds;

  // The local date this state was last modified (yyyy-MM-dd). Used to detect
  // overnight rollover.
  final DateTime touchedOn;

  // Set when an auto-reset happened on the most recent load. The screen
  // shows a quiet one-line note while this is non-null; the next user
  // action clears it.
  final DateTime? autoClearedFrom;

  bool get isEmpty => tomtomIds.isEmpty;

  bool contains(String tomtomId) => tomtomIds.contains(tomtomId);

  TodayRouteState copyWith({
    List<String>? tomtomIds,
    DateTime? touchedOn,
    DateTime? autoClearedFrom,
    bool clearAutoCleared = false,
  }) {
    return TodayRouteState(
      tomtomIds: tomtomIds ?? this.tomtomIds,
      touchedOn: touchedOn ?? this.touchedOn,
      autoClearedFrom: clearAutoCleared
          ? null
          : (autoClearedFrom ?? this.autoClearedFrom),
    );
  }
}

class TodayRouteCubit extends Cubit<TodayRouteState> {
  static const _idsKey = 'today_route_ids';
  static const _dateKey = 'today_route_date';

  /// [prefs] overrides the store the route is read from and written to.
  /// Defaults to the app-wide [SharedPreferences.getInstance]; pass an
  /// isolated instance to keep fixtures and tests from sharing state.
  TodayRouteCubit({SharedPreferences? prefs})
    : _injectedPrefs = prefs,
      super(
        TodayRouteState(tomtomIds: const [], touchedOn: _dateOnly(clock.now())),
      ) {
    _hydrate();
  }

  final SharedPreferences? _injectedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _injectedPrefs ?? await SharedPreferences.getInstance();

  /// The SharedPreferences entries that persist [ids] as the route for
  /// [date]. Exposed so fixtures can seed a route in the exact persisted
  /// format.
  static Map<String, String> persistedValues(List<String> ids, DateTime date) =>
      {_idsKey: jsonEncode(ids), _dateKey: _dateString(date)};

  Future<void> _hydrate() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_idsKey);
    final storedDateString = prefs.getString(_dateKey);
    final today = _dateOnly(clock.now());

    if (raw == null || storedDateString == null) {
      emit(TodayRouteState(tomtomIds: const [], touchedOn: today));
      return;
    }

    final storedDate = DateTime.parse(storedDateString);
    if (!_sameDay(storedDate, today)) {
      // Overnight reset. Persist the empty state under today's date and
      // surface the prior date so the UI can show its quiet note.
      await _persist(const [], today);
      emit(
        TodayRouteState(
          tomtomIds: const [],
          touchedOn: today,
          autoClearedFrom: storedDate,
        ),
      );
      return;
    }

    final decoded = (jsonDecode(raw) as List).cast<String>();
    emit(TodayRouteState(tomtomIds: decoded, touchedOn: storedDate));
  }

  // Call when the screen comes back into view so a route built yesterday
  // doesn't linger if the app stayed open through midnight.
  Future<void> refresh() async {
    final today = _dateOnly(clock.now());
    if (_sameDay(state.touchedOn, today)) return;
    await _persist(const [], today);
    emit(
      TodayRouteState(
        tomtomIds: const [],
        touchedOn: today,
        autoClearedFrom: state.touchedOn,
      ),
    );
  }

  Future<void> add(String tomtomId) async {
    if (state.tomtomIds.contains(tomtomId)) return;
    final next = [...state.tomtomIds, tomtomId];
    final today = _dateOnly(clock.now());
    await _persist(next, today);
    emit(
      state.copyWith(tomtomIds: next, touchedOn: today, clearAutoCleared: true),
    );
  }

  Future<void> remove(String tomtomId) async {
    if (!state.tomtomIds.contains(tomtomId)) return;
    final next = state.tomtomIds.where((id) => id != tomtomId).toList();
    final today = _dateOnly(clock.now());
    await _persist(next, today);
    emit(
      state.copyWith(tomtomIds: next, touchedOn: today, clearAutoCleared: true),
    );
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final next = [...state.tomtomIds];
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final item = next.removeAt(oldIndex);
    next.insert(adjusted, item);
    final today = _dateOnly(clock.now());
    await _persist(next, today);
    emit(
      state.copyWith(tomtomIds: next, touchedOn: today, clearAutoCleared: true),
    );
  }

  Future<void> dismissResetNote() async {
    if (state.autoClearedFrom == null) return;
    emit(state.copyWith(clearAutoCleared: true));
  }

  Future<void> _persist(List<String> ids, DateTime date) async {
    final prefs = await _prefs();
    for (final entry in persistedValues(ids, date).entries) {
      await prefs.setString(entry.key, entry.value);
    }
  }

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dateString(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
