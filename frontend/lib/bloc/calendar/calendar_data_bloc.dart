import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart' show Color, Colors;
import 'calendar_data_event.dart';
import 'calendar_data_state.dart';
import '../../services/api_service.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:icalendar_parser/icalendar_parser.dart';
import 'dart:convert' show jsonEncode, jsonDecode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' show Platform;

class CalendarDataBloc extends Bloc<CalendarDataEvent, CalendarDataState> {
  final ApiService apiService;
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  CalendarDataBloc({required this.apiService}) : super(const CalendarDataState()) {
    on<LoadSavedPlaces>(_onLoadSavedPlaces);
    on<TogglePlaceFilter>(_onTogglePlaceFilter);
    on<InitDeviceCalendar>(_onInitDeviceCalendar);
    on<ToggleDeviceCalendar>(_onToggleDeviceCalendar);
    on<ImportIcalFile>(_onImportIcalFile);
    on<ClearImportedEvents>(_onClearImportedEvents);
    on<LoadRemoteEvents>(_onLoadRemoteEvents);
    on<LoadPersistedImportedEvents>(_onLoadPersistedImportedEvents);

    add(LoadPersistedImportedEvents());
  }

  Future<void> _onLoadSavedPlaces(LoadSavedPlaces event, Emitter<CalendarDataState> emit) async {
    emit(state.clearError().copyWith(status: CalendarDataStatus.loading));
    try {
      final bookmarks = await apiService.getBookmarks();
      emit(state.copyWith(status: CalendarDataStatus.loaded, savedPlaces: bookmarks));
    } catch (e) {
      emit(state.copyWith(status: CalendarDataStatus.error, errorMessage: 'Failed to load places: $e'));
    }
  }

  void _onTogglePlaceFilter(TogglePlaceFilter event, Emitter<CalendarDataState> emit) {
    final updatedIds = Set<String>.from(state.checkedPlaceIds);
    if (updatedIds.contains(event.tomtomId)) {
      updatedIds.remove(event.tomtomId);
    } else {
      updatedIds.add(event.tomtomId);
    }
    emit(state.clearError().copyWith(checkedPlaceIds: updatedIds));
  }

  Future<void> _onInitDeviceCalendar(InitDeviceCalendar event, Emitter<CalendarDataState> emit) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && (permissionsGranted.data == false)) {
        permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
      }

      if (permissionsGranted.isSuccess && permissionsGranted.data == true) {
        emit(state.copyWith(hasCalendarPermission: true));
        final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
        if (calendarsResult.isSuccess && calendarsResult.data != null) {
          emit(state.copyWith(deviceCalendars: calendarsResult.data!));
        }
      } else if (event.fromButton) {
        emit(state.copyWith(errorMessage: 'Calendar permission denied. Please enable in Settings.'));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error initializing device calendar: $e'));
    }
  }

  Future<void> _onToggleDeviceCalendar(ToggleDeviceCalendar event, Emitter<CalendarDataState> emit) async {
    final updatedIds = Set<String>.from(state.checkedCalendarIds);
    if (updatedIds.contains(event.calendarId)) {
      updatedIds.remove(event.calendarId);
    } else {
      updatedIds.add(event.calendarId);
    }
    
    emit(state.clearError().copyWith(checkedCalendarIds: updatedIds));
    await _fetchDeviceEvents(updatedIds, emit);
  }

  Future<void> _fetchDeviceEvents(Set<String> activeIds, Emitter<CalendarDataState> emit) async {
    if (activeIds.isEmpty) {
      emit(state.copyWith(deviceEvents: []));
      return;
    }

    final calendarColorMap = <String, Color>{};
    for (final cal in state.deviceCalendars) {
      if (cal.id != null) {
        calendarColorMap[cal.id!] = cal.color != null
            ? Color(cal.color!).withValues(alpha: 0.7)
            : Colors.blue.withValues(alpha: 0.7);
      }
    }

    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 28));
    final endDate = now.add(const Duration(days: 84));

    List<CalendarEventData<Object?>> allEvents = [];

    for (final calendarId in activeIds) {
      final calColor = calendarColorMap[calendarId] ?? Colors.blue.withValues(alpha: 0.7);

      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(startDate: startDate, endDate: endDate),
      );

      if (eventsResult.isSuccess && eventsResult.data != null) {
        for (final event in eventsResult.data!) {
          if (event.start != null && event.end != null) {
            if (event.allDay == true) {
              allEvents.add(
                CalendarEventData(
                  title: event.title ?? 'No Title',
                  date: event.start!,
                  endDate: event.end!.subtract(const Duration(days: 1)),
                  description: event.description,
                  color: calColor,
                ),
              );
            } else {
              allEvents.add(
                CalendarEventData(
                  title: event.title ?? 'No Title',
                  date: event.start!,
                  startTime: event.start!,
                  endTime: event.end!,
                  description: event.description,
                  color: calColor,
                ),
              );
            }
          }
        }
      }
    }
    emit(state.copyWith(deviceEvents: allEvents));
  }

  bool _isAllDayIcsDateTime(IcsDateTime dt) {
    return !dt.dt.contains('T');
  }

  List<CalendarEventData<Object?>> _parseIcsString(String icsString, Color eventColor) {
    final iCalendar = ICalendar.fromString(icsString);
    final List<CalendarEventData<Object?>> events = [];
    for (final entry in iCalendar.data) {
      if (entry['type'] == 'VEVENT') {
        final title = entry['summary'] ?? 'Event';
        final dtstart = entry['dtstart'] as IcsDateTime?;
        final dtend = entry['dtend'] as IcsDateTime?;
        final description = entry['description'];

        if (dtstart != null) {
          final isAllDay = _isAllDayIcsDateTime(dtstart);
          final start = dtstart.toDateTime();
          final end = dtend?.toDateTime() ?? start?.add(const Duration(hours: 1));

          if (start != null) {
            if (isAllDay) {
              final endDate = end != null ? end.subtract(const Duration(days: 1)) : start;
              events.add(CalendarEventData(
                title: title,
                date: start,
                endDate: endDate,
                description: description,
                color: eventColor,
              ));
            } else {
              events.add(CalendarEventData(
                title: title,
                date: start,
                startTime: start,
                endTime: end ?? start,
                description: description,
                color: eventColor,
              ));
            }
          }
        }
      }
    }
    return events;
  }

  void _onImportIcalFile(ImportIcalFile event, Emitter<CalendarDataState> emit) {
    try {
      final events = _parseIcsString(event.icsString, Colors.teal.withValues(alpha: 0.5));
      emit(state.clearError().copyWith(importedEvents: events));
      _persistImportedEvents(events);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error importing iCal: $e'));
    }
  }

  void _onClearImportedEvents(ClearImportedEvents event, Emitter<CalendarDataState> emit) {
    emit(state.clearError().copyWith(importedEvents: []));
    _persistImportedEvents([]);
  }

  Future<void> _onLoadRemoteEvents(LoadRemoteEvents event, Emitter<CalendarDataState> emit) async {
    if (event.url.isEmpty) return;
    emit(state.clearError().copyWith(isLoadingRemote: true));
    try {
      final icsString = await apiService.getCalendarFromUrl(event.url);
      final events = _parseIcsString(icsString, Colors.deepPurple.withValues(alpha: 0.5));
      emit(state.copyWith(remoteEvents: events, isLoadingRemote: false));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error fetching remote calendar: $e', isLoadingRemote: false));
    }
  }

  Future<void> _onLoadPersistedImportedEvents(LoadPersistedImportedEvents event, Emitter<CalendarDataState> emit) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? eventsJson = prefs.getString('persisted_imported_events');
      if (eventsJson != null) {
        final List<dynamic> decoded = jsonDecode(eventsJson);
        final List<CalendarEventData<Object?>> events = decoded.map((e) {
          return CalendarEventData(
            title: e['title'],
            date: DateTime.parse(e['date']),
            startTime: e['startTime'] != null ? DateTime.parse(e['startTime']) : null,
            endTime: e['endTime'] != null ? DateTime.parse(e['endTime']) : null,
            description: e['description'],
            color: Colors.teal.withValues(alpha: 0.5),
          );
        }).toList();
        emit(state.copyWith(importedEvents: events));
      }
    } catch (e) {
      debugPrint('Error loading persisted events: $e');
    }
  }
  
  Future<void> _persistImportedEvents(List<CalendarEventData> events) async {
     try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> toStore = events.map((e) {
        return {
          'title': e.title,
          'date': e.date.toIso8601String(),
          'startTime': e.startTime?.toIso8601String(),
          'endTime': e.endTime?.toIso8601String(),
          'description': e.description,
        };
      }).toList();
      await prefs.setString('persisted_imported_events', jsonEncode(toStore));
    } catch (e) {
      debugPrint('Error persisting events: $e');
    }
  }
}
