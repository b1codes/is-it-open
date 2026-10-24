import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/calendar/calendar_event_tile.dart';

import 'support/catalog.dart';
import 'support/text_contrast.dart';

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

/// Use cases whose text isn't checked for contrast: components shown on
/// the catalog's multicolor glass backdrop (ComponentStage's `backdrop`),
/// which the app never puts them on. The screens that use them are checked
/// on their real backgrounds.
const _contrastExempt = {
  'components/shared/glasscard/default',
  'components/shared/glasscontainer/default',
  'components/search/searchresultlistcard/results-list',
  'components/search/searchresultgridcard/results-grid',
};

void main() {
  for (final path in useCasePaths) {
    group(path, () {
      for (final theme in ['Light', 'Dark']) {
        for (final device in [_phone, _desktop]) {
          testWidgets('meets the guidelines, ${theme.toLowerCase()} '
              '${device.name}', (tester) async {
            final semantics = tester.ensureSemantics();
            await _pump(tester, path, device, theme: theme);

            // Calendar event blocks: their height is the event's duration on
            // the time grid, so a short event can't be a 48px target.
            final events = [
              for (final e in find.byType(CalendarEventTileWidget).evaluate())
                tester.getRect(find.byWidget(e.widget)),
            ];
            await expectLater(
              tester,
              meetsGuideline(_TapTarget.android(skipping: events)),
            );
            await expectLater(
              tester,
              meetsGuideline(_TapTarget.iOS(skipping: events)),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(
                _contrastExempt.contains(path)
                    ? const _Pass()
                    : const TextStyleContrastGuideline(),
              ),
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

/// [androidTapTargetGuideline] or [iOSTapTargetGuideline], skipping the
/// tap targets inside [skipping].
class _TapTarget extends MinimumTapTargetGuideline {
  const _TapTarget.android({required this.skipping})
    : super(
        size: const Size(48, 48),
        link: 'https://support.google.com/accessibility/android/answer/7101858',
      );

  const _TapTarget.iOS({required this.skipping})
    : super(
        size: const Size(44, 44),
        link:
            'https://developer.apple.com/design/human-interface-guidelines/accessibility#Buttons-and-controls',
      );

  final List<Rect> skipping;

  @override
  bool shouldSkipNode(SemanticsNode node) {
    if (super.shouldSkipNode(node)) return true;
    // The node's rect in the view (the test views have a pixel ratio of 1).
    var rect = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      if (n.transform case final transform?) {
        rect = MatrixUtils.transformRect(transform, rect);
      }
    }
    return skipping.any((r) => r.inflate(1).contains(rect.center));
  }
}

class _Pass extends AccessibilityGuideline {
  const _Pass();

  @override
  String get description => 'Not checked';

  @override
  Evaluation evaluate(WidgetTester tester) => const Evaluation.pass();
}
