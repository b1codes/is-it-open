import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:frontend/screens/search/search_screen.dart';
import 'package:frontend/screens/map/map_screen.dart';
import 'package:frontend/screens/places/my_places_screen.dart';
import 'package:frontend/screens/calendar/calendar_screen.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import '../../components/shared/side_menu.dart';
import '../../components/core/refractive_glass.dart';
import '../../models/saved_place.dart';
import '../../utils/places_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

const _minSheetContentHeight = 240.0;

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 2; // Default to Map
  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _sheetAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_applySheetAnimation);
    _sheetController.addListener(() {
      final currentSize = _sheetController.size;
      // If user drags sheet down, sync index to Map
      if (_sheetTouched && currentSize <= 0.12 && _selectedIndex != 2) {
        setState(() {
          _selectedIndex = 2;
        });
      }
    });
  }

  @override
  void dispose() {
    _sheetAnimation.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _animateSheet(index == 2 ? 0.08 : 0.5);
  }

  // Moves the phone sheet by setting its size every frame. The sheet
  // controller's own animateTo is tied to the content's scroll position, so
  // swapping that content (a tab change, a list finishing loading) cancelled
  // it part-way and left the sheet collapsed.
  late final AnimationController _sheetAnimation;
  double _sheetFrom = 0.08;
  double _sheetTo = 0.08;

  void _applySheetAnimation() {
    if (!_sheetController.isAttached) return;
    final t = Curves.easeOutQuart.transform(_sheetAnimation.value);
    _sheetController.jumpTo(_sheetFrom + (_sheetTo - _sheetFrom) * t);
  }

  // Only the phone layout has a sheet; on desktop there is nothing to move.
  void _animateSheet(double size) {
    _sheetTouched = false;
    if (!_sheetController.isAttached) return;
    _sheetFrom = _sheetController.size;
    _sheetTo = size;
    _sheetAnimation.forward(from: 0);
  }

  // Whether the user has touched the sheet since the last tab change. Only a
  // user drag down to the peek height means "back to the map"; the sheet
  // also passes through that height when a tab opens it.
  bool _sheetTouched = false;

  void _handlePlaceTapped(SavedPlace sp) {
    final lat = sp.place.location.latitude;
    final lng = sp.place.location.longitude;
    // Offset the latitude slightly so the marker sits in the upper viewport above the bottom sheet
    final offsetLat = lat - 0.004;
    _mapController.move(LatLng(offsetLat, lng), 14.5);

    // Expand sheet to show details (if places list or search active)
    if (_selectedIndex == 2) {
      _onItemTapped(0); // Switch to My Places list
    } else {
      _animateSheet(0.4);
    }
  }

  Widget _buildSheetContent(int index, ScrollController scrollController) {
    switch (index) {
      case 0:
        return MyPlacesScreen(
          embedded: true,
          scrollController: scrollController,
        );
      case 1:
        return CalendarScreen(
          embedded: true,
          scrollController: scrollController,
        );
      case 2:
        final theme = context.places;
        // The sheet's controller only attaches once its scroll controller
        // drives a scrollable, so the peek bar sits in a ListView too.
        // Without it, dragging the sheet did nothing and tapping a tab threw.
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.zero,
          children: [
            GestureDetector(
              onTap: () => _onItemTapped(3), // Tap to open search
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: theme.inkMuted),
                    const SizedBox(width: 12),
                    Text(
                      'Search or plan route...',
                      style: PlacesType.bodySmall(theme.inkMuted),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.anchor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(PlacesRadius.sm),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.route_rounded,
                            color: theme.anchor,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Route',
                            style: PlacesType.label(
                              theme.anchor,
                            ).copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      case 3:
        return SearchScreen(embedded: true, scrollController: scrollController);
      case 4:
        return MeScreen(embedded: true, scrollController: scrollController);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        // Persistent background map
        final mapBackground = MapScreen(
          embedded: true,
          mapController: _mapController,
          onPlaceTapped: _handlePlaceTapped,
        );

        return Scaffold(
          body: Stack(
            children: [
              // 1. Persistent background map
              mapBackground,

              // 2. Floating overlays based on platform class
              if (isMobile)
                // Mobile layout: Draggable bottom panel
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: DraggableScrollableSheet(
                    controller: _sheetController,
                    initialChildSize: 0.08,
                    minChildSize: 0.08,
                    maxChildSize: 0.9,
                    snap: true,
                    snapSizes: const [0.08, 0.4, 0.9],
                    builder: (context, scrollController) {
                      return Listener(
                        onPointerDown: (_) {
                          _sheetTouched = true;
                          _sheetAnimation.stop(); // the user takes over
                        },
                        child: RefractiveGlass(
                          borderRadius: 16,
                          opacity: isDark ? 0.08 : 0.65,
                          child: Column(
                            children: [
                              _SheetHandle(
                                // The calendar scrolls its own views, so the
                                // handle carries the sheet's controller there.
                                scrollController: _selectedIndex == 1
                                    ? scrollController
                                    : null,
                              ),
                              Expanded(
                                // While the sheet opens from its peek
                                // height, lay content out at a usable
                                // height and clip it rather than letting
                                // every tab overflow mid-animation.
                                child: LayoutBuilder(
                                  builder: (context, constraints) => ClipRect(
                                    child: OverflowBox(
                                      alignment: Alignment.topCenter,
                                      minHeight: 0,
                                      maxHeight: math.max(
                                        constraints.maxHeight,
                                        _minSheetContentHeight,
                                      ),
                                      child: _buildSheetContent(
                                        _selectedIndex,
                                        scrollController,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              else
                // Desktop/Tablet layout: Left side menu + left floating glass panel
                Row(
                  children: [
                    SideMenu(
                      selectedIndex: _selectedIndex,
                      onIndexChanged: _onItemTapped,
                    ),
                    if (_selectedIndex != 2)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SizedBox(
                          width: 360,
                          child: RefractiveGlass(
                            borderRadius: 16,
                            opacity: isDark ? 0.08 : 0.65,
                            child: Column(
                              children: [
                                const SizedBox(height: 16),
                                Expanded(
                                  child: _buildSheetContent(
                                    _selectedIndex,
                                    ScrollController(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          bottomNavigationBar: isMobile
              ? Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: theme.ashSoft, width: 1),
                    ),
                  ),
                  child: BottomNavigationBar(
                    currentIndex: _selectedIndex > 4 ? 4 : _selectedIndex,
                    onTap: _onItemTapped,
                    type: BottomNavigationBarType.fixed,
                    selectedItemColor: theme.anchor,
                    unselectedItemColor: theme.inkMuted,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    elevation: 0,
                    selectedLabelStyle: PlacesType.label(
                      theme.anchor,
                    ).copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                    unselectedLabelStyle: PlacesType.label(
                      theme.inkMuted,
                    ).copyWith(fontWeight: FontWeight.w500, fontSize: 11),
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.star_rounded),
                        label: 'My Places',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.calendar_month_rounded),
                        label: 'Calendar',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.map_rounded),
                        label: 'Map',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.search_rounded),
                        label: 'Search',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.person_rounded),
                        label: 'Me',
                      ),
                    ],
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle({this.scrollController});

  /// When set, the handle is a scrollable on the sheet's controller, so the
  /// sheet attaches and can be dragged by it even if the content below
  /// doesn't scroll with the sheet.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final handle = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 5,
          decoration: BoxDecoration(
            color: context.places.ashSoft,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
    final controller = scrollController;
    if (controller == null) return handle;
    return SizedBox(
      height: 24,
      child: ListView(
        controller: controller,
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [handle],
      ),
    );
  }
}
