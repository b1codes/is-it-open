import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../models/user.dart';
import '../../components/shared/address_input_accordion.dart';
import '../../screens/profile/settings_screen.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isInitialized = false;

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _homeAddressController;
  late TextEditingController _homeStreetController;
  late TextEditingController _homeCityController;
  late TextEditingController _homeStateController;
  late TextEditingController _homeZipController;
  late TextEditingController _workAddressController;
  late TextEditingController _workStreetController;
  late TextEditingController _workCityController;
  late TextEditingController _workStateController;
  late TextEditingController _workZipController;

  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _homeAddressController = TextEditingController();
    _homeStreetController = TextEditingController();
    _homeCityController = TextEditingController();
    _homeStateController = TextEditingController();
    _homeZipController = TextEditingController();
    _workAddressController = TextEditingController();
    _workStreetController = TextEditingController();
    _workCityController = TextEditingController();
    _workStateController = TextEditingController();
    _workZipController = TextEditingController();

    // Initialize controllers with current user data if available
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _currentUser = authState.user;
      _populateFields(authState.user);
    }
  }

  void _populateFields(User user) {
    _firstNameController.text = user.firstName ?? '';
    _lastNameController.text = user.lastName ?? '';
    _homeAddressController.text = user.homeAddress ?? '';
    _homeStreetController.text = user.homeStreet ?? '';
    _homeCityController.text = user.homeCity ?? '';
    _homeStateController.text = user.homeState ?? '';
    _homeZipController.text = user.homeZip ?? '';
    _workAddressController.text = user.workAddress ?? '';
    _workStreetController.text = user.workStreet ?? '';
    _workCityController.text = user.workCity ?? '';
    _workStateController.text = user.workState ?? '';
    _workZipController.text = user.workZip ?? '';
    _isInitialized = true;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _homeAddressController.dispose();
    _homeStreetController.dispose();
    _homeCityController.dispose();
    _homeStateController.dispose();
    _homeZipController.dispose();
    _workAddressController.dispose();
    _workStreetController.dispose();
    _workCityController.dispose();
    _workStateController.dispose();
    _workZipController.dispose();
    super.dispose();
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
        homeStreet: _homeStreetController.text.trim(),
        homeCity: _homeCityController.text.trim(),
        homeState: _homeStateController.text.trim(),
        homeZip: _homeZipController.text.trim(),
        homeLat: currentUser.homeLat,
        homeLng: currentUser.homeLng,
        workAddress: _workAddressController.text.trim(),
        workStreet: _workStreetController.text.trim(),
        workCity: _workCityController.text.trim(),
        workState: _workStateController.text.trim(),
        workZip: _workZipController.text.trim(),
        workLat: currentUser.workLat,
        workLng: currentUser.workLng,
        useCurrentLocation: currentUser.useCurrentLocation,
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
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          _currentUser = state.user;
          if (!_isInitialized) {
            _populateFields(state.user);
          }
        }
        if (state is ProfileUpdateSuccess) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is ProfileUpdateFailure) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error), backgroundColor: Colors.red),
          );
        } else if (state is AuthFailure) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error), backgroundColor: Colors.red),
          );
        }
      },
      builder: (context, state) {
        if (_currentUser != null) {
          final user = _currentUser!;
          return Scaffold(
            appBar: AppBar(
              title: const Text('My Profile'),
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ],
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
                          AddressInputAccordion(
                            title: 'Home Address',
                            icon: Icons.home,
                            streetController: _homeStreetController,
                            cityController: _homeCityController,
                            stateController: _homeStateController,
                            zipController: _homeZipController,
                            initiallyExpanded:
                                _homeStreetController.text.isNotEmpty ||
                                _homeCityController.text.isNotEmpty ||
                                _homeStateController.text.isNotEmpty ||
                                _homeZipController.text.isNotEmpty,
                          ),
                          const SizedBox(height: 16),
                          AddressInputAccordion(
                            title: 'Work Address',
                            icon: Icons.work,
                            streetController: _workStreetController,
                            cityController: _workCityController,
                            stateController: _workStateController,
                            zipController: _workZipController,
                            initiallyExpanded:
                                _workStreetController.text.isNotEmpty ||
                                _workCityController.text.isNotEmpty ||
                                _workStateController.text.isNotEmpty ||
                                _workZipController.text.isNotEmpty,
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: state is AuthLoading
                                  ? null
                                  : () => _saveProfile(user),
                              child: state is AuthLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Save Profile'),
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
