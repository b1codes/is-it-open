import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/preferences/preferences_cubit.dart';
import '../../bloc/today/today_cubit.dart';
import '../../components/places/address_map_thumb.dart';
import '../../components/places/status_pill.dart';
import '../../models/hours.dart';
import '../../models/place.dart';
import '../../models/saved_place.dart';
import '../../services/api_service.dart';
import '../../utils/graphics_helper.dart';
import '../../utils/place_status.dart';
import '../../utils/navigation.dart';
import '../../utils/places_theme.dart';
import 'plan_visit_screen.dart';

class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({super.key, required this.place});

  final Place place;

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  SavedPlace? _saved;
  // _saved's position in the saved places, which picks its fallback color.
  int _savedIndex = 0;
  bool _loadingSaved = true;

  bool get _isCustomPlace => widget.place.tomtomId.startsWith('custom_');

  @override
  void initState() {
    super.initState();
    _hydrateSaved();
  }

  Future<void> _hydrateSaved() async {
    try {
      final bookmarks = await context.read<ApiService>().getBookmarks();
      final index = bookmarks.indexWhere(
        (b) => b.place.tomtomId == widget.place.tomtomId,
      );
      if (mounted) {
        setState(() {
          _saved = index < 0 ? null : bookmarks[index];
          _savedIndex = index < 0 ? 0 : index;
          _loadingSaved = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  Future<void> _saveAndAddToToday() async {
    final api = context.read<ApiService>();
    final today = context.read<TodayRouteCubit>();
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _loadingSaved = true);
    try {
      if (_saved == null) {
        await api.savePlace(widget.place);
        await api.bookmarkPlace(widget.place.tomtomId);
      }
      await today.add(widget.place.tomtomId);
      await _hydrateSaved();
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text("Couldn't add to today.")));
      setState(() => _loadingSaved = false);
    }
  }

  Future<void> _removeFromToday() async {
    await context.read<TodayRouteCubit>().remove(widget.place.tomtomId);
  }

  Future<void> _removeFromSaved() async {
    final api = context.read<ApiService>();
    final today = context.read<TodayRouteCubit>();
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    try {
      await api.deleteBookmark(widget.place.tomtomId);
      await today.remove(widget.place.tomtomId);
      closeRoute(nav, route);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final use24h = context.watch<PreferencesCubit>().state.use24HourFormat;
    final now = clock.now();
    final status = PlaceStatusCalculator.compute(
      widget.place,
      now: now,
      use24HourFormat: use24h,
    );

    return Scaffold(
      backgroundColor: theme.paper,
      appBar: AppBar(
        backgroundColor: theme.paper,
        surfaceTintColor: theme.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: theme.ink,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_saved != null)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz_rounded, color: theme.inkMuted),
              tooltip: 'More options',
              color: theme.paperRaised,
              onSelected: (v) {
                if (v == 'remove') _removeFromSaved();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from saved'),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            PlacesSpacing.lg,
            0,
            PlacesSpacing.lg,
            120,
          ),
          children: [
            const SizedBox(height: PlacesSpacing.sm),
            _Hero(
              place: widget.place,
              savedPlace: _saved,
              savedIndex: _savedIndex,
              status: status,
            ),
            const SizedBox(height: PlacesSpacing.lg),
            _AddressBlock(place: widget.place),
            if (widget.place.hours.isNotEmpty) ...[
              const SizedBox(height: PlacesSpacing.xxl),
              _HoursTable(
                hours: widget.place.hours,
                today: now.weekday - 1,
                use24h: use24h,
              ),
            ] else if (_isCustomPlace) ...[
              const SizedBox(height: PlacesSpacing.xxl),
              _HoursPlaceholder(onAddHours: _showHoursEditor),
            ],
            if (_saved != null) ...[
              const SizedBox(height: PlacesSpacing.xxl),
              _PlanVisitEntry(saved: _saved!, onOpen: _openPlanVisit),
            ],
            if (widget.place.phone != null || widget.place.website != null) ...[
              const SizedBox(height: PlacesSpacing.xxl),
              _ContactBlock(place: widget.place),
            ],
            if (_saved != null && _isCustomPlace) ...[
              const SizedBox(height: PlacesSpacing.xxl),
              _CustomPlaceAffordances(saved: _saved!, onChanged: _hydrateSaved),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PlacesSpacing.lg,
            PlacesSpacing.sm,
            PlacesSpacing.lg,
            PlacesSpacing.md,
          ),
          child: BlocBuilder<TodayRouteCubit, TodayRouteState>(
            builder: (context, route) {
              final isOn = route.contains(widget.place.tomtomId);
              return _StickyCTA(
                loading: _loadingSaved,
                isOnToday: isOn,
                onAdd: _saveAndAddToToday,
                onRemove: _removeFromToday,
              );
            },
          ),
        ),
      ),
    );
  }

  void _showHoursEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HoursEditorSheet(place: widget.place),
    ).then((_) => _hydrateSaved());
  }

  void _openPlanVisit() {
    final saved = _saved;
    if (saved == null) return;
    Navigator.push<int?>(
      context,
      MaterialPageRoute(
        builder: (_) => PlanVisitScreen(place: widget.place, saved: saved),
      ),
    ).then((_) => _hydrateSaved());
  }
}

// ─────────────────────────────────────────────────────────────────────
// Hero
// ─────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({
    required this.place,
    required this.savedPlace,
    required this.savedIndex,
    required this.status,
  });

  final Place place;
  final SavedPlace? savedPlace;
  final int savedIndex;
  final PlaceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final name = savedPlace?.customName ?? place.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (savedPlace != null)
          Padding(
            padding: const EdgeInsets.only(bottom: PlacesSpacing.md),
            child: GraphicsHelper.buildProfileGraphic(
              savedPlace!,
              savedIndex,
              size: 40,
            ),
          ),
        Text(name, style: PlacesType.display(theme.ink)),
        if (place.categories.isNotEmpty) ...[
          const SizedBox(height: PlacesSpacing.xs),
          Text(
            place.categories.first.replaceAll('_', ' '),
            style: PlacesType.label(theme.inkMuted),
          ),
        ],
        const SizedBox(height: PlacesSpacing.lg),
        StatusPill(status: status, size: StatusPillSize.medium),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Address
// ─────────────────────────────────────────────────────────────────────

class _AddressBlock extends StatelessWidget {
  const _AddressBlock({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final hasMap = AddressMapThumb.hasUsableLocation(place.location);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place_outlined, size: 20, color: theme.inkMuted),
              const SizedBox(width: PlacesSpacing.sm),
              Expanded(
                child: Text(place.address, style: PlacesType.body(theme.ink)),
              ),
            ],
          ),
        ),
        if (hasMap) ...[
          const SizedBox(width: PlacesSpacing.md),
          AddressMapThumb(location: place.location),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Weekly hours table
// ─────────────────────────────────────────────────────────────────────

class _HoursTable extends StatelessWidget {
  const _HoursTable({
    required this.hours,
    required this.today,
    required this.use24h,
  });

  final List<BusinessHours> hours;
  final int today; // 0..6 Mon..Sun
  final bool use24h;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hours', style: PlacesType.headline(theme.ink)),
        const SizedBox(height: PlacesSpacing.md),
        for (var d = 0; d < 7; d++)
          _HoursRow(
            label: labels[d],
            isToday: d == today,
            blocks: hours.where((h) => h.dayOfWeek == d).toList(),
            use24h: use24h,
          ),
      ],
    );
  }
}

class _HoursRow extends StatelessWidget {
  const _HoursRow({
    required this.label,
    required this.isToday,
    required this.blocks,
    required this.use24h,
  });

  final String label;
  final bool isToday;
  final List<BusinessHours> blocks;
  final bool use24h;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final highlightBg = isToday ? theme.anchor.withValues(alpha: 0.08) : null;

    return Container(
      decoration: BoxDecoration(
        color: highlightBg,
        borderRadius: BorderRadius.circular(PlacesRadius.sm),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: PlacesSpacing.sm,
        vertical: PlacesSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wide enough for the dot plus the widest bold label ("Wed").
          SizedBox(
            width: 52,
            child: Row(
              children: [
                if (isToday)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: theme.anchor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                // Clips rather than overflowing at large text scales.
                Flexible(
                  child: Text(
                    label,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: PlacesType.body(isToday ? theme.ink : theme.inkMuted)
                        .copyWith(
                          fontWeight: isToday
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: PlacesSpacing.md),
          Expanded(
            child: blocks.isEmpty
                ? Text('Closed', style: PlacesType.body(theme.inkMuted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final b in blocks)
                        Text(
                          '${_fmt(b.openTime.hour, b.openTime.minute, use24h)} – '
                          '${_fmt(b.closeTime.hour, b.closeTime.minute, use24h)}',
                          style: PlacesType.body(
                            isToday ? theme.ink : theme.inkMuted,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int h, int m, bool use24) {
    if (use24) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final suffix = h < 12 ? 'am' : 'pm';
    if (m == 0) return '$hour12$suffix';
    return '$hour12:${m.toString().padLeft(2, '0')}$suffix';
  }
}

// ─────────────────────────────────────────────────────────────────────
// Plan visit entry
// ─────────────────────────────────────────────────────────────────────

class _PlanVisitEntry extends StatelessWidget {
  const _PlanVisitEntry({required this.saved, required this.onOpen});

  final SavedPlace saved;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final mins = saved.averageVisitLength;
    final hasValue = mins != null;

    return Material(
      color: theme.paperRaised,
      borderRadius: BorderRadius.circular(PlacesRadius.md),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(PlacesRadius.md),
        child: Container(
          padding: const EdgeInsets.all(PlacesSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PlacesRadius.md),
            border: Border.all(color: theme.ashSoft),
          ),
          child: Row(
            children: [
              Icon(
                Icons.schedule_outlined,
                color: hasValue ? theme.anchor : theme.inkMuted,
                size: 22,
              ),
              const SizedBox(width: PlacesSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plan visit', style: PlacesType.title(theme.ink)),
                    const SizedBox(height: 2),
                    Text(
                      hasValue
                          ? 'Typical visit ${_formatDuration(mins)}. Check if it fits.'
                          : 'Set a typical length to see if it fits your day.',
                      style: PlacesType.bodySmall(theme.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PlacesSpacing.sm),
              if (hasValue)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PlacesSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.anchor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(PlacesRadius.pill),
                  ),
                  child: Text(
                    _formatDuration(mins),
                    style: TextStyle(
                      color: theme.anchor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Icon(Icons.chevron_right_rounded, color: theme.inkMuted),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDuration(int? mins) {
    if (mins == null) return '';
    if (mins < 60) return '$mins min';
    final hrs = mins / 60;
    if (hrs == hrs.truncateToDouble()) return '${hrs.toInt()} hr';
    return '${hrs.toStringAsFixed(1)} hr';
  }
}

// ─────────────────────────────────────────────────────────────────────
// Empty hours (custom places)
// ─────────────────────────────────────────────────────────────────────

class _HoursPlaceholder extends StatelessWidget {
  const _HoursPlaceholder({required this.onAddHours});
  final VoidCallback onAddHours;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Container(
      padding: const EdgeInsets.all(PlacesSpacing.lg),
      decoration: BoxDecoration(
        color: theme.paperRaised,
        borderRadius: BorderRadius.circular(PlacesRadius.md),
        border: Border.all(color: theme.ashSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_outlined, color: theme.inkMuted),
          const SizedBox(width: PlacesSpacing.md),
          Expanded(
            child: Text(
              'No hours yet for this place.',
              style: PlacesType.body(theme.inkMuted),
            ),
          ),
          TextButton(
            onPressed: onAddHours,
            style: TextButton.styleFrom(foregroundColor: theme.anchor),
            child: const Text('Add hours'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Contact
// ─────────────────────────────────────────────────────────────────────

class _ContactBlock extends StatelessWidget {
  const _ContactBlock({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Contact', style: PlacesType.headline(theme.ink)),
        const SizedBox(height: PlacesSpacing.md),
        if (place.phone != null && place.phone!.isNotEmpty)
          _ContactRow(icon: Icons.phone_outlined, text: place.phone!),
        if (place.website != null && place.website!.isNotEmpty)
          _ContactRow(icon: Icons.language_outlined, text: place.website!),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PlacesSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.inkMuted),
          const SizedBox(width: PlacesSpacing.md),
          Expanded(child: Text(text, style: PlacesType.body(theme.ink))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Custom-place affordances
// ─────────────────────────────────────────────────────────────────────

class _CustomPlaceAffordances extends StatefulWidget {
  const _CustomPlaceAffordances({required this.saved, required this.onChanged});

  final SavedPlace saved;
  final VoidCallback onChanged;

  @override
  State<_CustomPlaceAffordances> createState() =>
      _CustomPlaceAffordancesState();
}

class _CustomPlaceAffordancesState extends State<_CustomPlaceAffordances> {
  late final TextEditingController _label;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(
      text: widget.saved.customName ?? widget.saved.place.name,
    );
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _saveLabel() async {
    setState(() => _saving = true);
    try {
      await context.read<ApiService>().updateBookmarkGraphic(
        widget.saved.place.tomtomId,
        widget.saved.icon,
        widget.saved.color,
        // An empty name clears the label; null would leave it unchanged.
        customName: _label.text.trim(),
      );
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save the label.")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Custom place', style: PlacesType.headline(theme.ink)),
        const SizedBox(height: PlacesSpacing.md),
        TextField(
          controller: _label,
          style: PlacesType.body(theme.ink),
          decoration: InputDecoration(
            labelText: 'Label',
            labelStyle: PlacesType.label(theme.inkMuted),
            filled: true,
            fillColor: theme.paperRaised,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(PlacesRadius.sm),
              borderSide: BorderSide(color: theme.ash),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(PlacesRadius.sm),
              borderSide: BorderSide(color: theme.ashSoft),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(PlacesRadius.sm),
              borderSide: BorderSide(color: theme.anchor, width: 2),
            ),
          ),
          onSubmitted: (_) => _saveLabel(),
        ),
        const SizedBox(height: PlacesSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _saving ? null : _saveLabel,
            style: TextButton.styleFrom(foregroundColor: theme.anchor),
            child: Text(_saving ? 'Saving…' : 'Save label'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Sticky CTA
// ─────────────────────────────────────────────────────────────────────

class _StickyCTA extends StatelessWidget {
  const _StickyCTA({
    required this.loading,
    required this.isOnToday,
    required this.onAdd,
    required this.onRemove,
  });

  final bool loading;
  final bool isOnToday;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final bg = isOnToday ? theme.paperRaised : theme.anchor;
    final fg = isOnToday ? theme.ink : theme.anchorOnContrast;
    final border = isOnToday
        ? Border.all(color: theme.anchor, width: 1.5)
        : null;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(PlacesRadius.md),
          border: border,
        ),
        child: InkWell(
          onTap: loading ? null : (isOnToday ? onRemove : onAdd),
          borderRadius: BorderRadius.circular(PlacesRadius.md),
          // At least 56 high, and taller when large text on a small phone
          // wraps the label.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PlacesSpacing.md,
                vertical: PlacesSpacing.sm,
              ),
              child: Center(
                heightFactor: 1,
                child: loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(fg),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOnToday ? Icons.check_rounded : Icons.add_rounded,
                            color: fg,
                          ),
                          const SizedBox(width: PlacesSpacing.sm),
                          Flexible(
                            child: Text(
                              isOnToday
                                  ? "On today's route"
                                  : "Add to today's route",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: fg,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Hours editor sheet (custom places)
// ─────────────────────────────────────────────────────────────────────

class _HoursEditorSheet extends StatelessWidget {
  const _HoursEditorSheet({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.paperRaised,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(PlacesRadius.lg),
          ),
        ),
        padding: const EdgeInsets.all(PlacesSpacing.lg),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: PlacesSpacing.lg),
              Text('Edit hours', style: PlacesType.headline(theme.ink)),
              const SizedBox(height: PlacesSpacing.sm),
              Text(
                'Hours editing arrives in a follow-up pass. For now, '
                'submit the place and edit hours from the calendar surface.',
                style: PlacesType.bodySmall(theme.inkMuted),
              ),
              const SizedBox(height: PlacesSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: theme.anchor),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
