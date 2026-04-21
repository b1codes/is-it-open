import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'dart:convert' show utf8;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/saved_place.dart';
import '../../models/user.dart';
import '../../bloc/calendar/calendar_data_bloc.dart';
import '../../bloc/calendar/calendar_data_event.dart';
import '../../bloc/calendar/calendar_data_state.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../shared/glass_card.dart';

String displayName(SavedPlace sp) {
  if (sp.customName != null && sp.customName!.isNotEmpty) {
    return sp.customName!;
  }
  return sp.place.name;
}

void _showSubscriptionDialog(BuildContext context, String? currentUrl) {
  final controller = TextEditingController(text: currentUrl ?? '');
  final authBloc = context.read<AuthBloc>();
  final dataBloc = context.read<CalendarDataBloc>();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Calendar Subscription'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter a "Secret iCal URL" (ends in .ics) from iCloud, Outlook, or Proton.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'iCal URL',
              hintText: 'https://example.com/calendar.ics',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final authState = authBloc.state;
            if (authState is AuthAuthenticated) {
              final updatedUser = User(
                id: authState.user.id,
                username: authState.user.username,
                calendarSubscriptionUrl: controller.text,
              );
              authBloc.add(ProfileUpdateRequested(updatedUser: updatedUser));
            }
            Navigator.pop(context);
            Future.delayed(const Duration(seconds: 1), () {
              dataBloc.add(LoadRemoteEvents(controller.text));
            });
          },
          child: const Text('Save & Sync'),
        ),
      ],
    ),
  );
}

class CalendarSidebarWidget extends StatelessWidget {
  final CalendarDataState dataState;
  final Color Function(SavedPlace, int) colorForPlace;
  final Map<String, IconData> availableIcons;

  const CalendarSidebarWidget({
    super.key,
    required this.dataState,
    required this.colorForPlace,
    required this.availableIcons,
  });

  Widget _buildPlacesSidebar(BuildContext context) {
    if (dataState.status == CalendarDataStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (dataState.savedPlaces.isEmpty) {
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(dataState.savedPlaces.length, (index) {
          final sp = dataState.savedPlaces[index];
          final isChecked = dataState.checkedPlaceIds.contains(
            sp.place.tomtomId,
          );
          final color = colorForPlace(sp, index);
          final iconName = sp.icon ?? 'star';
          final iconData = availableIcons[iconName] ?? Icons.star;

          return GestureDetector(
            onTap: () {
              context.read<CalendarDataBloc>().add(
                TogglePlaceFilter(sp.place.tomtomId),
              );
            },
            child: GlassCard(
              color: color,
              opacity: isChecked ? 0.6 : 0.2,
              blur: 15,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              borderRadius: BorderRadius.circular(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconData, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    displayName(sp),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isChecked
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDeviceCalendarsSidebar(BuildContext context) {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(
              Icons.devices_other,
              size: 32,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Device sync is available on Mobile only. For Web/Desktop, consider cloud sync (coming soon).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    if (!dataState.hasCalendarPermission) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Grant permission to see your device calendars.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => context.read<CalendarDataBloc>().add(
                const InitDeviceCalendar(fromButton: true),
              ),
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );
    }

    if (dataState.deviceCalendars.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'No calendars found on this device.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(dataState.deviceCalendars.length, (index) {
          final cal = dataState.deviceCalendars[index];
          final isChecked = dataState.checkedCalendarIds.contains(cal.id);
          final color = cal.color != null ? Color(cal.color!) : Colors.blue;

          return GestureDetector(
            onTap: () {
              if (cal.id != null) {
                context.read<CalendarDataBloc>().add(
                  ToggleDeviceCalendar(cal.id!),
                );
              }
            },
            child: GlassCard(
              color: color,
              opacity: isChecked ? 0.6 : 0.2,
              blur: 15,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              borderRadius: BorderRadius.circular(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cal.name ?? 'Unnamed Calendar',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isChecked
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildRemoteSubscriptionSidebar(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final url = authState is AuthAuthenticated
        ? authState.user.calendarSubscriptionUrl
        : null;
    final hasUrl = url != null && url.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text(
                'Remote Sync',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (hasUrl)
                IconButton(
                  icon: dataState.isLoadingRemote
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 18),
                  onPressed: dataState.isLoadingRemote
                      ? null
                      : () => context.read<CalendarDataBloc>().add(
                          LoadRemoteEvents(url),
                        ),
                ),
              IconButton(
                icon: const Icon(Icons.settings, size: 18),
                onPressed: () => _showSubscriptionDialog(context, url),
              ),
            ],
          ),
        ),
        if (!hasUrl)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No subscription URL set. Use a .ics URL for real-time sync.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: Text(
              'Syncing with ${dataState.remoteEvents.length} events.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () =>
                    context.read<CalendarDataBloc>().add(LoadSavedPlaces()),
              ),
            ],
          ),
        ),
        _buildPlacesSidebar(context),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text(
                'Device Calendars',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (dataState.hasCalendarPermission)
                IconButton(
                  icon: const Icon(Icons.sync, size: 18),
                  onPressed: () => context.read<CalendarDataBloc>().add(
                    const InitDeviceCalendar(fromButton: true),
                  ),
                ),
            ],
          ),
        ),
        _buildDeviceCalendarsSidebar(context),
        const Divider(),
        _buildRemoteSubscriptionSidebar(context),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text(
                'Imported Events',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (dataState.importedEvents.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => context.read<CalendarDataBloc>().add(
                    ClearImportedEvents(),
                  ),
                  tooltip: 'Clear Imported',
                ),
              IconButton(
                icon: const Icon(Icons.file_upload, size: 18),
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['ics'],
                    withData: true,
                  );
                  if (result != null && result.files.single.bytes != null) {
                    final icsString = utf8.decode(result.files.single.bytes!);
                    if (context.mounted) {
                      context.read<CalendarDataBloc>().add(
                        ImportIcalFile(icsString),
                      );
                    }
                  }
                },
                tooltip: 'Import .ics file',
              ),
            ],
          ),
        ),
        if (dataState.importedEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No events imported. Upload a .ics file to see external events.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Text(
              'Displaying ${dataState.importedEvents.length} imported events.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
  }
}
