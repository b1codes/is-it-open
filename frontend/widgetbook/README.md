# Is It Open? Widgetbook

A [Widgetbook](https://docs.widgetbook.io/) catalog of every component in
`frontend/lib/components` and every screen in `frontend/lib/screens`. Each one
has interactive previews with knobs, theme/viewport/text-scale addons, and
canned data, so no backend or sign-in is needed.

## Run it

```bash
cd frontend/widgetbook
flutter pub get
flutter run -d chrome   # or -d macos
```

Map tiles (OpenStreetMap / CARTO) load over the network. The app's Google
Fonts (Montserrat, Open Sans) are bundled in `assets/google_fonts/` (see
`tool/fetch_fonts.sh`).

## Layout

```
lib/
├── main.dart                  # Widgetbook app + addons (@App)
├── main.directories.g.dart    # Generated: the navigation tree
├── mocks/
│   ├── sample_data.dart       # Places, saved places, users, events
│   ├── fake_api_service.dart  # In-memory ApiService (latency/failure knobs)
│   ├── seeded_blocs.dart      # AuthBloc / CalendarDataBloc with a seed state
│   └── mock_app_scope.dart    # Provides everything MyApp would
└── use_cases/
    ├── components/…           # Mirrors lib/components/…
    ├── screens/…              # Mirrors lib/screens/…
    └── support/               # Stage, route harness, embedded-mode helpers
```

The navigation tree mirrors the app's folders, because the generator groups
use cases by the import path of the widget they document.

### Mock app scope

Screens and stateful components read blocs and `ApiService` from context.
Wrap them in `MockAppScope`, which provides the same repositories and blocs
`MyApp` does, backed by `FakeApiService`:

```dart
MockAppScope(
  authState: AuthAuthenticated(user: minimalUser), // default: demoUser
  bookmarks: const [],                            // default: sampleSavedPlaces
  todayRouteIds: ['tt_coffee'],
  use24HourFormat: true,
  apiFails: true,      // every request throws
  apiLatency: null,    // every request hangs (loading states)
  child: const MyPlacesScreen(),
)
```

The blocs are real, so interactions such as saving a place, adding it to
today's route, or toggling calendar filters work end to end against the
in-memory data. `SharedPreferences` is replaced with an in-memory store, so
the catalog never touches real device storage.

### Route harness

Widgets that `Navigator.pop` themselves (dialogs, sheets, pushed screens)
would blank the preview. Wrap them in `RouteHarness`, which hosts them on a
nested navigator and shows the popped result with a "Reopen" button.

## Adding a use case

1. Create (or extend) the file under `lib/use_cases/` that mirrors the
   widget's location in `frontend/lib`.
2. Annotate a top-level builder:

   ```dart
   @widgetbook.UseCase(name: 'Default', type: StatusPill)
   Widget buildStatusPillUseCase(BuildContext context) {
     return ComponentStage(child: StatusPill(status: openStatus));
   }
   ```

3. Regenerate the directory tree:

   ```bash
   dart run build_runner build --force-jit
   ```

   (`--force-jit` works around build_runner failing to AOT-compile builders
   when dependencies ship build hooks.)

4. Run `flutter test`. The smoke test renders every use case in the app's
   real fonts and fails on any exception, RenderFlex overflows included.
   The accessibility test checks it against Flutter's accessibility
   guidelines (tap target size, labels, text contrast) and at 2× text. See
   "Accessibility" in `../../TESTING.md`.

5. Push, and let CI's Goldens job render the new use case's goldens (light
   and dark × phone, tablet and desktop × text scale 1.0 and 2.0). It fails
   because they're missing; `make goldens-pull` fetches them. Review, then
   commit `test/goldens/`. See "Visual regression" in `../../TESTING.md`.

Use cases that depend on "now" (calendar, place status) read `clock.now()`,
as the app does: the wall clock in the catalog, a fixed time in the golden
tests. Component previews such as `StatusPill` take fixed
`PlaceStatus` values so they stay stable for visual review.
