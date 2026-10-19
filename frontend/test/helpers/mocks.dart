import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_event.dart';
import 'package:frontend/bloc/calendar/calendar_data_state.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/api_service.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// mocktail mocks shared across the suite. Register fallbacks for any custom
// type passed to `any()` with [registerFallbacks] in a setUpAll.

class MockApiService extends Mock implements ApiService {}

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class MockCalendarDataBloc
    extends MockBloc<CalendarDataEvent, CalendarDataState>
    implements CalendarDataBloc {}

class MockDeviceCalendarPlugin extends Mock implements DeviceCalendarPlugin {}

void registerFallbacks() {
  registerFallbackValue(User(id: 0, username: 'fallback'));
  registerFallbackValue(RetrieveEventsParams());
  registerFallbackValue(AppStarted());
  registerFallbackValue(LoadSavedPlaces());
}

/// A [GeolocatorPlatform] that answers from fields instead of the device.
///
/// Install with [FakeGeolocator.install], which restores the real platform
/// when the test ends.
class FakeGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  FakeGeolocator({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.permissionAfterRequest,
    this.position,
    this.positionError,
  });

  bool serviceEnabled;
  LocationPermission permission;

  /// What [requestPermission] grants; defaults to [permission].
  LocationPermission? permissionAfterRequest;
  Position? position;
  Object? positionError;
  int permissionRequests = 0;

  static FakeGeolocator install(
    void Function(void Function()) addTearDown, [
    FakeGeolocator? fake,
  ]) {
    final previous = GeolocatorPlatform.instance;
    final installed = fake ?? FakeGeolocator();
    GeolocatorPlatform.instance = installed;
    addTearDown(() => GeolocatorPlatform.instance = previous);
    return installed;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return permission = permissionAfterRequest ?? permission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (positionError != null) throw positionError!;
    return position ?? fakePosition(40.7356, -73.9990);
  }
}

Position fakePosition(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// A [FilePicker] that returns [result] instead of opening a native dialog.
class FakeFilePicker extends FilePicker with MockPlatformInterfaceMixin {
  FakeFilePicker([this.result]);

  FilePickerResult? result;
  int picks = 0;

  static FakeFilePicker install(
    void Function(void Function()) addTearDown, [
    FilePickerResult? result,
  ]) {
    final fake = FakeFilePicker(result);
    FilePicker.platform = fake;
    // FilePicker has no public getter for a restorable default; a fresh fake
    // per test is installed by whichever test needs one.
    addTearDown(() => FilePicker.platform = FakeFilePicker());
    return fake;
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    picks++;
    return result;
  }
}
