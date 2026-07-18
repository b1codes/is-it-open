import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/preferences/preferences_cubit.dart';
import '../../models/hours.dart';
import '../../models/place.dart';
import '../../models/saved_place.dart';
import '../../services/api_service.dart';
import '../../utils/places_theme.dart';

class PlanVisitScreen extends StatefulWidget {
  const PlanVisitScreen({super.key, required this.place, required this.saved});

  final Place place;
  final SavedPlace saved;

  @override
  State<PlanVisitScreen> createState() => _PlanVisitScreenState();
}

class _PlanVisitScreenState extends State<PlanVisitScreen> {
  static const _presets = <int?>[null, 15, 30, 45, 60, 90, 120, 180, 240];

  int? _current;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _current = widget.saved.averageVisitLength;
  }

  Future<void> _select(int? minutes) async {
    if (_current == minutes) return;
    final previous = _current;
    setState(() {
      _current = minutes;
      _saving = true;
    });
    try {
      await context.read<ApiService>().updateVisitLength(
        widget.place.tomtomId,
        minutes,
      );
    } catch (e) {
      setState(() => _current = previous);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update visit length.")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final use24h = context.watch<PreferencesCubit>().state.use24HourFormat;
    final name = widget.saved.customName ?? widget.place.name;
    final today = DateTime.now().weekday - 1;
    final todayBlocks =
        widget.place.hours.where((h) => h.dayOfWeek == today).toList()
          ..sort((a, b) => _mins(a.openTime).compareTo(_mins(b.openTime)));

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
          onPressed: () => Navigator.pop(context, _current),
        ),
        title: Text('Plan visit', style: PlacesType.headline(theme.ink)),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            PlacesSpacing.lg,
            PlacesSpacing.md,
            PlacesSpacing.lg,
            PlacesSpacing.xxl,
          ),
          children: [
            Text(
              name,
              style: PlacesType.display(theme.ink).copyWith(fontSize: 26),
            ),
            const SizedBox(height: PlacesSpacing.lg),
            _SectionLabel('Typical visit'),
            const SizedBox(height: PlacesSpacing.sm),
            Text(
              _current == null
                  ? "No typical length set. Pick one and we'll check it against this week's hours and your calendar."
                  : "We'll use ${_formatDuration(_current)} when checking whether a visit fits.",
              style: PlacesType.body(theme.inkMuted),
            ),
            const SizedBox(height: PlacesSpacing.lg),
            Wrap(
              spacing: PlacesSpacing.sm,
              runSpacing: PlacesSpacing.sm,
              children: [
                for (final preset in _presets)
                  _DurationChip(
                    label: _formatDuration(preset),
                    selected: preset == _current,
                    enabled: !_saving,
                    onTap: () => _select(preset),
                  ),
              ],
            ),
            if (todayBlocks.isNotEmpty) ...[
              const SizedBox(height: PlacesSpacing.xxl),
              _SectionLabel("Today's windows"),
              const SizedBox(height: PlacesSpacing.sm),
              Text(
                _current == null
                    ? "When this place is open today."
                    : "Windows long enough for a ${_formatDuration(_current)} visit are marked.",
                style: PlacesType.body(theme.inkMuted),
              ),
              const SizedBox(height: PlacesSpacing.md),
              for (final b in todayBlocks)
                _WindowRow(block: b, visitLength: _current, use24h: use24h),
            ] else ...[
              const SizedBox(height: PlacesSpacing.xxl),
              _SectionLabel("Today's windows"),
              const SizedBox(height: PlacesSpacing.sm),
              Text(
                widget.place.hours.isEmpty
                    ? "No hours on file for this place."
                    : 'Closed today.',
                style: PlacesType.body(theme.inkMuted),
              ),
            ],
            const SizedBox(height: PlacesSpacing.xxl),
            _CalendarNote(),
          ],
        ),
      ),
    );
  }

  static int _mins(TimeOfDay t) => t.hour * 60 + t.minute;

  static String _formatDuration(int? mins) {
    if (mins == null) return 'No length';
    if (mins < 60) return '$mins min';
    final hrs = mins / 60;
    if (hrs == hrs.truncateToDouble()) {
      return '${hrs.toInt()} hr';
    }
    return '${hrs.toStringAsFixed(1)} hr';
  }
}

// ─────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Text(
      text,
      style: PlacesType.label(
        theme.inkMuted,
      ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Semantics(
      button: true,
      selected: selected,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.6,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(PlacesRadius.pill),
          child: AnimatedContainer(
            duration: PlacesMotion.standard,
            curve: PlacesMotion.curve,
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: PlacesSpacing.lg,
              vertical: PlacesSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: selected ? theme.anchor : Colors.transparent,
              borderRadius: BorderRadius.circular(PlacesRadius.pill),
              border: Border.all(
                color: selected ? theme.anchor : theme.ash,
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? theme.anchorOnContrast : theme.ink,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowRow extends StatelessWidget {
  const _WindowRow({
    required this.block,
    required this.visitLength,
    required this.use24h,
  });

  final BusinessHours block;
  final int? visitLength;
  final bool use24h;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final now = DateTime.now();
    final openMin = block.openTime.hour * 60 + block.openTime.minute;
    var closeMin = block.closeTime.hour * 60 + block.closeTime.minute;
    if (closeMin <= openMin) closeMin = 24 * 60; // cross-midnight: cap at today
    final nowMin = now.hour * 60 + now.minute;

    final effectiveStart = nowMin > openMin && nowMin < closeMin
        ? nowMin
        : openMin;
    final remaining = closeMin - effectiveStart;
    final fullDuration = closeMin - openMin;
    final inProgress = nowMin >= openMin && nowMin < closeMin;
    final passed = nowMin >= closeMin;

    final visit = visitLength;
    final fits = visit == null || remaining >= visit;
    final wouldHaveFit = visit == null || fullDuration >= visit;

    Color statusColor;
    String hint;
    if (passed) {
      statusColor = theme.inkMuted;
      hint = 'Already closed.';
    } else if (!fits && inProgress) {
      statusColor = theme.closingColor;
      hint = "Less than ${_formatMin(visitLength!)} left.";
    } else if (inProgress) {
      statusColor = theme.openColor;
      hint = "${_formatMin(remaining)} left in this window.";
    } else if (!wouldHaveFit) {
      statusColor = theme.closingColor;
      hint = "Shorter than ${_formatMin(visitLength!)}.";
    } else {
      statusColor = theme.ink;
      hint = "${_formatMin(fullDuration)} window.";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: PlacesSpacing.sm),
      padding: const EdgeInsets.all(PlacesSpacing.md),
      decoration: BoxDecoration(
        color: theme.paperRaised,
        borderRadius: BorderRadius.circular(PlacesRadius.md),
        border: Border.all(color: theme.ashSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: PlacesSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_fmtClock(block.openTime.hour, block.openTime.minute, use24h)} – '
                  '${_fmtClock(block.closeTime.hour, block.closeTime.minute, use24h)}',
                  style: PlacesType.title(theme.ink),
                ),
                const SizedBox(height: PlacesSpacing.xs),
                Text(hint, style: PlacesType.bodySmall(theme.inkMuted)),
              ],
            ),
          ),
          if (visitLength != null && fits && !passed)
            Icon(Icons.check_circle_outline, color: theme.openColor, size: 22),
          if (visitLength != null && !fits)
            Icon(Icons.error_outline, color: theme.closingColor, size: 22),
        ],
      ),
    );
  }

  static String _formatMin(int mins) {
    if (mins < 60) return '$mins min';
    final hrs = mins ~/ 60;
    final rem = mins % 60;
    if (rem == 0) return '${hrs}h';
    return '${hrs}h ${rem}m';
  }

  static String _fmtClock(int h, int m, bool use24) {
    if (use24) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final suffix = h < 12 ? 'am' : 'pm';
    if (m == 0) return '$hour12$suffix';
    return '$hour12:${m.toString().padLeft(2, '0')}$suffix';
  }
}

class _CalendarNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Container(
      padding: const EdgeInsets.all(PlacesSpacing.md),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(PlacesRadius.md),
        border: Border.all(color: theme.ashSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.event_note_outlined, color: theme.inkMuted, size: 20),
          const SizedBox(width: PlacesSpacing.md),
          Expanded(
            child: Text(
              "The Calendar tab uses this length to find slots that fit between "
              "your own events. Set it once here.",
              style: PlacesType.bodySmall(theme.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
