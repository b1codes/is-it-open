import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import '../bloc/auth/auth_bloc.dart';
import '../models/user.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _homeAddressController;
  late TextEditingController _workAddressController;

  bool _useCurrentLocation = false;
  double? _currentLat;
  double? _currentLng;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _homeAddressController = TextEditingController();
    _workAddressController = TextEditingController();

    // Initialize controllers with current user data if available
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final user = authState.user;
      _firstNameController.text = user.firstName ?? '';
      _lastNameController.text = user.lastName ?? '';
      _homeAddressController.text = user.homeAddress ?? '';
      _workAddressController.text = user.workAddress ?? '';
      _useCurrentLocation = user.useCurrentLocation;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _homeAddressController.dispose();
    _workAddressController.dispose();
    super.dispose();
  }

  Future<void> _handleCurrentLocationToggle(bool value) async {
    if (value) {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled.')),
          );
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
        }
        return;
      }

      try {
        Position position = await Geolocator.getCurrentPosition();
        setState(() {
          _useCurrentLocation = true;
          _currentLat = position.latitude;
          _currentLng = position.longitude;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
        }
      }
    } else {
      setState(() {
        _useCurrentLocation = false;
        _currentLat = null;
        _currentLng = null;
      });
    }
  }

  void _saveProfile(User currentUser) {
    if (_formKey.currentState!.validate()) {
      final updatedUser = User(
        id: currentUser.id,
        username: currentUser.username,
        email: currentUser.email,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        homeAddress: _homeAddressController.text.trim(),
        homeLat: _useCurrentLocation ? _currentLat : currentUser.homeLat,
        homeLng: _useCurrentLocation ? _currentLng : currentUser.homeLng,
        workAddress: _workAddressController.text.trim(),
        workLat: currentUser.workLat,
        workLng: currentUser.workLng,
        useCurrentLocation: _useCurrentLocation,
        // We might want to save current lat/lng to something specific if logic dictates,
        // but for now, rely on `useCurrentLocation` boolean for the backend flag.
      );

      context.read<AuthBloc>().add(
        ProfileUpdateRequested(updatedUser: updatedUser),
      );

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saving profile...')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthAuthenticated) {
          final user = state.user;
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text('My Profile'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account Information',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: TextEditingController(text: user.username),
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(),
                        ),
                        enabled: false,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: TextEditingController(
                          text: user.email ?? '',
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        enabled: false,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _firstNameController,
                              decoration: const InputDecoration(
                                labelText: 'First Name',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _lastNameController,
                              decoration: const InputDecoration(
                                labelText: 'Last Name',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Location Preferences',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _homeAddressController,
                        decoration: const InputDecoration(
                          labelText: 'Home Address',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.home),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _workAddressController,
                        decoration: const InputDecoration(
                          labelText: 'Work Address',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.work),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Use Current Location'),
                        subtitle: const Text(
                          'Allow the app to access your device location',
                        ),
                        value: _useCurrentLocation,
                        onChanged: _handleCurrentLocationToggle,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () => _saveProfile(user),
                          child: const Text('Save Profile'),
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () {
                            context.read<AuthBloc>().add(LogoutRequested());
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          child: const Text('Logout'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
