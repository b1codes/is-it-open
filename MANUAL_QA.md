# Manual QA

Only what the automated suites can't check: native permission prompts, the device's own pickers and screen readers, and how the app feels on real hardware. Everything else is automated (see [TESTING.md](TESTING.md)), and a deployed backend is checked by the [smoke test](smoke/README.md).

**When:** before an App Store or Play Store release, and in a PR that changes a native plugin (`geolocator`, `device_calendar`, `file_picker`), a permission, or `Info.plist`/`AndroidManifest.xml`.
**On:** a physical iPhone and a physical Android phone, ideally a mid-range one. Simulators and emulators don't show real permission dialogs reliably, or real performance. Start from a fresh install, so the first-run prompts appear.

Copy the list into the PR or release notes and tick what you checked, noting the devices and OS versions.

## Location

- [ ] **Map, first launch:** the system location prompt appears once, with the "show your current position on the map and find nearby places" text on iOS.
- [ ] **Allow:** the map shows your position. It centers on you if you have no home address saved, or if "Use Current Location" is on.
- [ ] **Deny:** no error, and the map centers on your home address, or New York without one. Reopening the map doesn't prompt again on iOS.
- [ ] **Location services off** (system setting): the map falls back the same way, without a prompt.
- [ ] **Permission revoked in system settings while the app is backgrounded:** returning to the app doesn't crash, and when the map next opens it falls back.
- [ ] **Settings > Use Current Location:** turning it on prompts if needed and saves your position. With permission denied, or location services off, it shows "Location permissions are denied" or "Location services are disabled" and stays off. Note that it overwrites your home coordinates (#42), and that the phone layout can't reach Settings (#43).
- [ ] **Search suggestions:** with location allowed, suggestions are near you. With it denied, they're recently added places, and there's no prompt (search never asks for permission).

## Device calendar

- [ ] **First launch:** the calendar access prompt appears. On iOS 17 and later, it asks for full access, with the "display your events alongside business hours" text.
- [ ] **Allow:** your device calendars' events show in the planner, next to business hours, and in the right time zone.
- [ ] **Deny:** the app works normally, with no error at startup.
- [ ] **Choosing calendars, and the "enable" button after a denial:** these are in the calendar sidebar, which the app doesn't show yet (#44). Check them once it does: toggling a calendar shows or hides its events, and the button says to enable access in Settings.

## Importing an .ics file

The import is in the calendar sidebar too (#44). Once it's reachable:

- [ ] The system file picker opens and offers only `.ics` files (Files on iOS, the document picker on Android, including a file from cloud storage).
- [ ] Cancelling the picker changes nothing.
- [ ] An imported file's events, including recurring ones, show in the planner.

## Screen readers

The automated checks cover labels, tap target sizes, contrast and 2× text. Reading order and how it feels need a person.

- [ ] **VoiceOver (iOS) and TalkBack (Android):** sign in, search for a place, open it, bookmark it, and find it in My Places, using only the screen reader. Everything is announced in a sensible order, and every button says what it does.
- [ ] Map markers can be reached and opened, and a place's open/closed status is spoken in words.
- [ ] With the system's largest text size, and with bold text on, every screen stays usable.

## Real-device feel

- [ ] Panning and zooming the map with many bookmarks is smooth on the mid-range phone. The glass panels' blur is the most expensive part to draw.
- [ ] The keyboard never covers the field you're typing in (sign-in, search, profile), and the Android back gesture closes sheets and dialogs before it leaves a screen.
- [ ] Notches, the Dynamic Island and the gesture bar don't cover any content, in portrait and landscape.
- [ ] On a fresh install, the app follows the system's light or dark mode (until you pick one in the app), and it updates when the system switches while it's open.
- [ ] Map tiles and search work on a slow mobile connection, and a lost connection shows an error, not a spinner that never ends.

## Not checkable yet

- **Google and Apple sign-in:** both only build mock tokens, which a production backend rejects (#49). Username and password sign-in is the only kind that works against production.
- **iOS builds with Xcode 26 and later** fail until the deployment target is raised (#45).
