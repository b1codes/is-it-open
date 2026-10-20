import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/theme/theme_cubit.dart';
import '../../screens/profile/settings_screen.dart';
import '../../utils/places_theme.dart';

class SideMenu extends StatelessWidget {
  final Function(int) onIndexChanged;
  final int selectedIndex;

  const SideMenu({
    super.key,
    required this.onIndexChanged,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    // Access the current theme mode to determine switch state
    final themeMode = context.watch<ThemeCubit>().state;
    final isDarkMode =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: theme.paperRaised,
        border: Border(right: BorderSide(color: theme.ashSoft, width: 1)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Text(
                'Is It Open',
                style: PlacesType.display(theme.ink).copyWith(fontSize: 28),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildNavItem(context, 0, 'My Places', Icons.star_rounded),
                  _buildNavItem(
                    context,
                    1,
                    'Calendar',
                    Icons.calendar_month_rounded,
                  ),
                  _buildNavItem(context, 2, 'Map', Icons.map_rounded),
                  _buildNavItem(context, 3, 'Search', Icons.search_rounded),
                  _buildNavItem(context, 4, 'Me', Icons.person_rounded),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Divider(color: theme.ashSoft, height: 1),
            ),
            const SizedBox(height: 12),
            _buildActionItem(
              context,
              'Settings',
              Icons.settings_outlined,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            _buildActionItem(
              context,
              isDarkMode ? 'Dark Mode' : 'Light Mode',
              isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              trailing: Switch(
                value: isDarkMode,
                onChanged: (value) {
                  context.read<ThemeCubit>().setTheme(
                    value ? ThemeMode.dark : ThemeMode.light,
                  );
                },
                activeTrackColor: theme.anchor.withValues(alpha: 0.3),
                activeThumbColor: theme.anchor,
              ),
            ),
            _buildActionItem(
              context,
              'Logout',
              Icons.logout_rounded,
              onTap: () {
                context.read<AuthBloc>().add(LogoutRequested());
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    int index,
    String title,
    IconData icon,
  ) {
    final theme = context.places;
    final isSelected = selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onIndexChanged(index),
          borderRadius: BorderRadius.circular(PlacesRadius.md),
          child: AnimatedContainer(
            duration: PlacesMotion.of(context, PlacesMotion.standard),
            curve: PlacesMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.anchor.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(PlacesRadius.md),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected ? theme.anchor : theme.inkMuted,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style:
                        PlacesType.title(
                          isSelected ? theme.anchor : theme.ink,
                        ).copyWith(
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 15,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionItem(
    BuildContext context,
    String title,
    IconData icon, {
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final theme = context.places;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PlacesRadius.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.inkMuted),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: PlacesType.bodySmall(
                      theme.ink,
                    ).copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
