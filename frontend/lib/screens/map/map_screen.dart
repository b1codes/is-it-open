import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../models/user.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _currentLocation;
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Default to NYC if we can't get location
    void useDefaultLocation() {
      if (mounted) {
        setState(() {
          _currentLocation = const LatLng(40.7128, -74.0060);
          _isLoadingLocation = false;
        });
      }
    }

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return useDefaultLocation();
      }

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
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      useDefaultLocation();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingLocation) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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

    return Scaffold(
      body: FlutterMap(
        options: MapOptions(
          initialCenter: _currentLocation!,
          initialZoom: 13.0,
        ),
        children: [
          TileLayer(
            urlTemplate: Theme.of(context).brightness == Brightness.dark
                ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.app',
          ),
          if (markers.isNotEmpty) MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}
