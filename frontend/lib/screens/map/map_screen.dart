import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/map/map_ui_cubit.dart';
import '../../bloc/map/map_ui_state.dart';
import '../../models/user.dart';
import '../../models/saved_place.dart';
import '../../services/api_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _currentLocation = const LatLng(40.7128, -74.0060); // Default to NYC
  LatLng? _userPosition; // Stores the actual GPS location

  // Saved places state
  List<SavedPlace> _savedPlaces = [];
  bool _isLoadingPlaces = true;
  final Set<String> _checkedPlaceIds = {};

  // Toggles
  bool _showPinnedLocations = true;

  // Map Controller for dynamic panning
  final MapController _mapController = MapController();

  static const List<Color> _defaultPalette = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.brown,
    Colors.indigo,
    Colors.cyan,
  ];

  static const Map<String, IconData> _availableIcons = {
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

  @override
  void initState() {
    super.initState();

    // Initialize map center with home address if available
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final user = authState.user;
      if (user.homeLat != null && user.homeLng != null) {
        _currentLocation = LatLng(user.homeLat!, user.homeLng!);
      }
    }

    _determinePosition();
    _loadSavedPlaces();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    void useDefaultLocation() {
      if (mounted) {
        setState(() {
          final authState = context.read<AuthBloc>().state;
          if (authState is AuthAuthenticated &&
              authState.user.homeLat != null &&
              authState.user.homeLng != null) {
            _currentLocation = LatLng(
              authState.user.homeLat!,
              authState.user.homeLng!,
            );
          } else {
            _currentLocation = const LatLng(40.7128, -74.0060); // NYC
          }
          _userPosition = null;
        });
      }
    }

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return useDefaultLocation();

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return useDefaultLocation();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return useDefaultLocation();
      }

      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        final newLocation = LatLng(position.latitude, position.longitude);
        setState(() {
          _userPosition = newLocation;
        });

        // Refined panning rule:
        // Only pan if Home is missing OR user prefers current location centering
        final authState = context.read<AuthBloc>().state;
        bool shouldPan = true;

        if (authState is AuthAuthenticated) {
          final user = authState.user;
          final hasHome = user.homeLat != null && user.homeLng != null;
          if (hasHome && !user.useCurrentLocation) {
            shouldPan = false;
          }
        }

        if (shouldPan) {
          setState(() {
            _currentLocation = newLocation;
          });
          _mapController.move(newLocation, 13.0);
        }
      }
    } catch (e) {
      useDefaultLocation();
    }
  }

  Future<void> _loadSavedPlaces() async {
    try {
      final apiService = context.read<ApiService>();
      final bookmarks = await apiService.getBookmarks();
      if (mounted) {
        setState(() {
          _savedPlaces = bookmarks;
          if (_showPinnedLocations) {
            for (final sp in _savedPlaces) {
              if (sp.isPinned) _checkedPlaceIds.add(sp.place.tomtomId);
            }
          }
          _isLoadingPlaces = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPlaces = false);
      }
    }
  }

  Color _colorForPlace(SavedPlace sp, int index) {
    if (sp.color != null && sp.color!.isNotEmpty) {
      try {
        return Color(int.parse(sp.color!, radix: 16));
      } catch (_) {}
    }
    return _defaultPalette[index % _defaultPalette.length];
  }

  String _displayName(SavedPlace sp) {
    if (sp.customName != null && sp.customName!.isNotEmpty) {
      return sp.customName!;
    }
    return sp.place.name;
  }

  Widget _buildPlacesSidebar() {
    if (_isLoadingPlaces) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_savedPlaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bookmark_border,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'No saved places yet',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _savedPlaces.length,
      itemBuilder: (context, index) {
        final sp = _savedPlaces[index];
        final isChecked = _checkedPlaceIds.contains(sp.place.tomtomId);
        final color = _colorForPlace(sp, index);
        final iconName = sp.icon ?? 'star';
        final iconData = _availableIcons[iconName] ?? Icons.star;

        return CheckboxListTile(
          value: isChecked,
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _checkedPlaceIds.add(sp.place.tomtomId);
                final allPinnedChecked = _savedPlaces
                    .where((p) => p.isPinned)
                    .every((p) => _checkedPlaceIds.contains(p.place.tomtomId));
                if (allPinnedChecked) {
                  _showPinnedLocations = true;
                }
              } else {
                _checkedPlaceIds.remove(sp.place.tomtomId);
                if (sp.isPinned) {
                  _showPinnedLocations = false;
                }
              }
            });
          },
          secondary: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(iconData, color: Colors.white, size: 20),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  _displayName(sp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              if (sp.isPinned)
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Icon(
                    Icons.push_pin,
                    size: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: color,
        );
      },
    );
  }

  Widget _buildCollapsedSidebar() {
    return Column(
      children: [
        const SizedBox(height: 16),
        // Toggle Pinned
        Tooltip(
          message: _showPinnedLocations ? 'Hide Pinned' : 'Show Pinned',
          child: IconButton(
            icon: Icon(
              _showPinnedLocations ? Icons.push_pin : Icons.push_pin_outlined,
              color: _showPinnedLocations
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () {
              setState(() {
                _showPinnedLocations = !_showPinnedLocations;
                if (_showPinnedLocations) {
                  for (final sp in _savedPlaces) {
                    if (sp.isPinned) _checkedPlaceIds.add(sp.place.tomtomId);
                  }
                } else {
                  for (final sp in _savedPlaces) {
                    if (sp.isPinned) _checkedPlaceIds.remove(sp.place.tomtomId);
                  }
                }
              });
            },
          ),
        ),
        const Divider(),
        // Refresh
        Tooltip(
          message: 'Refresh Places',
          child: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoadingPlaces = true);
              _loadSavedPlaces();
            },
          ),
        ),
        if (_checkedPlaceIds.isNotEmpty)
          Tooltip(
            message: 'Hide All Markers',
            child: IconButton(
              icon: const Icon(Icons.layers_clear),
              onPressed: () {
                setState(() {
                  _checkedPlaceIds.clear();
                  _showPinnedLocations = false;
                });
              },
            ),
          ),
        const Divider(),
        // Places
        Expanded(
          child: ListView.builder(
            itemCount: _savedPlaces.length,
            itemBuilder: (context, index) {
              final sp = _savedPlaces[index];
              final isChecked = _checkedPlaceIds.contains(sp.place.tomtomId);
              final color = _colorForPlace(sp, index);
              final iconName = sp.icon ?? 'star';
              final iconData = _availableIcons[iconName] ?? Icons.star;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Tooltip(
                  message: _displayName(sp),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (isChecked) {
                          _checkedPlaceIds.remove(sp.place.tomtomId);
                          if (sp.isPinned) _showPinnedLocations = false;
                        } else {
                          _checkedPlaceIds.add(sp.place.tomtomId);
                          final allPinnedChecked = _savedPlaces
                              .where((p) => p.isPinned)
                              .every(
                                (p) =>
                                    _checkedPlaceIds.contains(p.place.tomtomId),
                              );
                          if (allPinnedChecked) _showPinnedLocations = true;
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isChecked ? 0.6 : 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(iconData, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    final authState = context.watch<AuthBloc>().state;
    User? user;
    if (authState is AuthAuthenticated) {
      user = authState.user;
    }

    final markers = <Marker>[];
    if (user != null) {
      if (user.homeLat != null && user.homeLng != null) {
        markers.add(
          Marker(
            point: LatLng(user.homeLat!, user.homeLng!),
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 6,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const Icon(Icons.location_on, color: Colors.blue, size: 40),
                Positioned(
                  top: 8,
                  child: const Icon(Icons.home, color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
        );
      }
      if (user.workLat != null && user.workLng != null) {
        markers.add(
          Marker(
            point: LatLng(user.workLat!, user.workLng!),
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 6,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const Icon(Icons.location_on, color: Colors.orange, size: 40),
                Positioned(
                  top: 8,
                  child: const Icon(Icons.work, color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
        );
      }
    }

    int colorIndex = 0;
    for (final sp in _savedPlaces) {
      if (_checkedPlaceIds.contains(sp.place.tomtomId)) {
        final color = _colorForPlace(sp, colorIndex);
        final iconName = sp.icon ?? 'star';
        final iconData = _availableIcons[iconName] ?? Icons.star;
        final lat = sp.place.location.latitude;
        final lon = sp.place.location.longitude;

        markers.add(
          Marker(
            point: LatLng(lat, lon),
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 6,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Icon(Icons.location_on, color: color, size: 40),
                Positioned(
                  top: 8,
                  child: Icon(iconData, color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
        );
      }
      colorIndex++;
    }

    if (_userPosition != null) {
      markers.add(
        Marker(
          point: _userPosition!,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.4),
                  spreadRadius: 4,
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: _currentLocation!, initialZoom: 13.0),
      children: [
        TileLayer(
          urlTemplate: Theme.of(context).brightness == Brightness.dark
              ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.brandonlc.isitopen',
        ),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MapUiCubit>(
      create: (context) => MapUiCubit(),
      child: BlocBuilder<MapUiCubit, MapUiState>(
        builder: (context, uiState) {
          final isMobile = MediaQuery.of(context).size.width < 800;

          Widget sidebarContent = SafeArea(
            child: uiState.isSidebarCollapsed
                ? _buildCollapsedSidebar()
                : ListView(
                    children: [
                      SwitchListTile(
                        title: const Text('Show Pinned Locations'),
                        subtitle: const Text(
                          'Automatically show markers for all pinned places',
                        ),
                        value: _showPinnedLocations,
                        onChanged: (val) {
                          setState(() {
                            _showPinnedLocations = val;
                            if (val) {
                              for (final sp in _savedPlaces) {
                                if (sp.isPinned) {
                                  _checkedPlaceIds.add(sp.place.tomtomId);
                                }
                              }
                            } else {
                              for (final sp in _savedPlaces) {
                                if (sp.isPinned) {
                                  _checkedPlaceIds.remove(sp.place.tomtomId);
                                }
                              }
                            }
                          });
                        },
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(
                          children: [
                            Text(
                              'My Places',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            if (_checkedPlaceIds.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.layers_clear, size: 18),
                                tooltip: 'Hide All',
                                onPressed: () {
                                  setState(() {
                                    _checkedPlaceIds.clear();
                                    _showPinnedLocations = false;
                                  });
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 18),
                              onPressed: () {
                                setState(() => _isLoadingPlaces = true);
                                _loadSavedPlaces();
                              },
                            ),
                          ],
                        ),
                      ),
                      _buildPlacesSidebar(),
                    ],
                  ),
          );

          return Scaffold(
            appBar: AppBar(
              title: const Text('Map'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                if (!isMobile)
                  IconButton(
                    icon: Icon(
                      uiState.isSidebarCollapsed
                          ? Icons.chevron_left
                          : Icons.chevron_right,
                    ),
                    tooltip: uiState.isSidebarCollapsed
                        ? 'Expand Sidebar'
                        : 'Collapse Sidebar',
                    onPressed: () {
                      context.read<MapUiCubit>().toggleSidebar();
                    },
                  ),
                if (isMobile)
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.filter_list),
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                    ),
                  ),
              ],
            ),
            endDrawer: isMobile ? Drawer(child: sidebarContent) : null,
            body: isMobile
                ? _buildMap()
                : Row(
                    children: [
                      Expanded(child: _buildMap()),
                      const VerticalDivider(width: 1),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        width: uiState.isSidebarCollapsed ? 64 : 300,
                        child: sidebarContent,
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
