import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/preferences/preferences_cubit.dart';
import '../../models/user.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isUpdating = false;

  Future<void> _handleCurrentLocationToggle(
    bool value,
    User currentUser,
  ) async {
    setState(() {
      _isUpdating = true;
    });

    double? currentLat = currentUser.homeLat;
    double? currentLng = currentUser.homeLng;

    if (value) {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled.')),
          );
          setState(() {
            _isUpdating = false;
          });
        }
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions are denied')),
            );
            setState(() {
              _isUpdating = false;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied.'),
            ),
          );
          setState(() {
            _isUpdating = false;
          });
        }
        return;
      }

      try {
        Position position = await Geolocator.getCurrentPosition();
        currentLat = position.latitude;
        currentLng = position.longitude;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
          setState(() {
            _isUpdating = false;
          });
        }
        return;
      }
    }

    final updatedUser = User(
      id: currentUser.id,
      username: currentUser.username,
      email: currentUser.email,
      firstName: currentUser.firstName,
      lastName: currentUser.lastName,
      homeAddress: currentUser.homeAddress,
      homeStreet: currentUser.homeStreet,
      homeCity: currentUser.homeCity,
      homeState: currentUser.homeState,
      homeZip: currentUser.homeZip,
      homeLat: value ? currentLat : currentUser.homeLat,
      homeLng: value ? currentLng : currentUser.homeLng,
      workAddress: currentUser.workAddress,
      workStreet: currentUser.workStreet,
      workCity: currentUser.workCity,
      workState: currentUser.workState,
      workZip: currentUser.workZip,
      workLat: currentUser.workLat,
      workLng: currentUser.workLng,
      useCurrentLocation: value,
    );

    if (mounted) {
      context.read<AuthBloc>().add(
        ProfileUpdateRequested(updatedUser: updatedUser),
      );
      setState(() {
        _isUpdating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is ProfileUpdateSuccess) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Settings saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is AuthFailure) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error), backgroundColor: Colors.red),
          );
        }
      },
      builder: (context, state) {
        if (state is AuthAuthenticated) {
          final user = state.user;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Settings'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            body: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1A237E).withValues(alpha: 0.1),
                        const Color(0xFF0D47A1).withValues(alpha: 0.1),
                        const Color(0xFF880E4F).withValues(alpha: 0.1),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      Text(
                        'Location Preferences',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Use Current Location'),
                        subtitle: const Text(
                          'Allow the app to access your device location',
                        ),
                        value: user.useCurrentLocation,
                        onChanged: _isUpdating
                            ? null
                            : (value) => _handleCurrentLocationToggle(value, user),
                      ),
                      if (_isUpdating)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'App Preferences',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      BlocBuilder<PreferencesCubit, PreferencesState>(
                        builder: (context, prefsState) {
                          return SwitchListTile(
                            title: const Text('Use 24-Hour Time'),
                            subtitle: const Text(
                              'Display time in 24-hour format (e.g. 13:00)',
                            ),
                            value: prefsState.use24HourFormat,
                            onChanged: (value) {
                              context.read<PreferencesCubit>().toggle24HourFormat(value);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
      },
    );
  }
}
