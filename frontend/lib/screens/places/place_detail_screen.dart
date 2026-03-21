import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../models/place.dart';
import '../../models/saved_place.dart';
import '../../services/api_service.dart';
import '../../bloc/preferences/preferences_cubit.dart';
import 'package:intl/intl.dart';

class PlaceDetailScreen extends StatefulWidget {
  final Place place;

  const PlaceDetailScreen({super.key, required this.place});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

enum CalendarViewType {
  singleDay,
  threeDay,
  week,
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  CalendarViewType _currentView = CalendarViewType.week;
  DateTime _baseDate = DateTime.now();
  SavedPlace? _savedPlace;
  bool _isLoadingSavedPlace = true;
  String? _selectedIcon;
  String? _selectedColor;
  bool _isEditingGraphic = false;
  final TextEditingController _labelController = TextEditingController();
  DateTime? _plannedVisitTime;
  double _dragAccumulator = 0.0;

  final List<String> _suggestedLabels = ['Gym', 'Pharmacy', 'Grocery', 'Coffee', 'Work', 'Home', 'Restaurant'];

  final Map<String, IconData> _availableIcons = {
    'restaurant': Icons.restaurant,
    'local_cafe': Icons.local_cafe,
    'local_bar': Icons.local_bar,
    'store': Icons.store,
    'shopping_cart': Icons.shopping_cart,
    'fitness_center': Icons.fitness_center,
    'local_hospital': Icons.local_hospital,
    'park': Icons.park,
    'star': Icons.star,
    'home': Icons.home,
    'work': Icons.work,
  };

  final List<Color> _availableColors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.brown,
  ];

  @override
  void initState() {
    super.initState();
    _checkSavedStatus();
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _checkSavedStatus() async {
    try {
      final apiService = context.read<ApiService>();
      final bookmarks = await apiService.getBookmarks();
      final saved = bookmarks.cast<SavedPlace?>().firstWhere(
            (b) => b?.place.tomtomId == widget.place.tomtomId,
            orElse: () => null,
          );
      if (mounted) {
        setState(() {
          _savedPlace = saved;
          _selectedIcon = saved?.icon;
          _selectedColor = saved?.color;
          _labelController.text = saved?.customName ?? '';
          _isLoadingSavedPlace = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSavedPlace = false;
        });
      }
    }
  }

  Future<void> _updateGraphic({String? icon, String? color, String? customName}) async {
    try {
      final apiService = context.read<ApiService>();
      await apiService.updateBookmarkGraphic(widget.place.tomtomId, icon, color, customName: customName);
      
      if (_savedPlace != null) {
        setState(() {
          _savedPlace = SavedPlace(
            id: _savedPlace!.id,
            place: _savedPlace!.place,
            customName: customName != null && customName.isEmpty ? null : (customName ?? _savedPlace!.customName),
            isPinned: _savedPlace!.isPinned,
            icon: icon ?? _savedPlace!.icon,
            color: color ?? _savedPlace!.color,
          );
        });
        if (mounted) {
          setState(() {
            _isEditingGraphic = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile graphic saved successfully!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update graphic')),
        );
      }
    }
  }

  String _weekDayShortName(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[weekday - 1];
  }

  bool _isOpenDuring(DateTime visitStart, DateTime visitEnd) {
    if (widget.place.hours.isEmpty) return false;

    for (int dayOffset = -1; dayOffset <= 1; dayOffset++) {
      final baseDate = DateTime(
        visitStart.year,
        visitStart.month,
        visitStart.day,
      ).add(Duration(days: dayOffset));
      
      final dayOfWeek = baseDate.weekday - 1; // 0=Mon, ..., 6=Sun
      final dayHours = widget.place.hours.where((h) => h.dayOfWeek == dayOfWeek);
      
      for (final hours in dayHours) {
        final startTime = DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day,
          hours.openTime.hour,
          hours.openTime.minute,
        );
        var endTime = DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day,
          hours.closeTime.hour,
          hours.closeTime.minute,
        );
        if (endTime.isBefore(startTime)) {
          endTime = endTime.add(const Duration(days: 1));
        }

        if ((visitStart.isAfter(startTime) || visitStart.isAtSameMomentAs(startTime)) &&
            (visitEnd.isBefore(endTime) || visitEnd.isAtSameMomentAs(endTime))) {
          return true;
        }
      }
    }
    return false;
  }

  Widget _buildEventTile(
    DateTime date,
    List<CalendarEventData<dynamic>> events,
    Rect boundary,
    DateTime startDuration,
    DateTime endDuration,
  ) {
    if (events.isEmpty) return const SizedBox.shrink();
    final event = events[0];
    final isPlannedVisit = event.title == 'Planned Visit';

    return GestureDetector(
      onTapUp: (details) {
        if (!isPlannedVisit && _savedPlace?.averageVisitLength != null) {
          final tappedMinutes = details.localPosition.dy.toInt();
          final tappedTime = event.startTime!.add(Duration(minutes: tappedMinutes));
          final visitEnd = tappedTime.add(Duration(minutes: _savedPlace!.averageVisitLength!));
          
          if (_isOpenDuring(tappedTime, visitEnd)) {
            setState(() => _plannedVisitTime = tappedTime);
          } else {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Planned visit must be entirely within open business hours'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      },
      onVerticalDragStart: (_) => _dragAccumulator = 0.0,
      onVerticalDragUpdate: isPlannedVisit ? (details) {
        if (_savedPlace?.averageVisitLength != null) {
          _dragAccumulator += details.delta.dy;
          if (_dragAccumulator.abs() >= 1.0) {
            final minutesDelta = _dragAccumulator.toInt();
            _dragAccumulator -= minutesDelta;
            
            setState(() {
              final proposedTime = _plannedVisitTime!.add(Duration(minutes: minutesDelta));
              final visitEnd = proposedTime.add(Duration(minutes: _savedPlace!.averageVisitLength!));
              if (_isOpenDuring(proposedTime, visitEnd)) {
                _plannedVisitTime = proposedTime;
              }
            });
          }
        }
      } : null,
      child: Container(
        decoration: BoxDecoration(
          color: event.color,
          borderRadius: BorderRadius.circular(4),
          boxShadow: isPlannedVisit
              ? [const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]
              : null,
          border: isPlannedVisit
              ? Border.all(color: Colors.white, width: 1.5)
              : null,
        ),
        padding: const EdgeInsets.all(4),
        child: Text(
          event.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  EventController<Object?> _buildEventController() {
    final controller = EventController<Object?>();
    final now = DateTime.now();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    // Generate events for 4 weeks in the past and 12 weeks in the future
    for (int weekOffset = -4; weekOffset <= 12; weekOffset++) {
      final weekStart = startOfWeek.add(Duration(days: weekOffset * 7));
      
      for (final hours in widget.place.hours) {
        final baseDate = weekStart.add(Duration(days: hours.dayOfWeek));
        final startTime = DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day,
          hours.openTime.hour,
          hours.openTime.minute,
        );

        var endTime = DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day,
          hours.closeTime.hour,
          hours.closeTime.minute,
        );

        if (endTime.isBefore(startTime)) {
          endTime = endTime.add(const Duration(days: 1));
        }

        controller.add(
          CalendarEventData(
            title: 'Open',
            date: baseDate,
            startTime: startTime,
            endTime: endTime,
            color: Colors.green.withValues(alpha: 0.7),
          ),
        );
      }
    }

    if (_plannedVisitTime != null && _savedPlace?.averageVisitLength != null) {
      controller.add(
        CalendarEventData(
          title: 'Planned Visit',
          date: DateTime(_plannedVisitTime!.year, _plannedVisitTime!.month, _plannedVisitTime!.day),
          startTime: _plannedVisitTime!,
          endTime: _plannedVisitTime!.add(Duration(minutes: _savedPlace!.averageVisitLength!)),
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
        ),
      );
    }

    return controller;
  }

  Widget _buildContactInfoSection() {
    final hasPhone = widget.place.phone != null && widget.place.phone!.isNotEmpty;
    final hasWebsite = widget.place.website != null && widget.place.website!.isNotEmpty;
    final hasCategories = widget.place.categories.isNotEmpty;

    if (!hasPhone && !hasWebsite && !hasCategories) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasCategories) ...[
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: widget.place.categories.map((category) {
                return Chip(
                  label: Text(category, style: const TextStyle(fontSize: 12)),
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            if (hasPhone || hasWebsite) const SizedBox(height: 12),
          ],
          if (hasPhone) ...[
            Row(
              children: [
                Icon(Icons.phone, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.place.phone!,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            if (hasWebsite) const SizedBox(height: 12),
          ],
          if (hasWebsite) ...[
            Row(
              children: [
                Icon(Icons.language, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.place.website!,
                    style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendarOptions() {
    return SegmentedButton<CalendarViewType>(
      segments: const [
        ButtonSegment(
          value: CalendarViewType.singleDay,
          label: Text('1 Day'),
        ),
        ButtonSegment(
          value: CalendarViewType.threeDay,
          label: Text('3 Days'),
        ),
        ButtonSegment(
          value: CalendarViewType.week,
          label: Text('Week'),
        ),
      ],
      selected: <CalendarViewType>{_currentView},
      onSelectionChanged: (Set<CalendarViewType> selection) {
        setState(() {
          _currentView = selection.first;
          _baseDate = DateTime.now();
        });
      },
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildAddressSection() {
    final addressParts = widget.place.address.split(', ');
    final String line1 = addressParts.isNotEmpty ? addressParts[0] : widget.place.address;
    final String line2 = addressParts.length > 1 ? addressParts.skip(1).join(', ') : '';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Address',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  line1,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                ),
                if (line2.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    line2,
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ]
              ],
            ),
          ),
          const SizedBox(width: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 80,
              height: 80,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: widget.place.location,
                  initialZoom: 15.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none, // Static map
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: Theme.of(context).brightness == Brightness.dark
                        ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: widget.place.location,
                        width: 30,
                        height: 30,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAverageVisitLengthPicker() {
    if (_isLoadingSavedPlace || _savedPlace == null) {
      return const SizedBox.shrink();
    }

    final List<int?> durations = [null, 15, 30, 45, 60, 90, 120, 180, 240];
    String formatDuration(int? mins) {
      if (mins == null) return 'None';
      if (mins < 60) return '$mins mins';
      final hrs = mins / 60;
      return '${hrs.toStringAsFixed(hrs.truncateToDouble() == hrs ? 0 : 1)} ${hrs == 1 ? 'hr' : 'hrs'}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.timer, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Average Visit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(
                  'Tap calendar to see if it fits',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          DropdownButton<int?>(
            value: _savedPlace!.averageVisitLength,
            items: durations.map((d) => DropdownMenuItem(value: d, child: Text(formatDuration(d)))).toList(),
            onChanged: (val) async {
              try {
                final apiService = context.read<ApiService>();
                await apiService.updateVisitLength(widget.place.tomtomId, val);
                if (mounted) {
                  setState(() {
                    _savedPlace = SavedPlace(
                      id: _savedPlace!.id,
                      place: _savedPlace!.place,
                      customName: _savedPlace!.customName,
                      icon: _savedPlace!.icon,
                      color: _savedPlace!.color,
                      isPinned: _savedPlace!.isPinned,
                      averageVisitLength: val,
                    );
                    if (val == null) {
                      _plannedVisitTime = null;
                    }
                  });
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to update visit length'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            underline: const SizedBox(),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphicPicker() {
    if (_isLoadingSavedPlace) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_savedPlace == null) {
      return const SizedBox.shrink(); // Not saved -> don't show picker
    }

    final currentColorHex = _selectedColor ?? _savedPlace!.color ?? Colors.blue.value.toRadixString(16);
    final currentColor = Color(int.parse(currentColorHex, radix: 16)).withOpacity(1.0);
    final currentIconName = _selectedIcon ?? _savedPlace!.icon ?? 'star';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: currentColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _availableIcons[currentIconName] ?? Icons.star,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'Profile Graphic',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    if (_savedPlace?.customName != null && _savedPlace!.customName!.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '—  ${_savedPlace!.customName!}',
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(_isEditingGraphic ? Icons.close : Icons.edit, size: 20),
                onPressed: () {
                  setState(() {
                    _isEditingGraphic = !_isEditingGraphic;
                    if (!_isEditingGraphic) {
                      // Reset selections if cancelling
                      _selectedIcon = _savedPlace?.icon;
                      _selectedColor = _savedPlace?.color;
                      _labelController.text = _savedPlace?.customName ?? '';
                    }
                  });
                },
              ),
            ],
          ),
          if (_isEditingGraphic) ...[
            const SizedBox(height: 16),
            const Text('Color', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _availableColors.map((color) {
                  final isSelected = color.value == currentColor.value;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedColor = color.value.toRadixString(16);
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2) : null,
                        boxShadow: isSelected
                            ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Icon', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _availableIcons.entries.map((entry) {
                  final isSelected = entry.key == currentIconName;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIcon = entry.key;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? currentColor.withOpacity(0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected ? Border.all(color: currentColor) : Border.all(color: Colors.transparent),
                      ),
                      child: Icon(
                        entry.value,
                        color: isSelected ? currentColor : Theme.of(context).iconTheme.color,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Label', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _suggestedLabels.map((label) {
                  final isSelected = _labelController.text == label;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _labelController.text = selected ? label : '';
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                hintText: 'Custom label (e.g. My Gym)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) {
                setState(() {}); // refresh chip selection if typed manually
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _updateGraphic(icon: _selectedIcon, color: _selectedColor, customName: _labelController.text),
                icon: const Icon(Icons.save),
                label: const Text('Save Profile'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendar(Color textColor, Color textSmallColor, bool use24HourFormat) {
    List<WeekDays> weekDays = WeekDays.values;
    int daysToAdvance = 7;
    String headerText = "";

    if (_currentView == CalendarViewType.threeDay) {
      daysToAdvance = 3;
      weekDays = [
        WeekDays.values[_baseDate.weekday - 1],
        WeekDays.values[_baseDate.add(const Duration(days: 1)).weekday - 1],
        WeekDays.values[_baseDate.add(const Duration(days: 2)).weekday - 1],
      ];
      final endDate = _baseDate.add(const Duration(days: 2));
      headerText = "${_baseDate.month}/${_baseDate.day} - ${endDate.month}/${endDate.day}";
    } else if (_currentView == CalendarViewType.singleDay) {
      daysToAdvance = 1;
      headerText = "${_baseDate.month}/${_baseDate.day}/${_baseDate.year}";
    } else {
      daysToAdvance = 7;
      final start = _baseDate.subtract(Duration(days: _baseDate.weekday - 1));
      final end = start.add(const Duration(days: 6));
      headerText = "${start.month}/${start.day} - ${end.month}/${end.day}";
    }

    Widget calendarWidget;
    if (_currentView == CalendarViewType.singleDay) {
      calendarWidget = DayView(
        key: ValueKey(_baseDate),
        controller: _buildEventController(),
        initialDay: _baseDate,
        minDay: _baseDate.subtract(const Duration(days: 28)),
        maxDay: _baseDate.add(const Duration(days: 84)),
        heightPerMinute: 1, // Compact view
        scrollPhysics: const ClampingScrollPhysics(),
        pageViewPhysics: const NeverScrollableScrollPhysics(),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        eventTileBuilder: _buildEventTile,
        onDateTap: (date) {
          if (_savedPlace?.averageVisitLength != null) {
            final visitEnd = date.add(Duration(minutes: _savedPlace!.averageVisitLength!));
            if (_isOpenDuring(date, visitEnd)) {
              setState(() => _plannedVisitTime = date);
            } else {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Planned visit must be entirely within open business hours'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        },
        dayTitleBuilder: (date) => const SizedBox.shrink(),
        hourIndicatorSettings: HourIndicatorSettings(
          color: Theme.of(context).dividerColor,
        ),
        liveTimeIndicatorSettings: LiveTimeIndicatorSettings(
          color: Theme.of(context).colorScheme.primary,
        ),
        timeLineBuilder: (date) {
          final timeString = use24HourFormat
              ? "${date.hour.toString().padLeft(2, '0')}:00"
              : DateFormat('h a').format(DateTime(date.year, date.month, date.day, date.hour));
          return Center(
            child: Text(
              timeString,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color ?? textSmallColor,
                fontSize: 12,
              ),
            ),
          );
        },
      );
    } else {
      calendarWidget = WeekView(
        key: ValueKey(_baseDate),
        controller: _buildEventController(),
        minDay: _baseDate.subtract(const Duration(days: 28)),
        maxDay: _baseDate.add(const Duration(days: 84)),
        initialDay: _baseDate,
        startDay: _currentView == CalendarViewType.threeDay
            ? WeekDays.values[_baseDate.weekday - 1]
            : WeekDays.monday,
        weekDays: weekDays,
        heightPerMinute: 1, // Compact view
        scrollPhysics: const ClampingScrollPhysics(),
        pageViewPhysics: const NeverScrollableScrollPhysics(),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        eventTileBuilder: _buildEventTile,
        onDateTap: (date) {
          if (_savedPlace?.averageVisitLength != null) {
            final visitEnd = date.add(Duration(minutes: _savedPlace!.averageVisitLength!));
            if (_isOpenDuring(date, visitEnd)) {
              setState(() => _plannedVisitTime = date);
            } else {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Planned visit must be entirely within open business hours'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        },
        weekPageHeaderBuilder: (start, end) => const SizedBox.shrink(),
        hourIndicatorSettings: HourIndicatorSettings(
          color: Theme.of(context).dividerColor,
        ),
        liveTimeIndicatorSettings: LiveTimeIndicatorSettings(
          color: Theme.of(context).colorScheme.primary,
        ),
        timeLineBuilder: (date) {
          final timeString = use24HourFormat
              ? "${date.hour.toString().padLeft(2, '0')}:00"
              : DateFormat('h a').format(DateTime(date.year, date.month, date.day, date.hour));
          return Center(
            child: Text(
              timeString,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color ?? textSmallColor,
                fontSize: 12,
              ),
            ),
          );
        },
        weekDayBuilder: (date) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _weekDayShortName(date.weekday),
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color ?? textSmallColor,
                  fontSize: 12,
                ),
              ),
              Text(
                date.day.toString(),
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color ?? textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _baseDate = _baseDate.subtract(Duration(days: daysToAdvance));
                  });
                },
              ),
              Expanded(
                child: Text(
                  headerText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _baseDate = _baseDate.add(Duration(days: daysToAdvance));
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: calendarWidget,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final textSmallColor = isDark ? Colors.white70 : Colors.black87;
    final use24HourFormat = context.watch<PreferencesCubit>().state.use24HourFormat;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.place.name),
        actions: [
          if (_isLoadingSavedPlace)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_savedPlace == null)
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined),
              tooltip: 'Save Place',
              onPressed: () async {
                setState(() => _isLoadingSavedPlace = true);
                try {
                  final apiService = context.read<ApiService>();
                  await apiService.savePlace(widget.place);
                  await apiService.bookmarkPlace(widget.place.tomtomId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Saved to My Places'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _checkSavedStatus();
                  }
                } catch (e) {
                  if (context.mounted) {
                    setState(() => _isLoadingSavedPlace = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Error saving place'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Remove from Saved Places',
              onPressed: () async {
                setState(() => _isLoadingSavedPlace = true);
                try {
                  final apiService = context.read<ApiService>();
                  await apiService.deleteBookmark(widget.place.tomtomId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Removed from My Places'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (context.mounted) {
                    setState(() => _isLoadingSavedPlace = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Error deleting place'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGraphicPicker(),
                  _buildAverageVisitLengthPicker(),
                  _buildAddressSection(),
                  const SizedBox(height: 16),
                  _buildContactInfoSection(),
                  // More details will be added here later
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                  child: _buildCalendarOptions(),
                ),
                Expanded(
                  child: _buildCalendar(textColor, textSmallColor, use24HourFormat),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
