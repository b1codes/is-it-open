import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG AA text contrast (4.5:1, or 3:1 for large text), for every piece of
/// visible text.
///
/// Flutter's textContrastGuideline takes the two most common colors around
/// a piece of text as its color and the background's. That depends on how
/// the platform anti-aliases glyphs: on Linux, at 1×, few pixels of thin
/// text reach the text's color, so it reported ink on paper as 1.5:1. Here
/// the text's color comes from its style, which is exact, and only the
/// background is read from the rendered pixels: the most common color
/// behind the text, ignoring pixels close to the text's own color.
///
/// Skips text that's disabled (WCAG exempts inactive controls), fully
/// transparent, or covered, and icons.
class TextStyleContrastGuideline extends AccessibilityGuideline {
  const TextStyleContrastGuideline();

  @override
  String get description =>
      'Text contrast should be at least 4.5:1 (3:1 for large text)';

  @override
  Future<Evaluation> evaluate(WidgetTester tester) async {
    var result = const Evaluation.pass();
    for (final view in tester.binding.renderViews) {
      final layer = view.debugLayer! as OffsetLayer;
      final pixelRatio = 1 / view.flutterView.devicePixelRatio;
      final (image, bytes) = (await tester.binding.runAsync(() async {
        final image = await layer.toImage(
          view.paintBounds,
          pixelRatio: pixelRatio,
        );
        final bytes = await image.toByteData();
        return (image, bytes!);
      }))!;
      final pixels = _Pixels(bytes, image.width, image.height);
      image.dispose();

      for (final element in find.byType(RichText).hitTestable().evaluate()) {
        result += _evaluate(tester, element, pixels);
      }
    }
    return result;
  }

  Evaluation _evaluate(WidgetTester tester, Element element, _Pixels pixels) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText().trim();
    // Icons are glyphs in the Unicode private use area. Text contrast
    // doesn't cover them.
    final isIcon = text.runes.every((c) => c >= 0xE000 && c <= 0xF8FF);
    if (text.isEmpty || isIcon) return const Evaluation.pass();

    final opacity = _opacity(paragraph);
    if (opacity == 0) return const Evaluation.pass();
    if (_isDisabled(tester, element)) return const Evaluation.pass();

    final rect = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      Offset.zero & paragraph.size,
    );

    var result = const Evaluation.pass();
    for (final style in _styles(paragraph.text)) {
      final color = style.color!;
      final textColor = color.withValues(alpha: color.a * opacity);
      final background = pixels.background(rect, excluding: textColor);
      if (background == null) continue;
      final ratio = contrastRatio(textColor, background);
      final target = _isLarge(style) ? 3.0 : 4.5;
      if (ratio < target - 0.01) {
        result += Evaluation.fail(
          '"$text": ${ratio.toStringAsFixed(2)}:1 for '
          '${style.fontSize}px text, under $target:1. Text $textColor on '
          '$background.',
        );
      }
    }
    return result;
  }

  /// The styles the text's characters are drawn in, each once.
  static Set<TextStyle> _styles(InlineSpan root) {
    final styles = <TextStyle>{};
    void visit(InlineSpan span, TextStyle? inherited) {
      final style = inherited?.merge(span.style) ?? span.style;
      if (span is TextSpan) {
        if ((span.text ?? '').trim().isNotEmpty && style?.color != null) {
          styles.add(style!);
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, style);
        }
      }
    }

    visit(root, null);
    return styles;
  }

  /// WCAG's large text, with Flutter's thresholds: 18px, or 14px bold.
  static bool _isLarge(TextStyle style) {
    final size = style.fontSize ?? 14;
    final bold = (style.fontWeight ?? FontWeight.normal).value >= 700;
    return size >= 18 || (bold && size >= 14);
  }

  /// The combined opacity of the Opacity widgets above [object].
  static double _opacity(RenderObject object) {
    var opacity = 1.0;
    for (RenderObject? o = object; o != null; o = o.parent) {
      if (o is RenderOpacity) opacity *= o.opacity;
      if (o is RenderAnimatedOpacity) opacity *= o.opacity.value;
    }
    return opacity;
  }

  static bool _isDisabled(WidgetTester tester, Element element) {
    final node = tester.getSemantics(
      find.byElementPredicate((e) => e == element),
    );
    return node.getSemanticsData().flagsCollection.isEnabled ==
        ui.Tristate.isFalse;
  }
}

/// The WCAG 2 contrast ratio of [foreground], composited over [background],
/// on [background].
double contrastRatio(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background).computeLuminance();
  final bg = background.computeLuminance();
  return (math.max(fg, bg) + 0.05) / (math.min(fg, bg) + 0.05);
}

class _Pixels {
  _Pixels(this.bytes, this.width, this.height);

  final ByteData bytes;
  final int width;
  final int height;

  /// The most common color in [rect] other than the text's: pixels within a
  /// small distance of [excluding] (the text and its anti-aliased edge) are
  /// left out, unless they're most of the rect, which means the background
  /// itself is that close to the text's color.
  Color? background(Rect rect, {required Color excluding}) {
    final clipped = rect.intersect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    if (clipped.width < 1 || clipped.height < 1) return null;
    final exclude = Color.alphaBlend(excluding, const Color(0xFFFFFFFF));
    final all = <int, int>{}, other = <int, int>{};
    var total = 0;
    for (var y = clipped.top.floor(); y < clipped.bottom.ceil(); y++) {
      for (var x = clipped.left.floor(); x < clipped.right.ceil(); x++) {
        final i = (y * width + x) * 4;
        final r = bytes.getUint8(i), g = bytes.getUint8(i + 1);
        final b = bytes.getUint8(i + 2);
        final key = (r << 16) | (g << 8) | b;
        total++;
        all[key] = (all[key] ?? 0) + 1;
        if (!_near(r, g, b, exclude)) other[key] = (other[key] ?? 0) + 1;
      }
    }
    final otherCount = other.values.fold(0, (a, b) => a + b);
    final counts = otherCount * 2 < total ? all : other;
    if (counts.isEmpty) return null;
    final mode = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return Color(0xFF000000 | mode.key);
  }

  static bool _near(int r, int g, int b, Color c) {
    final dr = r - (c.r * 255).round(), dg = g - (c.g * 255).round();
    final db = b - (c.b * 255).round();
    return dr * dr + dg * dg + db * db < 40 * 40;
  }
}
