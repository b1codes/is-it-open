// App size check for CI (perf.yml) and `make app-size`.
//
//   dart run tool/app_size.dart check --analysis=<apk-code-size-analysis.json> [--max-growth=<percent>]
//       Measures the release builds, compares them with the baseline in app_size.json, prints a
//       table (also appended to $GITHUB_STEP_SUMMARY when set), writes the measurements to
//       build/app-size/measured.json, and exits 1 if the APK or the web build grew by more than
//       --max-growth percent (default 5).
//
// Build first, with the Flutter version pinned in perf.yml (sizes differ between versions):
//
//   flutter build apk --release --analyze-size --target-platform android-arm64
//   flutter build web --release
//
// `--analysis` is the JSON summary `--analyze-size` prints the path of. The baseline is only valid
// when CI measured it; `make app-size-pull` replaces it with a run's measurements.
import 'dart:convert';
import 'dart:io';

const _baselinePath = 'app_size.json';
const _measuredPath = 'build/app-size/measured.json';
const _apkPath = 'build/app/outputs/flutter-apk/app-release.apk';
const _webPath = 'build/web';

// What's measured, in table order. The gated ones fail the check when they grow too much; the
// others show where a change came from.
const _measurements = {
  'android_apk': 'Android APK (arm64)',
  'android_dart_code': '↳ Dart code (libapp.so)',
  'android_engine': '↳ Flutter engine (libflutter.so)',
  'android_assets': '↳ Assets (flutter_assets)',
  'android_dex': '↳ Java and Kotlin (classes.dex)',
  'web': 'Web build, without CanvasKit',
  'web_dart_code': '↳ Dart code (main.dart.js)',
  'web_assets': '↳ Assets',
  // The renderer; only a Flutter upgrade changes it, and it would hide growth in the rest.
  'web_canvaskit': 'CanvasKit (web renderer)',
};
const _gated = {'android_apk', 'web'};

void main(List<String> args) {
  if (args.isEmpty || args.first != 'check') _usage();
  final options = {
    for (final arg in args.skip(1))
      if (arg.startsWith('--') && arg.contains('='))
        arg.substring(2, arg.indexOf('=')): arg.substring(arg.indexOf('=') + 1),
  };
  final analysis = options['analysis'];
  if (analysis == null) _usage();
  _check(analysis, double.parse(options['max-growth'] ?? '5'));
}

Never _usage() {
  stderr.writeln(
    'usage: dart run tool/app_size.dart check --analysis=<apk-code-size-analysis.json> [--max-growth=<percent>]',
  );
  exit(64);
}

void _check(String analysisPath, double maxGrowth) {
  final measured = {..._measureApk(analysisPath), ..._measureWeb()};
  File(_measuredPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(measured)}\n',
    );

  final baselineFile = File(_baselinePath);
  final baseline = baselineFile.existsSync()
      ? (jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>)
            .cast<String, int>()
      : <String, int>{};

  final failures = <String>[];
  final shrunk = <String>[];
  final rows = <String>[];
  for (final MapEntry(key: key, value: label) in _measurements.entries) {
    final now = measured[key]!;
    final before = baseline[key];
    final gated = _gated.contains(key);
    final growth = before == null || before == 0
        ? null
        : (now - before) / before * 100;
    final over = gated && growth != null && growth > maxGrowth;
    if (over) failures.add(label);
    if (gated && growth != null && growth < -maxGrowth) shrunk.add(label);
    rows.add(
      '| $label | ${before == null ? '–' : _mb(before)} | ${_mb(now)} '
      '| ${growth == null ? 'new' : '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}%'} '
      '| ${gated ? (over ? '❌' : '✅') : ''} |',
    );
  }

  final report = StringBuffer()
    ..writeln('## App size')
    ..writeln()
    ..writeln(
      'Release builds against the baseline in `frontend/$_baselinePath`. '
      'The APK and the web build may grow by at most ${maxGrowth.toStringAsFixed(0)}%.',
    )
    ..writeln()
    ..writeln('| Build | Baseline | Now | Change | |')
    ..writeln('| --- | ---: | ---: | ---: | --- |')
    ..writeAll(rows.map((row) => '$row\n'))
    ..writeln();
  if (baseline.isEmpty) {
    report.writeln(
      'There is no baseline yet. Commit this run\'s measurements with `make app-size-pull`.',
    );
  } else if (failures.isNotEmpty) {
    report.writeln(
      '${failures.join(' and ')} grew by more than ${maxGrowth.toStringAsFixed(0)}%. If that\'s '
      'intended (e.g. a new feature or dependency), accept the new size with `make app-size-pull`.',
    );
  } else if (shrunk.isNotEmpty) {
    report.writeln(
      '${shrunk.join(' and ')} shrank by more than ${maxGrowth.toStringAsFixed(0)}%. Lock that '
      'in with `make app-size-pull`, so it can\'t quietly grow back.',
    );
  }

  stdout.write(report);
  final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null && summary.isNotEmpty) {
    File(summary).writeAsStringSync(report.toString(), mode: FileMode.append);
  }
  if (failures.isNotEmpty) exit(1);
}

Map<String, int> _measureApk(String analysisPath) {
  final apk = File(_apkPath);
  final analysisFile = File(analysisPath);
  if (!apk.existsSync() || !analysisFile.existsSync()) {
    stderr.writeln(
      'Build the APK first: flutter build apk --release --analyze-size --target-platform android-arm64',
    );
    exit(1);
  }
  final root =
      jsonDecode(analysisFile.readAsStringSync()) as Map<String, dynamic>;
  return {
    'android_apk': apk.lengthSync(),
    'android_dart_code': _node(root, ['lib', 'arm64-v8a', 'libapp.so']),
    'android_engine': _node(root, ['lib', 'arm64-v8a', 'libflutter.so']),
    'android_assets': _node(root, ['assets', 'flutter_assets']),
    'android_dex': _node(root, ['classes.dex']),
  };
}

/// The size of the node at `path` in an --analyze-size tree. Each name matches a node whose name
/// starts with it (the analysis labels some, e.g. "libapp.so (Dart AOT)").
int _node(Map<String, dynamic> root, List<String> path) {
  var node = root;
  for (final name in path) {
    final children = (node['children'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    node = children.firstWhere(
      (child) => (child['n'] as String).startsWith(name),
      orElse: () {
        stderr.writeln('The size analysis has no ${path.join('/')}');
        exit(1);
      },
    );
  }
  return node['value'] as int;
}

Map<String, int> _measureWeb() {
  final web = Directory(_webPath);
  if (!web.existsSync()) {
    stderr.writeln('Build the web app first: flutter build web --release');
    exit(1);
  }
  int size(FileSystemEntity entity) => entity is File
      ? entity.lengthSync()
      : entity is Directory
      ? entity
            .listSync(recursive: true)
            .whereType<File>()
            .fold(0, (sum, file) => sum + file.lengthSync())
      : 0;

  return {
    'web': size(web) - size(Directory('$_webPath/canvaskit')),
    'web_dart_code': size(File('$_webPath/main.dart.js')),
    'web_canvaskit': size(Directory('$_webPath/canvaskit')),
    'web_assets': size(Directory('$_webPath/assets')),
  };
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
