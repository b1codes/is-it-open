import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/calendar/calendar_event_tile.dart';
import 'package:frontend/utils/app_theme.dart';
import 'package:frontend/utils/places_theme.dart';

// WCAG AA contrast for the color pairs the app draws text with, worked out
// from the colors themselves. The catalog-wide check in
// widgetbook/test/accessibility_test.dart measures rendered pixels instead,
// which can't read small text on the calendar grid; those colors are
// checked here.

/// The WCAG 2 contrast ratio of [foreground] (composited over [background]
/// if translucent) on [background].
double _contrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background).computeLuminance();
  final bg = background.computeLuminance();
  final (lighter, darker) = fg > bg ? (fg, bg) : (bg, fg);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Normal-size text (under 18px, or 14px bold).
const _aa = 4.5;

Matcher _meetsAA(String what) =>
    isA<double>().having((ratio) => ratio, what, greaterThanOrEqualTo(_aa));

void main() {
  for (final (name, theme) in [
    ('light', PlacesTheme.light),
    ('dark', PlacesTheme.dark),
  ]) {
    group('$name theme', () {
      test('text on the page and on raised surfaces', () {
        for (final surface in [theme.paper, theme.paperRaised]) {
          expect(_contrast(theme.ink, surface), _meetsAA('ink'));
          expect(_contrast(theme.inkMuted, surface), _meetsAA('inkMuted'));
          expect(_contrast(theme.anchor, surface), _meetsAA('anchor links'));
        }
      });

      // Selected chips and toggles put anchor text on an anchor tint of up
      // to 12%.
      test('anchor text on an anchor tint', () {
        for (final surface in [theme.paper, theme.paperRaised]) {
          final tint = Color.alphaBlend(
            theme.anchor.withValues(alpha: 0.12),
            surface,
          );
          expect(_contrast(theme.anchor, tint), _meetsAA('anchor on tint'));
        }
      });

      test('labels on filled buttons and status pills', () {
        expect(
          _contrast(theme.anchorOnContrast, theme.anchor),
          _meetsAA('anchorOnContrast on anchor'),
        );
        for (final kind in [
          PlaceStatusKind.open,
          PlaceStatusKind.closingSoon,
          PlaceStatusKind.closed,
        ]) {
          expect(
            _contrast(theme.statusOnContrast(kind), theme.statusColor(kind)),
            _meetsAA('${kind.name} pill'),
          );
        }
      });

      testWidgets('calendar event blocks', (tester) async {
        // As the calendar screen colors them: opening-hours blocks in a
        // translucent anchor, personal events in inkMuted.
        for (final (kind, color) in [
          ('opening hours', PlacesTheme.light.anchor.withValues(alpha: 0.15)),
          ('personal event', theme.inkMuted),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: name == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme,
              home: CalendarEventTileWidget(
                date: DateTime(2026, 6, 10),
                events: [
                  CalendarEventData(
                    title: 'Event',
                    date: DateTime(2026, 6, 10),
                    color: color,
                  ),
                ],
                boundary: Rect.zero,
                startDuration: DateTime(2026, 6, 10, 9),
                endDuration: DateTime(2026, 6, 10, 10),
              ),
            ),
          );
          final text = tester.widget<Text>(find.text('Event')).style!.color!;
          final fill =
              (tester
                          .widget<AnimatedContainer>(
                            find.byType(AnimatedContainer),
                          )
                          .decoration!
                      as BoxDecoration)
                  .color!;
          // The time grid behind the block is the page.
          final background = Color.alphaBlend(fill, theme.paper);
          expect(_contrast(text, background), _meetsAA(kind));
        }
      });
    });
  }

  test('PlacesTheme.onColor is readable on any color', () {
    // Every 17th step of each channel: 4,096 colors.
    for (var r = 0; r < 256; r += 17) {
      for (var g = 0; g < 256; g += 17) {
        for (var b = 0; b < 256; b += 17) {
          final color = Color.fromARGB(255, r, g, b);
          expect(
            _contrast(PlacesTheme.onColor(color), color),
            _meetsAA('on $color'),
          );
        }
      }
    }
  });

  group('app theme', () {
    test('filled button labels', () {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        final scheme = theme.colorScheme;
        expect(
          _contrast(scheme.onPrimary, scheme.primary),
          _meetsAA('${scheme.brightness.name} onPrimary on primary'),
        );
      }
      // ThermalButton's label, in either theme.
      expect(
        _contrast(Colors.white, AppColors.terracotta),
        _meetsAA('white on terracotta'),
      );
    });

    test('text on the page', () {
      final light = AppTheme.lightTheme;
      expect(
        _contrast(light.colorScheme.primary, light.scaffoldBackgroundColor),
        _meetsAA('light primary links'),
      );
      expect(
        _contrast(AppColors.inkWarmMuted, AppColors.paperWarm),
        _meetsAA('inkWarmMuted on paperWarm'),
      );
    });
  });
}
