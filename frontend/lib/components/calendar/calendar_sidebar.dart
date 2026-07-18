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
import '../../utils/places_theme.dart';

String displayName(SavedPlace sp) {
  if (sp.customName != null && sp.customName!.isNotEmpty) {
    return sp.customName!;
  }
  return sp.place.name;
}

void _showSubscriptionDialog(BuildContext context, String? currentUrl) {
  final theme = context.places;
  final controller = TextEditingController(text: currentUrl ?? '');
  final authBloc = context.read<AuthBloc>();
  final dataBloc = context.read<CalendarDataBloc>();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        'Calendar Subscription',
        style: PlacesType.headline(theme.ink),
      ),
      backgroundColor: theme.paperRaised,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Enter a "Secret iCal URL" (ends in .ics) from iCloud, Outlook, or Proton.',
            style: PlacesType.bodySmall(theme.ink),
          ),
          const SizedBox(height: PlacesSpacing.lg),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'iCal URL',
              labelStyle: PlacesType.bodySmall(theme.inkMuted),
              hintText: 'https://example.com/calendar.ics',
              border: const OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: theme.anchor, width: 2),
              ),
            ),
            style: PlacesType.bodySmall(theme.ink),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: PlacesType.body(theme.ink)),
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
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.anchor,
            foregroundColor: theme.anchorOnContrast,
            elevation: 0,
          ),
          child: Text(
            'Save & Sync',
            style: PlacesType.body(
              theme.anchorOnContrast,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class CalendarSidebarWidget extends StatelessWidget {
  final CalendarDataState dataState;
  final Color Function(SavedPlace, int) colorForPlace;
  final Map<String, IconData> availableIcons;
  final bool isCollapsed;

  const CalendarSidebarWidget({
    super.key,
    required this.dataState,
    required this.colorForPlace,
    required this.availableIcons,
    this.isCollapsed = false,
  });

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    Widget? trailing,
  }) {
    final theme = context.places;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlacesSpacing.xl,
        PlacesSpacing.xxl,
        PlacesSpacing.xl,
        PlacesSpacing.md,
      ),
      child: Row(
        children: [
          Text(title, style: PlacesType.title(theme.ink)),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildCollapsedSidebar(BuildContext context) {
    final theme = context.places;
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: PlacesSpacing.xxl),
          // Places
          ...List.generate(dataState.savedPlaces.length, (index) {
            final sp = dataState.savedPlaces[index];
            final isChecked = dataState.checkedPlaceIds.contains(
              sp.place.tomtomId,
            );
            final color = colorForPlace(sp, index);
            final iconName = sp.icon ?? 'star';
            final iconData = availableIcons[iconName] ?? Icons.star;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Tooltip(
                message: displayName(sp),
                child: Semantics(
                  button: true,
                  selected: isChecked,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: InkWell(
                      onTap: () {
                        context.read<CalendarDataBloc>().add(
                          TogglePlaceFilter(sp.place.tomtomId),
                        );
                      },
                      borderRadius: BorderRadius.circular(PlacesRadius.pill),
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isChecked ? color : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isChecked
                                  ? color
                                  : color.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            iconData,
                            color: isChecked ? Colors.white : color,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Divider(color: theme.ashSoft, indent: 16, endIndent: 16),
          ),
          // Device Calendars
          ...List.generate(dataState.deviceCalendars.length, (index) {
            final cal = dataState.deviceCalendars[index];
            final isChecked = dataState.checkedCalendarIds.contains(cal.id);
            final color = cal.color != null ? Color(cal.color!) : Colors.blue;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Tooltip(
                message: cal.name ?? 'Unnamed Calendar',
                child: Semantics(
                  button: true,
                  selected: isChecked,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: InkWell(
                      onTap: () {
                        if (cal.id != null) {
                          context.read<CalendarDataBloc>().add(
                            ToggleDeviceCalendar(cal.id!),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(PlacesRadius.pill),
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isChecked ? color : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isChecked
                                  ? color
                                  : color.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: isChecked ? Colors.white : color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Divider(color: theme.ashSoft, indent: 16, endIndent: 16),
          ),
          // Import action
          Tooltip(
            message: 'Import .ics file',
            child: IconButton(
              icon: Icon(Icons.file_upload, color: theme.ink),
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
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPlacesSidebar(BuildContext context) {
    final theme = context.places;
    if (dataState.status == CalendarDataStatus.loading) {
      return Center(child: CircularProgressIndicator(color: theme.anchor));
    }

    if (dataState.savedPlaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_border, size: 48, color: theme.ash),
              const SizedBox(height: 12),
              Text(
                'No saved places yet',
                style: PlacesType.bodySmall(theme.inkMuted),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PlacesSpacing.xl),
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

          return Semantics(
            button: true,
            selected: isChecked,
            child: GestureDetector(
              onTap: () {
                context.read<CalendarDataBloc>().add(
                  TogglePlaceFilter(sp.place.tomtomId),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isChecked ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(PlacesRadius.lg),
                  border: Border.all(
                    color: isChecked ? color : color.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      iconData,
                      color: isChecked ? Colors.white : color,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      displayName(sp),
                      style:
                          PlacesType.label(
                            isChecked ? Colors.white : theme.ink,
                          ).copyWith(
                            fontWeight: isChecked
                                ? FontWeight.w600
                                : FontWeight.w500,
                            letterSpacing: 0,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDeviceCalendarsSidebar(BuildContext context) {
    final theme = context.places;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: PlacesSpacing.xl),
        child: Column(
          children: [
            Icon(Icons.devices_other, size: 32, color: theme.ash),
            const SizedBox(height: 8),
            Text(
              'Device sync is available on Mobile only. For Web/Desktop, consider cloud sync (coming soon).',
              textAlign: TextAlign.center,
              style: PlacesType.bodySmall(theme.inkMuted),
            ),
          ],
        ),
      );
    }

    if (!dataState.hasCalendarPermission) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: PlacesSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Grant permission to see your device calendars.',
              style: PlacesType.bodySmall(theme.ink),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.read<CalendarDataBloc>().add(
                const InitDeviceCalendar(fromButton: true),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.ink,
                side: BorderSide(color: theme.ash),
              ),
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );
    }

    if (dataState.deviceCalendars.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: PlacesSpacing.xl),
        child: Text(
          'No calendars found on this device.',
          style: PlacesType.bodySmall(theme.ink),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PlacesSpacing.xl),
      child: Column(
        children: List.generate(dataState.deviceCalendars.length, (index) {
          final cal = dataState.deviceCalendars[index];
          final isChecked = dataState.checkedCalendarIds.contains(cal.id);
          final color = cal.color != null ? Color(cal.color!) : Colors.blue;

          return Semantics(
            button: true,
            selected: isChecked,
            child: GestureDetector(
              onTap: () {
                if (cal.id != null) {
                  context.read<CalendarDataBloc>().add(
                    ToggleDeviceCalendar(cal.id!),
                  );
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isChecked ? theme.paperRaised : Colors.transparent,
                  borderRadius: BorderRadius.circular(PlacesRadius.sm),
                  border: Border.all(
                    color: isChecked ? theme.ash : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isChecked ? color : Colors.transparent,
                        border: Border.all(color: color, width: 2),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        cal.name ?? 'Unnamed Calendar',
                        style: PlacesType.bodySmall(theme.ink).copyWith(
                          fontWeight: isChecked
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildRemoteSubscriptionSidebar(BuildContext context) {
    final theme = context.places;
    final authState = context.watch<AuthBloc>().state;
    final url = authState is AuthAuthenticated
        ? authState.user.calendarSubscriptionUrl
        : null;
    final hasUrl = url != null && url.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context,
          'Remote Sync',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasUrl)
                IconButton(
                  icon: dataState.isLoadingRemote
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.anchor,
                          ),
                        )
                      : Icon(Icons.sync, size: 20, color: theme.ink),
                  onPressed: dataState.isLoadingRemote
                      ? null
                      : () => context.read<CalendarDataBloc>().add(
                          LoadRemoteEvents(url),
                        ),
                ),
              IconButton(
                icon: Icon(Icons.settings, size: 20, color: theme.ink),
                onPressed: () => _showSubscriptionDialog(context, url),
              ),
            ],
          ),
        ),
        if (!hasUrl)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PlacesSpacing.xl),
            child: Text(
              'No subscription URL set. Use a .ics URL for real-time sync.',
              style: PlacesType.bodySmall(theme.inkMuted),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PlacesSpacing.xl),
            child: Text(
              'Syncing with ${dataState.remoteEvents.length} events.',
              style: PlacesType.bodySmall(theme.ink),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    if (isCollapsed) {
      return _buildCollapsedSidebar(context);
    }
    return ListView(
      children: [
        _buildSectionHeader(
          context,
          'My Places',
          trailing: IconButton(
            icon: Icon(Icons.refresh, size: 20, color: theme.ink),
            onPressed: () =>
                context.read<CalendarDataBloc>().add(LoadSavedPlaces()),
          ),
        ),
        _buildPlacesSidebar(context),

        const SizedBox(height: 16),
        Divider(color: theme.ashSoft, height: 1),

        _buildSectionHeader(
          context,
          'Device Calendars',
          trailing: dataState.hasCalendarPermission
              ? IconButton(
                  icon: Icon(Icons.sync, size: 20, color: theme.ink),
                  onPressed: () => context.read<CalendarDataBloc>().add(
                    const InitDeviceCalendar(fromButton: true),
                  ),
                )
              : null,
        ),
        _buildDeviceCalendarsSidebar(context),

        const SizedBox(height: 16),
        Divider(color: theme.ashSoft, height: 1),

        _buildRemoteSubscriptionSidebar(context),

        const SizedBox(height: 16),
        Divider(color: theme.ashSoft, height: 1),

        _buildSectionHeader(
          context,
          'Imported Events',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dataState.importedEvents.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: theme.ink),
                  onPressed: () => context.read<CalendarDataBloc>().add(
                    ClearImportedEvents(),
                  ),
                  tooltip: 'Clear Imported',
                ),
              IconButton(
                icon: Icon(Icons.file_upload, size: 20, color: theme.ink),
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
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(
              'No events imported. Upload a .ics file to see external events.',
              style: PlacesType.bodySmall(theme.inkMuted),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(
              'Displaying ${dataState.importedEvents.length} imported events.',
              style: PlacesType.bodySmall(theme.ink),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}
