import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/preferences/preferences_cubit.dart';
import '../../bloc/today/today_cubit.dart';
import '../../components/places/quick_add_place_sheet.dart';
import '../../components/places/saved_place_row.dart';
import '../../components/places/saved_place_tile.dart';
import '../../components/places/status_pill.dart';
import '../../models/saved_place.dart';
import '../../services/api_service.dart';
import '../../utils/place_status.dart';
import '../../utils/places_theme.dart';
import 'place_detail_screen.dart';

enum _VisitFilter { all, wantToVisit, visited }

enum _ViewMode { list, grid }

class MyPlacesScreen extends StatefulWidget {
  const MyPlacesScreen({super.key});

  @override
  State<MyPlacesScreen> createState() => _MyPlacesScreenState();
}

class _MyPlacesScreenState extends State<MyPlacesScreen> {
  Future<List<SavedPlace>>? _bookmarksFuture;
  _ViewMode _viewMode = _ViewMode.list;
  _VisitFilter _filter = _VisitFilter.all;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
    // Minute ticker: triggers a rebuild so status pills update from
    // open → closing-soon → closed without a manual refresh. Cheap because
    // the data future itself doesn't reload.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Re-check the cubit in case the app stayed open through midnight.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TodayRouteCubit>().refresh();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _loadBookmarks() {
    setState(() {
      _bookmarksFuture = context.read<ApiService>().getBookmarks();
    });
  }

  Future<void> _refresh() async {
    final next = context.read<ApiService>().getBookmarks();
    setState(() => _bookmarksFuture = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.places;

    return Scaffold(
      backgroundColor: theme.paper,
      appBar: AppBar(
        backgroundColor: theme.paper,
        surfaceTintColor: theme.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: theme.ink,
        title: Text('My Places', style: PlacesType.headline(theme.ink)),
        actions: [
          IconButton(
            tooltip: _viewMode == _ViewMode.list ? 'Grid view' : 'List view',
            icon: Icon(
              _viewMode == _ViewMode.list
                  ? Icons.grid_view_rounded
                  : Icons.view_agenda_outlined,
              color: theme.inkMuted,
            ),
            onPressed: () => setState(() {
              _viewMode = _viewMode == _ViewMode.list
                  ? _ViewMode.grid
                  : _ViewMode.list;
            }),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded, color: theme.inkMuted),
            onPressed: _refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<SavedPlace>>(
          future: _bookmarksFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _SkeletonList();
            }
            if (snapshot.hasError) {
              return _ErrorState(onRetry: _refresh);
            }
            final allPlaces = snapshot.data ?? const <SavedPlace>[];
            if (allPlaces.isEmpty) {
              return const _EmptyState();
            }
            return _PlacesBody(
              allPlaces: allPlaces,
              filter: _filter,
              viewMode: _viewMode,
              onFilterChanged: (f) => setState(() => _filter = f),
              onRefresh: _refresh,
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────

class _PlacesBody extends StatelessWidget {
  const _PlacesBody({
    required this.allPlaces,
    required this.filter,
    required this.viewMode,
    required this.onFilterChanged,
    required this.onRefresh,
  });

  final List<SavedPlace> allPlaces;
  final _VisitFilter filter;
  final _ViewMode viewMode;
  final ValueChanged<_VisitFilter> onFilterChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final use24h = context.watch<PreferencesCubit>().state.use24HourFormat;
    final now = DateTime.now();

    final filtered = allPlaces.where(
      (p) => switch (filter) {
        _VisitFilter.all => true,
        _VisitFilter.wantToVisit => p.isCheckItOut,
        _VisitFilter.visited => !p.isCheckItOut,
      },
    );

    // Compute status for each place once (avoids per-row recomputation in lists).
    final enriched = [
      for (final p in filtered)
        _EnrichedPlace(
          savedPlace: p,
          status: PlaceStatusCalculator.compute(
            p.place,
            now: now,
            use24HourFormat: use24h,
          ),
        ),
    ];

    final groups = _groupByStatus(enriched);

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: context.places.anchor,
      backgroundColor: context.places.paperRaised,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _TodayStrip()),
          SliverToBoxAdapter(
            child: _FilterChips(
              filter: filter,
              counts: _filterCounts(allPlaces),
              onChanged: onFilterChanged,
            ),
          ),
          for (final group in groups) ...[
            SliverToBoxAdapter(child: _SectionHeader(group: group)),
            if (viewMode == _ViewMode.list)
              SliverList.builder(
                itemCount: group.places.length,
                itemBuilder: (context, i) {
                  final ep = group.places[i];
                  return _RowRouter(
                    enriched: ep,
                    onRefresh: onRefresh,
                    isLast: i == group.places.length - 1,
                  );
                },
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PlacesSpacing.lg,
                ),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisExtent: 168,
                    crossAxisSpacing: PlacesSpacing.md,
                    mainAxisSpacing: PlacesSpacing.md,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final ep = group.places[i];
                    return _TileRouter(enriched: ep, onRefresh: onRefresh);
                  }, childCount: group.places.length),
                ),
              ),
          ],
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  static List<_StatusGroup> _groupByStatus(List<_EnrichedPlace> enriched) {
    final groups = <PlaceStatusKind, List<_EnrichedPlace>>{
      PlaceStatusKind.open: [],
      PlaceStatusKind.closingSoon: [],
      PlaceStatusKind.closed: [],
      PlaceStatusKind.unknown: [],
    };
    for (final e in enriched) {
      groups[e.status.kind]!.add(e);
    }
    // Within Open: pinned first, then by nextChange ascending (closing soonest first).
    groups[PlaceStatusKind.open]!.sort((a, b) {
      if (a.savedPlace.isPinned != b.savedPlace.isPinned) {
        return a.savedPlace.isPinned ? -1 : 1;
      }
      final an = a.status.nextChange;
      final bn = b.status.nextChange;
      if (an == null) return 1;
      if (bn == null) return -1;
      return an.compareTo(bn);
    });
    groups[PlaceStatusKind.closingSoon]!.sort(
      (a, b) => (a.status.nextChange ?? DateTime.now()).compareTo(
        b.status.nextChange ?? DateTime.now(),
      ),
    );
    groups[PlaceStatusKind.closed]!.sort((a, b) {
      final an = a.status.nextChange;
      final bn = b.status.nextChange;
      if (an == null) return 1;
      if (bn == null) return -1;
      return an.compareTo(bn);
    });
    groups[PlaceStatusKind.unknown]!.sort(
      (a, b) => (a.savedPlace.customName ?? a.savedPlace.place.name).compareTo(
        b.savedPlace.customName ?? b.savedPlace.place.name,
      ),
    );
    return [
      for (final k in [
        PlaceStatusKind.open,
        PlaceStatusKind.closingSoon,
        PlaceStatusKind.closed,
        PlaceStatusKind.unknown,
      ])
        if (groups[k]!.isNotEmpty) _StatusGroup(kind: k, places: groups[k]!),
    ];
  }

  static Map<_VisitFilter, int> _filterCounts(List<SavedPlace> all) => {
    _VisitFilter.all: all.length,
    _VisitFilter.wantToVisit: all.where((p) => p.isCheckItOut).length,
    _VisitFilter.visited: all.where((p) => !p.isCheckItOut).length,
  };
}

class _EnrichedPlace {
  const _EnrichedPlace({required this.savedPlace, required this.status});
  final SavedPlace savedPlace;
  final PlaceStatus status;
}

class _StatusGroup {
  const _StatusGroup({required this.kind, required this.places});
  final PlaceStatusKind kind;
  final List<_EnrichedPlace> places;
}

// ─────────────────────────────────────────────────────────────────────
// Today's Route strip
// ─────────────────────────────────────────────────────────────────────

class _TodayStrip extends StatelessWidget {
  const _TodayStrip();

  @override
  Widget build(BuildContext context) {
    final theme = context.places;

    return BlocBuilder<TodayRouteCubit, TodayRouteState>(
      builder: (context, route) {
        if (route.isEmpty && route.autoClearedFrom == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              PlacesSpacing.lg,
              PlacesSpacing.xl,
              PlacesSpacing.lg,
              PlacesSpacing.sm,
            ),
            child: Row(
              children: [
                Text("Today's route", style: PlacesType.label(theme.inkMuted)),
                const SizedBox(width: PlacesSpacing.sm),
                Expanded(
                  child: Text(
                    'Nothing on today\'s plan yet.',
                    style: PlacesType.bodySmall(theme.inkMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            0,
            PlacesSpacing.lg,
            0,
            PlacesSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (route.autoClearedFrom != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PlacesSpacing.lg,
                    0,
                    PlacesSpacing.lg,
                    PlacesSpacing.sm,
                  ),
                  child: Semantics(
                    button: true,
                    label: "Dismiss route reset notification",
                    child: GestureDetector(
                      onTap: () =>
                          context.read<TodayRouteCubit>().dismissResetNote(),
                      child: Text(
                        "Today's route reset for ${_friendlyDate(DateTime.now())}.",
                        style: PlacesType.bodySmall(theme.inkMuted),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PlacesSpacing.lg,
                  0,
                  PlacesSpacing.lg,
                  PlacesSpacing.sm,
                ),
                child: Text(
                  "Today's route",
                  style: PlacesType.label(theme.inkMuted),
                ),
              ),
              if (route.tomtomIds.isNotEmpty)
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: PlacesSpacing.lg,
                    ),
                    itemCount: route.tomtomIds.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: PlacesSpacing.sm),
                    itemBuilder: (context, i) =>
                        _TodayStopCard(tomtomId: route.tomtomIds[i], index: i),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _friendlyDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }
}

class _TodayStopCard extends StatelessWidget {
  const _TodayStopCard({required this.tomtomId, required this.index});

  final String tomtomId;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    // Resolve display info from the cached bookmarks list above; the
    // FutureBuilder upstream already has it. We re-fetch lightly here.
    return FutureBuilder<List<SavedPlace>>(
      future: context.read<ApiService>().getBookmarks(),
      builder: (context, snap) {
        final places = snap.data ?? const <SavedPlace>[];
        final match = places.cast<SavedPlace?>().firstWhere(
          (p) => p?.place.tomtomId == tomtomId,
          orElse: () => null,
        );
        final use24 = context.watch<PreferencesCubit>().state.use24HourFormat;
        final status = match == null
            ? const PlaceStatus(kind: PlaceStatusKind.unknown, supporting: '')
            : PlaceStatusCalculator.compute(
                match.place,
                now: DateTime.now(),
                use24HourFormat: use24,
              );
        final name = match == null
            ? 'Loading…'
            : (match.customName ?? match.place.name);

        return Semantics(
          button: true,
          label: 'Route stop: $name. Long press to open options menu.',
          child: GestureDetector(
            onLongPress: () => _showStopMenu(context, tomtomId, index),
            child: Container(
              width: 220,
              padding: const EdgeInsets.all(PlacesSpacing.md),
              decoration: BoxDecoration(
                color: theme.paperRaised,
                borderRadius: BorderRadius.circular(PlacesRadius.md),
                border: Border.all(color: theme.ashSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: theme.anchor,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: theme.anchorOnContrast,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: PlacesSpacing.sm),
                      Expanded(
                        child: Text(
                          name,
                          style: PlacesType.title(
                            theme.ink,
                          ).copyWith(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  StatusPill(status: status),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showStopMenu(BuildContext context, String tomtomId, int index) {
    final theme = context.places;
    final cubit = context.read<TodayRouteCubit>();
    final total = cubit.state.tomtomIds.length;
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.paperRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PlacesRadius.lg),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: PlacesSpacing.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.ash,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (index > 0)
              ListTile(
                leading: const Icon(Icons.arrow_back_rounded),
                title: const Text('Move earlier'),
                onTap: () {
                  cubit.reorder(index, index - 1);
                  Navigator.pop(ctx);
                },
              ),
            if (index < total - 1)
              ListTile(
                leading: const Icon(Icons.arrow_forward_rounded),
                title: const Text('Move later'),
                onTap: () {
                  cubit.reorder(index, index + 2);
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              leading: Icon(Icons.close_rounded, color: theme.closingColor),
              title: const Text('Remove from today'),
              onTap: () {
                cubit.remove(tomtomId);
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: PlacesSpacing.sm),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Filter chips
// ─────────────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.filter,
    required this.counts,
    required this.onChanged,
  });

  final _VisitFilter filter;
  final Map<_VisitFilter, int> counts;
  final ValueChanged<_VisitFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlacesSpacing.lg,
        PlacesSpacing.md,
        PlacesSpacing.lg,
        PlacesSpacing.md,
      ),
      child: Wrap(
        spacing: PlacesSpacing.sm,
        children: [
          _chip(context, _VisitFilter.all, 'All'),
          _chip(context, _VisitFilter.wantToVisit, 'Want to visit'),
          _chip(context, _VisitFilter.visited, 'Visited'),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, _VisitFilter value, String label) {
    final theme = context.places;
    final active = filter == value;
    final count = counts[value] ?? 0;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(PlacesRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PlacesSpacing.md,
          vertical: PlacesSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: active ? theme.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(PlacesRadius.pill),
          border: Border.all(color: active ? theme.ink : theme.ash, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? theme.paper : theme.ink,
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: PlacesSpacing.xs),
            Text(
              '$count',
              style: TextStyle(
                color: active
                    ? theme.paper.withValues(alpha: 0.7)
                    : theme.inkMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.group});

  final _StatusGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlacesSpacing.lg,
        PlacesSpacing.lg,
        PlacesSpacing.lg,
        PlacesSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: theme.statusColor(group.kind),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: PlacesSpacing.sm),
          Text(
            _labelFor(group.kind),
            style: PlacesType.label(
              theme.ink,
            ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
          const SizedBox(width: PlacesSpacing.sm),
          Text(
            '${group.places.length}',
            style: PlacesType.label(theme.inkMuted),
          ),
        ],
      ),
    );
  }

  static String _labelFor(PlaceStatusKind k) => switch (k) {
    PlaceStatusKind.open => 'OPEN NOW',
    PlaceStatusKind.closingSoon => 'CLOSES SOON',
    PlaceStatusKind.closed => 'CLOSED',
    PlaceStatusKind.unknown => 'HOURS UNKNOWN',
  };
}

// ─────────────────────────────────────────────────────────────────────
// Row / Tile routers (connect cubit + actions)
// ─────────────────────────────────────────────────────────────────────

class _RowRouter extends StatelessWidget {
  const _RowRouter({
    required this.enriched,
    required this.onRefresh,
    required this.isLast,
  });

  final _EnrichedPlace enriched;
  final Future<void> Function() onRefresh;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TodayRouteCubit, TodayRouteState>(
      buildWhen: (a, b) =>
          a.contains(enriched.savedPlace.place.tomtomId) !=
          b.contains(enriched.savedPlace.place.tomtomId),
      builder: (context, route) {
        final onToday = route.contains(enriched.savedPlace.place.tomtomId);
        return SavedPlaceRow(
          savedPlace: enriched.savedPlace,
          status: enriched.status,
          isOnToday: onToday,
          onTap: () => _openDetail(context, enriched, onRefresh),
          onToggleToday: () => _toggleToday(context, enriched, onToday),
          onLongPress: () => _openActionSheet(context, enriched, onRefresh),
          showDivider: !isLast,
        );
      },
    );
  }
}

class _TileRouter extends StatelessWidget {
  const _TileRouter({required this.enriched, required this.onRefresh});

  final _EnrichedPlace enriched;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TodayRouteCubit, TodayRouteState>(
      buildWhen: (a, b) =>
          a.contains(enriched.savedPlace.place.tomtomId) !=
          b.contains(enriched.savedPlace.place.tomtomId),
      builder: (context, route) {
        final onToday = route.contains(enriched.savedPlace.place.tomtomId);
        return SavedPlaceTile(
          savedPlace: enriched.savedPlace,
          status: enriched.status,
          isOnToday: onToday,
          onTap: () => _openDetail(context, enriched, onRefresh),
          onToggleToday: () => _toggleToday(context, enriched, onToday),
          onLongPress: () => _openActionSheet(context, enriched, onRefresh),
        );
      },
    );
  }
}

void _toggleToday(
  BuildContext context,
  _EnrichedPlace enriched,
  bool currentlyOn,
) {
  final cubit = context.read<TodayRouteCubit>();
  final id = enriched.savedPlace.place.tomtomId;
  if (currentlyOn) {
    cubit.remove(id);
  } else {
    cubit.add(id);
  }
}

void _openDetail(
  BuildContext context,
  _EnrichedPlace enriched,
  Future<void> Function() onRefresh,
) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlaceDetailScreen(place: enriched.savedPlace.place),
    ),
  ).then((_) => onRefresh());
}

void _openActionSheet(
  BuildContext context,
  _EnrichedPlace enriched,
  Future<void> Function() onRefresh,
) {
  final theme = context.places;
  final api = context.read<ApiService>();
  final todayCubit = context.read<TodayRouteCubit>();
  final sp = enriched.savedPlace;
  showModalBottomSheet(
    context: context,
    backgroundColor: theme.paperRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PlacesRadius.lg),
      ),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: PlacesSpacing.sm),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.ash,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PlacesSpacing.lg,
              PlacesSpacing.md,
              PlacesSpacing.lg,
              PlacesSpacing.sm,
            ),
            child: Text(
              sp.customName ?? sp.place.name,
              style: PlacesType.title(theme.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ListTile(
            leading: Icon(
              sp.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: theme.anchor,
            ),
            title: Text(sp.isPinned ? 'Unpin' : 'Pin'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await api.togglePinPlace(sp.place.tomtomId, !sp.isPinned);
                onRefresh();
              } catch (_) {}
            },
          ),
          ListTile(
            leading: Icon(
              sp.isCheckItOut
                  ? Icons.check_circle_outline
                  : Icons.visibility_off_outlined,
              color: theme.inkMuted,
            ),
            title: Text(
              sp.isCheckItOut ? 'Mark as visited' : 'Move to want to visit',
            ),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await api.toggleCheckItOut(sp.place.tomtomId, !sp.isCheckItOut);
                onRefresh();
              } catch (_) {}
            },
          ),
          ListTile(
            leading: Icon(Icons.edit_outlined, color: theme.inkMuted),
            title: const Text('Edit details'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaceDetailScreen(place: sp.place),
                ),
              ).then((_) => onRefresh());
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.closingColor),
            title: Text('Remove', style: TextStyle(color: theme.closingColor)),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await api.deleteBookmark(sp.place.tomtomId);
                todayCubit.remove(sp.place.tomtomId);
                onRefresh();
              } catch (_) {}
            },
          ),
          const SizedBox(height: PlacesSpacing.sm),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────
// States: skeleton / empty / error
// ─────────────────────────────────────────────────────────────────────

class _SkeletonList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return ListView.separated(
      padding: const EdgeInsets.only(top: PlacesSpacing.lg),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 0),
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.fromLTRB(
          PlacesSpacing.lg,
          PlacesSpacing.md,
          PlacesSpacing.lg,
          PlacesSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShimmerBox(
              width: 28,
              height: 28,
              radius: 14,
              color: theme.ashSoft,
            ),
            const SizedBox(width: PlacesSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShimmerBox(width: 180, height: 16, color: theme.ashSoft),
                  const SizedBox(height: PlacesSpacing.sm),
                  _ShimmerBox(width: 220, height: 12, color: theme.ashSoft),
                  const SizedBox(height: PlacesSpacing.sm),
                  _ShimmerBox(
                    width: 110,
                    height: 22,
                    radius: 11,
                    color: theme.ashSoft,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.color,
    this.radius = 4,
  });
  final double width;
  final double height;
  final Color color;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(PlacesSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A pocket of places.',
                style: PlacesType.display(theme.ink).copyWith(fontSize: 28),
              ),
              const SizedBox(height: PlacesSpacing.md),
              Text(
                "No places saved yet. Save somewhere you go, and we'll keep "
                "hours, status, and your today's route within reach.",
                style: PlacesType.body(theme.inkMuted),
              ),
              const SizedBox(height: PlacesSpacing.xl),
              Row(
                children: [
                  _PrimaryAction(
                    label: 'Find a place',
                    icon: Icons.search_rounded,
                    onPressed: () {
                      // Search lives outside this screen; surface the affordance
                      // and let the user navigate via the side menu / home shell.
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: theme.paperRaised,
                          content: Text(
                            'Use Search from the menu to find places.',
                            style: PlacesType.body(theme.ink),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: PlacesSpacing.sm),
                  _SecondaryAction(
                    label: 'Add a custom place',
                    icon: Icons.add_location_alt_outlined,
                    onPressed: () => _openQuickAdd(context),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PlacesSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't load your places.",
              style: PlacesType.title(theme.ink),
            ),
            const SizedBox(height: PlacesSpacing.sm),
            Text(
              'Check your connection and try again.',
              style: PlacesType.bodySmall(theme.inkMuted),
            ),
            const SizedBox(height: PlacesSpacing.lg),
            _PrimaryAction(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Material(
      color: theme.anchor,
      borderRadius: BorderRadius.circular(PlacesRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(PlacesRadius.md),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PlacesSpacing.lg,
            vertical: PlacesSpacing.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: theme.anchorOnContrast),
              const SizedBox(width: PlacesSpacing.sm),
              Text(
                label,
                style: TextStyle(
                  color: theme.anchorOnContrast,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(PlacesRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PlacesSpacing.lg,
          vertical: PlacesSpacing.md,
        ),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(PlacesRadius.md),
          border: Border.all(color: theme.ash),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.ink),
            const SizedBox(width: PlacesSpacing.sm),
            Text(
              label,
              style: TextStyle(
                color: theme.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openQuickAdd(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const QuickAddPlaceSheet(),
  );
}
