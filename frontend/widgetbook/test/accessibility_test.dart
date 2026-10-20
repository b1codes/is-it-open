import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/calendar/calendar_event_tile.dart';

import 'support/catalog.dart';

// Accessibility checks for every catalog use case, so every screen and
// component is covered:
//
// - Flutter's accessibility guidelines, in light and dark, at phone and
//   desktop widths: tap targets of at least 48×48 (Android) and 44×44 (iOS),
//   a label on everything tappable, and WCAG AA text contrast.
// - Text at 2× (the largest the catalog offers) at phone, tablet and desktop
//   widths, with no layout overflow.
//
// Unlike the goldens, these run on every platform.

/// The goldens' "now", so the calendar and opening hours match them.
final _now = DateTime(2026, 6, 10, 10, 30);

class _Device {
  const _Device(this.name, this.size);

  final String name;
  final Size size;
}

const _phone = _Device('phone', Size(390, 844));
const _tablet = _Device('tablet', Size(834, 1194));
const _desktop = _Device('desktop', Size(1280, 800));

/// Text the contrast check reads wrongly, by use case. The check finds the
/// two most common colors around a piece of text and takes them as text and
/// background, which fails when the text has fewer pixels than the
/// background's own shades. Each of these was checked by hand.
const _contrastExempt = <String, Set<String>>{
  // The calendar grid: hour lines, day columns and translucent blocks
  // behind small labels. The colors are checked directly in the app's
  // test/accessibility/contrast_test.dart.
  'components/calendar/calendarviewstackwidget/default': _anyText,
  'components/calendar/calendareventtilewidget/business-block': _anyText,
  'components/calendar/calendareventtilewidget/personal-event': _anyText,
  'components/calendar/fulldayeventwidget/single-event': _anyText,
  'components/calendar/fulldayeventwidget/multiple-events': _anyText,
  'components/calendar/plannerview/default': _anyText,
  'components/calendar/plannerview/empty': _anyText,
  'screens/calendar/calendarscreen/default': _anyText,
  'screens/calendar/calendarscreen/loading-places': _anyText,
  'screens/calendar/calendarscreen/no-saved-places': _anyText,
  // Glass on the catalog's multicolor backdrop, which the app never puts
  // glass on. The screens that use glass are checked on their real
  // backgrounds.
  'components/shared/glasscard/default': _anyText,
  'components/shared/glasscontainer/default': _anyText,
  // A lone "1": too thin a glyph for any of its pixels to be the text color.
  'screens/places/myplacesscreen/default': {'1'},
  // The screen is transparent (the home shell paints behind it), so the
  // catalog's grid shows through.
  'screens/search/searchscreen/default': {
    'No suggestions available.\nTry searching for something!',
  },
  // Section headers over the screen's gradient.
  'screens/profile/settingsscreen/default': {
    'Location Preferences',
    'App Preferences',
  },
};

/// Stands for every piece of text in a use case in [_contrastExempt].
const _anyText = {'*'};

void main() {
  for (final path in useCasePaths) {
    group(path, () {
      for (final theme in ['Light', 'Dark']) {
        for (final device in [_phone, _desktop]) {
          testWidgets('meets the guidelines, ${theme.toLowerCase()} '
              '${device.name}', (tester) async {
            final semantics = tester.ensureSemantics();
            await _pump(tester, path, device, theme: theme);

            await expectLater(tester, meetsGuideline(_androidTapTarget));
            await expectLater(tester, meetsGuideline(_iOSTapTarget));
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(_TextContrast(_contrastExempt[path] ?? const {})),
            );

            await unmountUseCase(tester);
            semantics.dispose();
          });
        }
      }

      for (final device in [_phone, _tablet, _desktop]) {
        // A RenderFlex overflow is reported as an error, which fails the
        // test.
        testWidgets('lays out at 2× text, ${device.name}', (tester) async {
          await _pump(tester, path, device, textScale: 2);
          await unmountUseCase(tester);
        });
      }
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  String path,
  _Device device, {
  String theme = 'Light',
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = device.size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await withClock(
    Clock.fixed(_now),
    () => pumpUseCase(tester, path, theme: theme, textScale: textScale),
  );
}

/// [androidTapTargetGuideline] and [iOSTapTargetGuideline], except for
/// calendar event blocks, whose height is the event's duration on the time
/// grid.
const _androidTapTarget = _TapTarget(
  size: Size(48, 48),
  link: 'https://support.google.com/accessibility/android/answer/7101858',
);
const _iOSTapTarget = _TapTarget(
  size: Size(44, 44),
  link:
      'https://developer.apple.com/design/human-interface-guidelines/accessibility#Buttons-and-controls',
);

class _TapTarget extends MinimumTapTargetGuideline {
  const _TapTarget({required super.size, required super.link});

  @override
  bool shouldSkipNode(SemanticsNode node) =>
      node.getSemanticsData().identifier ==
          CalendarEventTileWidget.semanticsIdentifier ||
      super.shouldSkipNode(node);
}

/// [textContrastGuideline], skipping the [exempt] text.
class _TextContrast extends MinimumTextContrastGuideline {
  const _TextContrast(this.exempt);

  final Set<String> exempt;

  @override
  bool shouldSkipNode(SemanticsData data) =>
      exempt.contains('*') ||
      exempt.contains(data.label) ||
      super.shouldSkipNode(data);
}
