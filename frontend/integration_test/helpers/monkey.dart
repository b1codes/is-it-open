import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seed for a monkey run: `--dart-define=SEED=...`. Each scenario mixes
/// in its own name (see [scenarioSeed]), so one can be replayed on its own.
const monkeySeed = int.fromEnvironment('SEED', defaultValue: 20261025);

/// Actions per scenario: `--dart-define=MONKEY_STEPS=...`.
const monkeySteps = int.fromEnvironment('MONKEY_STEPS', defaultValue: 150);

/// [monkeySeed] mixed with [scenario]'s name (FNV-1a, so it's the same on
/// every platform and Dart version, unlike `String.hashCode`).
int scenarioSeed(String scenario, [int seed = monkeySeed]) {
  var hash = 0x811c9dc5 ^ seed;
  for (final unit in scenario.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// What a [Monkey] can do. [Monkey.run] picks one per step, weighted by
/// [Monkey.weights].
enum MonkeyAction {
  /// A tap on something tappable, a little off its center (a fat finger).
  tap,

  /// A tap anywhere on screen.
  tapAnywhere,
  doubleTap,

  /// Three to six taps in quick succession on one spot.
  rapidTaps,
  longPress,
  drag,
  fling,

  /// Two fingers moving apart or together: a pinch or zoom.
  pinch,

  /// Two fingers tapping two things at once.
  twoFingerTap,

  /// Random text in a text field, sometimes submitted.
  type,

  /// The system back button.
  back,

  /// The app goes to the background and comes back.
  background,

  /// The screen turns between portrait and landscape.
  rotate,

  /// The system text size changes.
  textScale,

  /// The system switches between light and dark.
  brightness,

  /// Nothing, for a while: lets requests and animations finish, or not.
  wait,
}

/// Inputs no form should choke on: emoji (with skin tones, ZWJ sequences and
/// flags), combining marks, right-to-left and CJK scripts, zero-width and
/// bidi control characters, markup, SQL and format strings, escapes and
/// whitespace.
const monkeyStrings = [
  '',
  ' ',
  '   ',
  'a',
  'Coffee',
  '😀',
  '👍🏽',
  '👨\u200d👩\u200d👧\u200d👦',
  '🇨🇦',
  'e\u0301',
  'Z\u0364\u0354\u0367\u0311\u0353a\u0308\u0356\u032d\u0308\u0307lgo',
  '\u200b',
  '\u202eevil',
  'مرحبا بالعالم',
  'שלום',
  '東京タワー',
  'Ελληνικά',
  '<script>alert(1)</script>',
  "Robert'); DROP TABLE places;--",
  r'%s%n%x %d',
  r'${name}',
  r'\',
  '"\'`',
  '\n',
  '\t',
  'ﷺ',
  '-1',
  '99999999999999999999',
  'null',
];

/// A random string to type: one of [monkeyStrings], a few of them run
/// together, or something very long.
String randomMonkeyText(Random random) {
  switch (random.nextInt(4)) {
    case 0:
    case 1:
      return monkeyStrings[random.nextInt(monkeyStrings.length)];
    case 2:
      return [
        for (var i = random.nextInt(4) + 2; i > 0; i--)
          monkeyStrings[random.nextInt(monkeyStrings.length)],
      ].join();
    default:
      final word = monkeyStrings[random.nextInt(monkeyStrings.length)];
      return List.filled(
        random.nextInt(400) + 100,
        word.isEmpty ? 'x' : word,
      ).join(random.nextBool() ? ' ' : '');
  }
}

/// Flutter bugs the monkey runs into that the app can't fix or avoid: debug
/// assertions inside the framework. The monkey skips exactly these errors
/// (and logs each skip), so they don't fail every run. Remove an entry once
/// the Flutter version in .fvmrc fixes it.
final knownFlutterBugs =
    <({String issue, bool Function(FlutterErrorDetails) matches})>[
      (
        // A sheet released between snap sizes, then tapped.
        issue: 'https://github.com/b1codes/is-it-open/issues/61',
        matches: (details) =>
            '${details.exception}'.contains("'_hold == null'") &&
            '${details.stack}'.contains('ScrollableState._handleDrag'),
      ),
      (
        // A text field's toolbar showing while the field's own scrolling
        // changes size mid-layout (here, a long search query cleared).
        issue: 'https://github.com/b1codes/is-it-open/issues/61',
        matches: (details) =>
            '${details.stack}'.contains(
              'EditableTextState._handleContextMenuOnScroll',
            ) &&
            RegExp(
              r"'(selection\.isValid|sizeAccessAllowed)'",
            ).hasMatch('${details.exception}'),
      ),
      (
        // A SnackBar shown while a route is pushed or popped. Either check
        // in _HeroFlight.divert, depending on which way the flight turns.
        issue: 'https://github.com/b1codes/is-it-open/issues/61',
        matches: (details) => RegExp(
          r"'manifest\.(fromHero == newManifest\.toHero|toHero == newManifest\.fromHero)'",
        ).hasMatch('${details.exception}'),
      ),
    ];

/// A failure the monkey found: what was thrown, and the steps that led there.
class MonkeyFailure implements Exception {
  MonkeyFailure(this.step, this.error, this.log, this.replay);

  final int step;

  /// The first error, with the widget that threw and the stack when Flutter
  /// reported it.
  final String error;
  final List<String> log;

  /// How to run this sequence again.
  final String replay;

  @override
  String toString() {
    final tail = log.length > 25 ? log.sublist(log.length - 25) : log;
    return 'The monkey hit an exception at step $step:\n\n$error\n\n'
        'Last actions:\n${tail.join('\n')}\n\nReplay: $replay';
  }
}

/// Drives the app under [tester] with random input from a seeded generator,
/// and fails as soon as anything throws or overflows.
///
/// The same seed against the same app replays the same actions, so any
/// failure can be reproduced. Each action is passed to [onLog] as it happens,
/// so a run that hangs still leaves its log.
class Monkey {
  Monkey(
    this.tester, {
    required this.seed,
    required this.steps,
    required this.replay,
    this.onLog,
    Map<MonkeyAction, int>? weights,
    this.avoid = const [],
    this.ignore,
  }) : weights = weights ?? defaultWeights,
       _random = Random(seed);

  /// How often each action is picked, relative to the others.
  static const defaultWeights = {
    MonkeyAction.tap: 30,
    MonkeyAction.tapAnywhere: 6,
    MonkeyAction.doubleTap: 6,
    MonkeyAction.rapidTaps: 5,
    MonkeyAction.longPress: 3,
    MonkeyAction.drag: 8,
    MonkeyAction.fling: 4,
    MonkeyAction.pinch: 4,
    MonkeyAction.twoFingerTap: 3,
    MonkeyAction.type: 10,
    MonkeyAction.back: 5,
    MonkeyAction.background: 2,
    MonkeyAction.rotate: 2,
    MonkeyAction.textScale: 2,
    MonkeyAction.brightness: 1,
    MonkeyAction.wait: 5,
  };

  final WidgetTester tester;
  final int seed;
  final int steps;
  final String replay;
  final void Function(String line)? onLog;
  final Map<MonkeyAction, int> weights;

  /// Labels the monkey must not touch (case-insensitive substrings of a
  /// target's text or tooltip), e.g. "Logout" on a run against a real
  /// account. Taps anywhere on screen also stay clear of them.
  final List<String> avoid;

  /// Errors that aren't the app's fault, e.g. map tiles that can't load in
  /// a test without a network. They're dropped, so they don't fail the run.
  final bool Function(FlutterErrorDetails details)? ignore;

  final Random _random;
  final List<String> log = [];

  /// The text scales the system offers; 2× is the most the app supports
  /// (see "Accessibility" in TESTING.md).
  static const _textScales = [0.85, 1.0, 1.3, 2.0];

  Future<void> run() async {
    // The test binding keeps only an error's message for takeException; the
    // full report says which widget threw, and where.
    final report = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = (details) {
      if (ignore?.call(details) ?? false) return;
      for (final bug in knownFlutterBugs) {
        if (bug.matches(details)) {
          _record('  (skipped a known Flutter bug: ${bug.issue})');
          return;
        }
      }
      errors.add(details);
      report?.call(details);
    };
    try {
      _record('seed $seed, $steps steps');
      for (var step = 1; step <= steps; step++) {
        final action = _pick();
        if (_live) {
          // On a device a step can hang (a frame that never comes), and the
          // job would time out without saying where. Name the step first,
          // and give up on it after a while.
          onLog?.call('#$step ${action.name}…');
          await _step(step, action).timeout(
            _stepTimeout,
            onTimeout: () => _fail(
              step,
              'The ${action.name} action, or the pause after it, '
              "didn't finish in ${_stepTimeout.inSeconds} s: the app is stuck.",
            ),
          );
        } else {
          await _step(step, action);
        }
        final error = tester.takeException();
        if (error != null) {
          _fail(step, errors.isEmpty ? '$error' : '${errors.first}');
        }
        if (!_hasRoute()) {
          _fail(
            step,
            'The app popped its last route: the screen is blank, and the '
            "next rebuild fails Navigator's `_history.isNotEmpty` assertion.",
          );
        }
      }
    } finally {
      FlutterError.onError = report;
    }
  }

  /// A device test runs in real time, a widget test in fake time.
  bool get _live => tester.binding is LiveTestWidgetsFlutterBinding;

  static const _stepTimeout = Duration(seconds: 60);

  Future<void> _step(int step, MonkeyAction action) async {
    final description = await _perform(action);
    _record('#$step ${action.name}: $description');
    await _pause();
  }

  /// Throws a [MonkeyFailure], logging it first: on a device a stuck app can
  /// keep the test from ever reporting it.
  Never _fail(int step, String error) {
    final failure = MonkeyFailure(step, error, log, replay);
    onLog?.call('$failure');
    throw failure;
  }

  /// Whether the app's navigator still shows a route. Popping the only one
  /// (say, a close button tapped twice) leaves it empty.
  bool _hasRoute() {
    final root = find.byType(Navigator).first;
    return find
        .descendant(
          of: root,
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString().startsWith('_ModalScope'),
          ),
        )
        .evaluate()
        .isNotEmpty;
  }

  void _record(String line) {
    log.add(line);
    onLog?.call(line);
  }

  MonkeyAction _pick() {
    final total = weights.values.fold(0, (a, b) => a + b);
    var roll = _random.nextInt(total);
    for (final entry in weights.entries) {
      roll -= entry.value;
      if (roll < 0) return entry.key;
    }
    return weights.keys.last;
  }

  /// Sometimes a frame, sometimes long enough for a request to finish, so
  /// the next action lands mid-transition as often as on a settled screen.
  Future<void> _pause() async {
    await tester.pump(Duration(milliseconds: _random.nextInt(600)));
    await tester.pump();
  }

  Size get _screen => tester.view.physicalSize / tester.view.devicePixelRatio;

  Future<String> _perform(MonkeyAction action) async {
    switch (action) {
      case MonkeyAction.tap:
        final target = _target();
        if (target == null) return _tapAt(_anywhere());
        final at = _fatFinger(target.rect);
        if (_avoided(at)) return 'skipped (near something off-limits)';
        await tester.tapAt(at);
        return '${target.label} at ${_fmt(at)}';
      case MonkeyAction.tapAnywhere:
        return _tapAt(_anywhere());
      case MonkeyAction.doubleTap:
        final at = _targetOrAnywhere();
        if (at == null) return 'skipped';
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(at);
        return _fmt(at);
      case MonkeyAction.rapidTaps:
        final at = _targetOrAnywhere();
        if (at == null) return 'skipped';
        final count = _random.nextInt(4) + 3;
        for (var i = 0; i < count; i++) {
          await tester.tapAt(at);
          await tester.pump(Duration(milliseconds: _random.nextInt(40) + 10));
        }
        return '$count at ${_fmt(at)}';
      case MonkeyAction.longPress:
        final at = _targetOrAnywhere();
        if (at == null) return 'skipped';
        await tester.longPressAt(at);
        return _fmt(at);
      case MonkeyAction.drag:
      case MonkeyAction.fling:
        final from = _anywhere();
        if (_avoided(from)) return 'skipped (starts on something off-limits)';
        final by = Offset(
          (_random.nextDouble() - 0.5) * _screen.width,
          (_random.nextDouble() - 0.5) * _screen.height,
        );
        if (action == MonkeyAction.fling) {
          await tester.flingFrom(from, by, _random.nextDouble() * 4000 + 500);
        } else {
          await tester.dragFrom(from, by);
        }
        return 'from ${_fmt(from)} by ${_fmt(by)}';
      case MonkeyAction.pinch:
        return _pinch();
      case MonkeyAction.twoFingerTap:
        final a = _targetOrAnywhere();
        final b = _targetOrAnywhere();
        if (a == null || b == null) return 'skipped';
        final first = await tester.startGesture(a);
        final second = await tester.startGesture(b);
        await tester.pump(const Duration(milliseconds: 30));
        await first.up();
        await second.up();
        return '${_fmt(a)} and ${_fmt(b)}';
      case MonkeyAction.type:
        return _type();
      case MonkeyAction.back:
        // On the first route the system would close the app, which a test
        // on a device can't come back from.
        final root = tester.state<NavigatorState>(find.byType(Navigator).first);
        if (!root.canPop()) return 'skipped (nothing to go back to)';
        await tester.binding.handlePopRoute();
        return 'popped';
      case MonkeyAction.background:
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        final away = Duration(milliseconds: _random.nextInt(2000));
        // In the background the app draws no frames, so on a device a pump
        // would wait for one forever; just let the time pass.
        await (_live ? tester.binding.delayed(away) : tester.pump(away));
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        return 'and back';
      case MonkeyAction.rotate:
        final size = tester.view.physicalSize;
        tester.view.physicalSize = Size(size.height, size.width);
        return 'to ${_fmt(Offset(_screen.width, _screen.height))}';
      case MonkeyAction.textScale:
        final scale = _textScales[_random.nextInt(_textScales.length)];
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        return '$scale×';
      case MonkeyAction.brightness:
        final dark =
            tester.platformDispatcher.platformBrightness == Brightness.light;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        return dark ? 'dark' : 'light';
      case MonkeyAction.wait:
        final ms = _random.nextInt(3000);
        await tester.pump(Duration(milliseconds: ms));
        return '${ms}ms';
    }
  }

  Future<String> _tapAt(Offset at) async {
    if (_avoided(at)) return 'skipped (on something off-limits)';
    await tester.tapAt(at);
    return _fmt(at);
  }

  Future<String> _pinch() async {
    final center = _anywhere();
    final spread = _random.nextDouble() * 80 + 20;
    final apart = _random.nextBool();
    final angle = _random.nextDouble() * pi;
    final axis = Offset(cos(angle), sin(angle)) * spread;
    if (_avoided(center - axis) || _avoided(center + axis)) {
      return 'skipped (on something off-limits)';
    }
    final first = await tester.startGesture(center - axis);
    final second = await tester.startGesture(center + axis);
    final step = axis * (apart ? 0.15 : -0.1);
    for (var i = 0; i < 6; i++) {
      await first.moveBy(-step);
      await second.moveBy(step);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    return '${apart ? 'out' : 'in'} at ${_fmt(center)}';
  }

  Future<String> _type() async {
    final fields = _visible(
      find.byType(EditableText).evaluate(),
    ).where((t) => !_isAvoided(t.label)).toList();
    if (fields.isEmpty) return 'skipped (no text field)';
    final field = fields[_random.nextInt(fields.length)];
    final finder = find.byElementPredicate((e) => e == field.element);
    var text = randomMonkeyText(_random);
    if (tester.widget<EditableText>(finder).obscureText) {
      // A password field breaks on an emoji typed over one character
      // (a Flutter bug: https://github.com/b1codes/is-it-open/issues/60).
      text = String.fromCharCodes(text.runes.where((r) => r <= 0xFFFF));
    }
    await tester.enterText(finder, text);
    var submitted = '';
    if (_random.nextInt(3) == 0) {
      final action =
          (tester.widget<EditableText>(finder).textInputAction ??
          TextInputAction.done);
      await tester.testTextInput.receiveAction(action);
      submitted = ', then ${action.name}';
    }
    final shown = text.length > 40 ? '${text.substring(0, 40)}…' : text;
    return '${text.length} chars into ${field.label}$submitted: '
        '${_quote(shown)}';
  }

  /// Something on screen that reacts to touch, picked at random.
  _Target? _target() {
    final candidates = _visible(
      find
          .byWidgetPredicate(
            (w) =>
                w is InkResponse ||
                w is GestureDetector ||
                w is EditableText ||
                w is Checkbox ||
                w is Switch ||
                w is Radio ||
                w is Slider,
          )
          .evaluate(),
    ).where((t) => !_isAvoided(t.label)).toList();
    if (candidates.isEmpty) return null;
    return candidates[_random.nextInt(candidates.length)];
  }

  Offset? _targetOrAnywhere() {
    final target = _random.nextInt(4) == 0 ? null : _target();
    final at = target == null ? _anywhere() : _fatFinger(target.rect);
    return _avoided(at) ? null : at;
  }

  Offset _anywhere() => Offset(
    _random.nextDouble() * _screen.width,
    _random.nextDouble() * _screen.height,
  );

  /// A point near the middle of [rect], up to a fingertip outside it.
  Offset _fatFinger(Rect rect) {
    final reach = rect.inflate(6);
    final at = Offset(
      reach.left + reach.width * (0.2 + _random.nextDouble() * 0.6),
      reach.top + reach.height * (0.2 + _random.nextDouble() * 0.6),
    );
    return Offset(
      at.dx.clamp(0, _screen.width - 1),
      at.dy.clamp(0, _screen.height - 1),
    );
  }

  /// [elements] that are on screen and would receive a touch at their
  /// center (not covered by a dialog, a sheet, or another route).
  List<_Target> _visible(Iterable<Element> elements) {
    final screen = Offset.zero & _screen;
    final targets = <_Target>[];
    for (final element in elements) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      if (box.size.isEmpty) continue;
      final rect = (box.localToGlobal(Offset.zero) & box.size).intersect(
        screen,
      );
      if (rect.width < 1 || rect.height < 1) continue;
      final result = HitTestResult();
      tester.binding.hitTestInView(result, rect.center, tester.view.viewId);
      if (!result.path.any((entry) => entry.target == box)) continue;
      targets.add(_Target(element, rect, _labelOf(element)));
    }
    return targets;
  }

  bool _isAvoided(String label) {
    final lower = label.toLowerCase();
    return avoid.any((a) => lower.contains(a.toLowerCase()));
  }

  /// Whether [at] is on (or a fingertip from) something in [avoid].
  bool _avoided(Offset at) {
    if (avoid.isEmpty) return false;
    final labelled = find.byWidgetPredicate(
      (w) => w is InkResponse || w is Tooltip,
    );
    for (final target in _visible(labelled.evaluate())) {
      if (_isAvoided(target.label) && target.rect.inflate(12).contains(at)) {
        return true;
      }
    }
    return false;
  }

  /// The first text or tooltip inside [element] (else its first icon), to
  /// name it in the log.
  static String _labelOf(Element element) {
    String? text;
    String? icon;
    void visit(Element e) {
      if (text != null) return;
      final widget = e.widget;
      if (widget is Text) {
        text = widget.data ?? widget.textSpan?.toPlainText();
      } else if (widget is Tooltip) {
        text = widget.message;
      } else if (widget is EditableText) {
        text = widget.controller.text.isEmpty ? '(empty field)' : '(field)';
      } else if (widget is Icon && widget.icon != null) {
        icon ??= 'icon U+${widget.icon!.codePoint.toRadixString(16)}';
      }
      e.visitChildren(visit);
    }

    visit(element);
    text ??= icon;
    final name = element.widget.runtimeType.toString();
    if (text == null) return name;
    final label = text!.length > 30 ? '${text!.substring(0, 30)}…' : text!;
    return '$name ${_quote(label)}';
  }

  static String _quote(String s) =>
      '"${s.replaceAll('\n', r'\n').replaceAll('\t', r'\t')}"';

  static String _fmt(Offset o) =>
      '(${o.dx.toStringAsFixed(0)}, ${o.dy.toStringAsFixed(0)})';
}

class _Target {
  _Target(this.element, this.rect, this.label);

  final Element element;
  final Rect rect;
  final String label;
}
