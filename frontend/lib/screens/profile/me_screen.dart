import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../models/user.dart';
import '../../components/shared/address_input_accordion.dart';
import '../../components/shared/glass_card.dart';
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

  String _getInitials(User user) {
    if (user.firstName != null &&
        user.lastName != null &&
        user.firstName!.isNotEmpty &&
        user.lastName!.isNotEmpty) {
      return '${user.firstName![0]}${user.lastName![0]}'.toUpperCase();
    }
    return user.username.substring(0, 1).toUpperCase();
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
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Profile Header Card
                              GlassCard(
                                padding: const EdgeInsets.all(24),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 40,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.2),
                                      child: Text(
                                        _getInitials(user),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user.username,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          if (user.email != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              user.email!,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    color: Colors.grey[600],
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Account Information Section
                              GlassCard(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Account Information',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _firstNameController,
                                            decoration: const InputDecoration(
                                              labelText: 'First Name',
                                              prefixIcon: Icon(
                                                Icons.person_outline,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: TextFormField(
                                            controller: _lastNameController,
                                            decoration: const InputDecoration(
                                              labelText: 'Last Name',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Location Preferences Section
                              GlassCard(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Location Preferences',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 12),
                                    AddressInputAccordion(
                                      title: 'Home Address',
                                      icon: Icons.home_outlined,
                                      streetController: _homeStreetController,
                                      cityController: _homeCityController,
                                      stateController: _homeStateController,
                                      zipController: _homeZipController,
                                      initiallyExpanded:
                                          _homeStreetController
                                              .text
                                              .isNotEmpty ||
                                          _homeCityController.text.isNotEmpty ||
                                          _homeStateController
                                              .text
                                              .isNotEmpty ||
                                          _homeZipController.text.isNotEmpty,
                                    ),
                                    const Divider(height: 32),
                                    AddressInputAccordion(
                                      title: 'Work Address',
                                      icon: Icons.work_outline,
                                      streetController: _workStreetController,
                                      cityController: _workCityController,
                                      stateController: _workStateController,
                                      zipController: _workZipController,
                                      initiallyExpanded:
                                          _workStreetController
                                              .text
                                              .isNotEmpty ||
                                          _workCityController.text.isNotEmpty ||
                                          _workStateController
                                              .text
                                              .isNotEmpty ||
                                          _workZipController.text.isNotEmpty,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),

                              // Action Buttons
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  onPressed:
                                      state is AuthLoading
                                          ? null
                                          : () => _saveProfile(user),
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 2,
                                  ),
                                  child:
                                      state is AuthLoading
                                          ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                          : const Text(
                                            'Save Profile',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: OutlinedButton(
                                  onPressed: () {
                                    context.read<AuthBloc>().add(
                                      LogoutRequested(),
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(
                                      color: Colors.red,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text(
                                    'Logout',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
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
