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

  // Bumped by [clear], so a load or edit that started before it doesn't
  // bring the cleared route back when it finishes.
  int _generation = 0;

  // Writes to the store run one at a time, in call order, so the removal in
  // [clear] always lands after a write that started before it and the old
  // route can't end up back on the device.
  Future<void> _writes = Future.value();

  bool _isStale(int generation) => generation != _generation || isClosed;

  Future<SharedPreferences> _prefs() async =>
      _injectedPrefs ?? await SharedPreferences.getInstance();

  /// The SharedPreferences entries that persist [ids] as the route for
  /// [date]. Exposed so fixtures can seed a route in the exact persisted
  /// format.
  static Map<String, String> persistedValues(List<String> ids, DateTime date) =>
      {_idsKey: jsonEncode(ids), _dateKey: _dateString(date)};

  Future<void> _hydrate() async {
    final generation = _generation;
    final prefs = await _prefs();
    if (_isStale(generation)) return;
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
      if (_isStale(generation)) return;
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
    final generation = _generation;
    await _persist(const [], today);
    if (_isStale(generation)) return;
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
    final generation = _generation;
    await _persist(next, today);
    if (_isStale(generation)) return;
    emit(
      state.copyWith(tomtomIds: next, touchedOn: today, clearAutoCleared: true),
    );
  }

  Future<void> remove(String tomtomId) async {
    if (!state.tomtomIds.contains(tomtomId)) return;
    final next = state.tomtomIds.where((id) => id != tomtomId).toList();
    final today = _dateOnly(clock.now());
    final generation = _generation;
    await _persist(next, today);
    if (_isStale(generation)) return;
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
    final generation = _generation;
    await _persist(next, today);
    if (_isStale(generation)) return;
    emit(
      state.copyWith(tomtomIds: next, touchedOn: today, clearAutoCleared: true),
    );
  }

  /// Empties the route, in memory and on the device, without the overnight
  /// reset's note. Called on sign-out: the route belongs to whoever built it,
  /// and the next account on this device would otherwise inherit it.
  Future<void> clear() async {
    _generation++;
    final today = _dateOnly(clock.now());
    emit(TodayRouteState(tomtomIds: const [], touchedOn: today));
    await _write((prefs) async {
      await prefs.remove(_idsKey);
      await prefs.remove(_dateKey);
    });
  }

  Future<void> dismissResetNote() async {
    if (state.autoClearedFrom == null) return;
    emit(state.copyWith(clearAutoCleared: true));
  }

  Future<void> _persist(List<String> ids, DateTime date) =>
      _write((prefs) async {
        for (final entry in persistedValues(ids, date).entries) {
          await prefs.setString(entry.key, entry.value);
        }
      });

  // Queues [write] behind the writes already in flight.
  Future<void> _write(Future<void> Function(SharedPreferences prefs) write) {
    final done = _writes.then((_) async => write(await _prefs()));
    // A failed write fails its caller but doesn't stall the ones after it.
    _writes = done.catchError((Object _) {});
    return done;
  }

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dateString(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
