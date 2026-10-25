import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../models/user.dart';
import '../../components/shared/address_input_accordion.dart';
import '../../components/shared/glass_card.dart';
import '../../screens/profile/settings_screen.dart';
import '../../utils/places_theme.dart';

class MeScreen extends StatefulWidget {
  final bool embedded;
  final ScrollController? scrollController;

  const MeScreen({super.key, this.embedded = false, this.scrollController});

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

  // Whole characters (`characters`), not UTF-16 code units: a name that
  // starts with an emoji would otherwise give half of it, which can't be
  // laid out.
  String _getInitials(User user) {
    String initial(String s) => s.characters.first.toUpperCase();
    if (user.firstName != null &&
        user.lastName != null &&
        user.firstName!.isNotEmpty &&
        user.lastName!.isNotEmpty) {
      return '${initial(user.firstName!)}${initial(user.lastName!)}';
    }
    return initial(user.username);
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
      // Send only the fields edited here: the server keeps every field left
      // out, so a profile cached before another device's edit (say, turning
      // on "Use Current Location") doesn't undo it. Coordinates are never
      // sent: an edited address is geocoded afresh, and an unchanged one
      // keeps the server's.
      final saved = currentUser.toJson();
      final fields = <String, dynamic>{};
      for (final MapEntry(key: name, value: controller) in {
        'first_name': _firstNameController,
        'last_name': _lastNameController,
        'home_address': _homeAddressController,
        'home_street': _homeStreetController,
        'home_city': _homeCityController,
        'home_state': _homeStateController,
        'home_zip': _homeZipController,
        'work_address': _workAddressController,
        'work_street': _workStreetController,
        'work_city': _workCityController,
        'work_state': _workStateController,
        'work_zip': _workZipController,
      }.entries) {
        final text = controller.text.trim();
        // '' and null are the same "not set".
        if (text != ((saved[name] as String?) ?? '').trim()) {
          fields[name] = text;
        }
      }

      context.read<AuthBloc>().add(
        ProfileFieldsUpdateRequested(fields: fields),
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
          final bodyContent = SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  controller: widget.scrollController,
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
                                // Solid: primary initials on a 20% primary
                                // tint over the glass were under 3:1.
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                child: Text(
                                  _getInitials(user),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                              color: context.places.ink,
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
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _firstNameController,
                                      decoration: const InputDecoration(
                                        labelText: 'First Name',
                                        prefixIcon: Icon(Icons.person_outline),
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
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
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
                                    _homeStreetController.text.isNotEmpty ||
                                    _homeCityController.text.isNotEmpty ||
                                    _homeStateController.text.isNotEmpty ||
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
                                    _workStreetController.text.isNotEmpty ||
                                    _workCityController.text.isNotEmpty ||
                                    _workStateController.text.isNotEmpty ||
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
                            onPressed: state is ProfileUpdating
                                ? null
                                : () => _saveProfile(user),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 2,
                            ),
                            child: state is ProfileUpdating
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
                              context.read<AuthBloc>().add(LogoutRequested());
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
          );

          if (widget.embedded) {
            return bodyContent;
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text('My Profile'),
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
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
                        Theme.of(context).scaffoldBackgroundColor,
                        Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.08),
                      ],
                    ),
                  ),
                ),
                bodyContent,
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
