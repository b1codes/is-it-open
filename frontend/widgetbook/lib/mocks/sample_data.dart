import 'package:calendar_view/calendar_view.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:frontend/models/hours.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/utils/availability_calculator.dart';
import 'package:frontend/utils/place_status.dart';
import 'package:frontend/utils/places_theme.dart';
import 'package:latlong2/latlong.dart';

// Fixture data shared by every use case. Day-of-week follows the backend
// convention (Mon=0..Sun=6) used by BusinessHours.

List<BusinessHours> _everyDay(int openHour, int closeHour) => [
  for (var day = 0; day < 7; day++)
    BusinessHours(
      dayOfWeek: day,
      openTime: TimeOfDay(hour: openHour, minute: 0),
      closeTime: TimeOfDay(hour: closeHour, minute: 0),
    ),
];

final coffeePlace = Place(
  id: 1,
  tomtomId: 'tt_coffee',
  name: 'Blue Bottle Coffee',
  address: '450 W 15th St, New York, NY 10011',
  location: const LatLng(40.7420, -74.0048),
  phone: '+1 510-653-3394',
  website: 'https://bluebottlecoffee.com',
  categories: const ['cafe', 'coffee'],
  hours: _everyDay(7, 18),
);

final bistroPlace = Place(
  id: 2,
  tomtomId: 'tt_bistro',
  name: 'Corner Bistro',
  address: '331 W 4th St, New York, NY 10014',
  location: const LatLng(40.7380, -74.0035),
  phone: '+1 212-242-9502',
  categories: const ['restaurant', 'bar'],
  hours: [
    for (var day = 0; day < 4; day++)
      BusinessHours(
        dayOfWeek: day,
        openTime: const TimeOfDay(hour: 11, minute: 30),
        closeTime: const TimeOfDay(hour: 23, minute: 0),
      ),
    // Fri/Sat run past midnight.
    for (var day = 4; day < 6; day++)
      BusinessHours(
        dayOfWeek: day,
        openTime: const TimeOfDay(hour: 11, minute: 30),
        closeTime: const TimeOfDay(hour: 2, minute: 0),
      ),
    const BusinessHours(
      dayOfWeek: 6,
      openTime: TimeOfDay(hour: 12, minute: 0),
      closeTime: TimeOfDay(hour: 22, minute: 0),
    ),
  ],
);

final gymPlace = Place(
  id: 3,
  tomtomId: 'tt_gym',
  name: 'Harbor Fitness',
  address: '88 Pier Ave, Brooklyn, NY 11201',
  location: const LatLng(40.7003, -73.9967),
  website: 'https://example.com/harbor-fitness',
  categories: const ['gym'],
  hours: [
    for (var day = 0; day < 5; day++)
      BusinessHours(
        dayOfWeek: day,
        openTime: const TimeOfDay(hour: 5, minute: 0),
        closeTime: const TimeOfDay(hour: 22, minute: 0),
      ),
    for (var day = 5; day < 7; day++)
      BusinessHours(
        dayOfWeek: day,
        openTime: const TimeOfDay(hour: 7, minute: 0),
        closeTime: const TimeOfDay(hour: 20, minute: 0),
      ),
  ],
);

final libraryPlace = Place(
  id: 4,
  tomtomId: 'tt_library',
  name: 'Jefferson Market Library',
  address: '425 6th Ave, New York, NY 10011',
  location: const LatLng(40.7346, -73.9989),
  phone: '+1 212-243-4334',
  categories: const ['library'],
  hours: [
    // Split shift with a lunch closure, closed Sundays.
    for (var day = 0; day < 6; day++) ...[
      BusinessHours(
        dayOfWeek: day,
        openTime: const TimeOfDay(hour: 9, minute: 0),
        closeTime: const TimeOfDay(hour: 12, minute: 30),
      ),
      BusinessHours(
        dayOfWeek: day,
        openTime: const TimeOfDay(hour: 13, minute: 30),
        closeTime: const TimeOfDay(hour: 18, minute: 0),
      ),
    ],
  ],
);

// No published hours: exercises the "Hours unknown" paths.
const hardwarePlace = Place(
  id: 5,
  tomtomId: 'custom_hardware',
  name: 'Ace Hardware on Bleecker Street and Seventh Avenue South',
  address: '160 Bleecker St, New York, NY 10012',
  location: LatLng(40.7286, -74.0004),
);

final samplePlaces = <Place>[
  coffeePlace,
  bistroPlace,
  gymPlace,
  libraryPlace,
  hardwarePlace,
];

final sampleSavedPlaces = <SavedPlace>[
  SavedPlace(
    id: 101,
    place: coffeePlace,
    icon: 'local_cafe',
    color: 'ffb14e27',
    isPinned: true,
    averageVisitLength: 30,
  ),
  SavedPlace(
    id: 102,
    place: bistroPlace,
    customName: 'Friday burger spot',
    icon: 'restaurant',
    color: 'ffd99b52',
    isPinned: true,
    averageVisitLength: 90,
  ),
  SavedPlace(
    id: 103,
    place: gymPlace,
    icon: 'fitness_center',
    color: 'ff6b5344',
    averageVisitLength: 60,
  ),
  SavedPlace(
    id: 104,
    place: libraryPlace,
    icon: 'star',
    color: 'ff8f7a6a',
    isCheckItOut: true,
  ),
  SavedPlace(
    id: 105,
    place: hardwarePlace,
    icon: 'store',
    color: 'ff9e8b7e',
    isCheckItOut: true,
  ),
];

final demoUser = User(
  id: 1,
  username: 'demo',
  email: 'demo@isitopen.app',
  firstName: 'Avery',
  lastName: 'Park',
  homeAddress: '120 W 11th St, New York, NY 10011',
  homeStreet: '120 W 11th St',
  homeCity: 'New York',
  homeState: 'NY',
  homeZip: '10011',
  homeLat: 40.7356,
  homeLng: -73.9990,
  workAddress: '1 World Trade Center, New York, NY 10007',
  workStreet: '1 World Trade Center',
  workCity: 'New York',
  workState: 'NY',
  workZip: '10007',
  workLat: 40.7127,
  workLng: -74.0134,
  calendarSubscriptionUrl: 'https://calendar.example.com/demo.ics',
  token: 'widgetbook-token',
);

// A freshly registered account with nothing filled in.
final minimalUser = User(
  id: 2,
  username: 'newcomer',
  token: 'widgetbook-token',
);

// Pill statuses are passed in directly so component previews stay stable
// regardless of the wall clock.
const openStatus = PlaceStatus(
  kind: PlaceStatusKind.open,
  supporting: 'until 6pm',
);
const closingSoonStatus = PlaceStatus(
  kind: PlaceStatusKind.closingSoon,
  supporting: 'in 25 min',
);
const closedStatus = PlaceStatus(
  kind: PlaceStatusKind.closed,
  supporting: 'opens 9am tomorrow',
);
const unknownStatus = PlaceStatus(
  kind: PlaceStatusKind.unknown,
  supporting: '',
);

final sampleStatuses = <PlaceStatusKind, PlaceStatus>{
  PlaceStatusKind.open: openStatus,
  PlaceStatusKind.closingSoon: closingSoonStatus,
  PlaceStatusKind.closed: closedStatus,
  PlaceStatusKind.unknown: unknownStatus,
};

DateTime _at(DateTime day, int hour, [int minute = 0]) =>
    DateTime(day.year, day.month, day.day, hour, minute);

DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

// Personal calendar events around [anchor], spread across the week that
// contains it so the week, three-day and single-day views all show content.
List<CalendarEventData<Object?>> sampleCalendarEvents(DateTime anchor) {
  final day = dateOnly(anchor);
  final tomorrow = day.add(const Duration(days: 1));
  final twoDays = day.add(const Duration(days: 2));
  return [
    CalendarEventData(
      title: 'Standup',
      description: 'Daily sync with the product team.',
      date: day,
      startTime: _at(day, 9, 30),
      endTime: _at(day, 9, 45),
      color: Colors.deepPurple.withValues(alpha: 0.5),
    ),
    CalendarEventData(
      title: 'Design review',
      description: 'Walk through the Map-First workspace.',
      date: day,
      startTime: _at(day, 13),
      endTime: _at(day, 14, 30),
      color: Colors.teal.withValues(alpha: 0.5),
    ),
    CalendarEventData(
      title: 'Dentist',
      date: tomorrow,
      startTime: _at(tomorrow, 11),
      endTime: _at(tomorrow, 12),
      color: Colors.deepPurple.withValues(alpha: 0.5),
    ),
    CalendarEventData(
      title: 'Dinner with Sam',
      description: 'Corner Bistro, 7pm.',
      date: twoDays,
      startTime: _at(twoDays, 19),
      endTime: _at(twoDays, 21),
      color: Colors.teal.withValues(alpha: 0.5),
    ),
    CalendarEventData(
      title: 'Out of office',
      description: 'Long weekend upstate.',
      date: twoDays,
      endDate: twoDays.add(const Duration(days: 1)),
      color: Colors.blueGrey.withValues(alpha: 0.6),
    ),
  ];
}

DateTime? _currentWeekEventsDay;
List<CalendarEventData<Object?>> _currentWeekEvents = const [];

// Cached per calendar day so scopes keyed on calendar state stay stable
// across rebuilds (CalendarEventData has identity equality), while still
// moving with the other clock-anchored fixtures past midnight.
List<CalendarEventData<Object?>> get currentWeekEvents {
  final now = clock.now();
  final today = DateTime(now.year, now.month, now.day);
  if (_currentWeekEventsDay != today) {
    _currentWeekEventsDay = today;
    _currentWeekEvents = sampleCalendarEvents(now);
  }
  return _currentWeekEvents;
}

// Personal events in the {title, startTime, endTime} map shape PlannerView
// and AvailabilityCalculator consume.
List<Map<String, dynamic>> samplePersonalEvents(DateTime anchor) {
  return sampleCalendarEvents(anchor)
      .where((e) => e.startTime != null && e.endTime != null)
      .map(
        (e) => <String, dynamic>{
          'title': e.title,
          'startTime': e.startTime!,
          'endTime': e.endTime!,
        },
      )
      .toList();
}

List<AvailabilityWindow> sampleAvailabilityWindows(
  DateTime anchor, {
  int dayCount = 3,
}) {
  final day = dateOnly(anchor);
  return [
    for (var offset = 0; offset < dayCount; offset++) ...[
      AvailabilityWindow(
        date: day.add(Duration(days: offset)),
        startTime: _at(day.add(Duration(days: offset)), 7),
        endTime: _at(day.add(Duration(days: offset)), 9),
        placeCount: 2,
        placeIds: const ['tt_coffee', 'tt_gym'],
      ),
      AvailabilityWindow(
        date: day.add(Duration(days: offset)),
        startTime: _at(day.add(Duration(days: offset)), 15),
        endTime: _at(day.add(Duration(days: offset)), 18),
        placeCount: 4,
        placeIds: const ['tt_coffee', 'tt_bistro', 'tt_gym', 'tt_library'],
      ),
    ],
  ];
}

// Served by FakeApiService.getCalendarFromUrl so the remote-sync path parses
// real iCal through IcalParserService.
String sampleIcs(DateTime anchor) {
  String stamp(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}T'
      '${dt.hour.toString().padLeft(2, '0')}'
      '${dt.minute.toString().padLeft(2, '0')}00';
  final day = dateOnly(anchor);
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Is It Open//Widgetbook//EN',
    'BEGIN:VEVENT',
    'UID:widgetbook-1@isitopen.app',
    'DTSTAMP:${stamp(day)}',
    'DTSTART:${stamp(_at(day, 16))}',
    'DTEND:${stamp(_at(day, 17))}',
    'SUMMARY:Remote: Yoga class',
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
}
