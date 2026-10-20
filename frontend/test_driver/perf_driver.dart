import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver.dart';

// The host side of integration_test/perf_test.dart. Summarizes each traced
// interaction's frames, writes the timelines to build/ (open one in
// Perfetto), prints a table (also appended to $GITHUB_STEP_SUMMARY when set),
// and fails if an interaction is over its budgets. See "Performance" in
// TESTING.md.

/// Per interaction:
/// - `jank`: the largest share of frames that may take over 16 ms to build,
///   i.e. drop below 60 fps on the UI thread. That's the app's own work, and
///   janks on any device.
/// - `rasterP90`: the 90th percentile time to rasterize a frame, in ms. CI
///   rasterizes in software, far slower than a phone's GPU (the glass blurs
///   most of all), so this is only comparable between CI runs: the budget is
///   about twice what a CI runner measured (23, 68 and 139 ms with Flutter
///   3.47.7).
const _budgets = {
  'map_pan_zoom': (jank: 0.10, rasterP90: 50.0),
  'calendar_scroll': (jank: 0.10, rasterP90: 140.0),
  'search_typing': (jank: 0.10, rasterP90: 280.0),
};

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final failures = <String>[];
    final rows = <String>[];
    for (final MapEntry(key: name, value: budget) in _budgets.entries) {
      final timeline = data?[name];
      if (timeline == null) {
        failures.add('$name: no timeline (did its test fail?)');
        continue;
      }
      final summary = TimelineSummary.summarize(
        Timeline.fromJson(timeline as Map<String, dynamic>),
      );
      await summary.writeTimelineToFile(name, pretty: true);

      final json = summary.summaryJson;
      final frames = json['frame_count'] as int;
      final jank = frames == 0
          ? 0.0
          : (json['missed_frame_build_budget_count'] as num) / frames;
      final rasterP90 =
          json['90th_percentile_frame_rasterizer_time_millis'] as num;
      final ok = jank <= budget.jank && rasterP90 <= budget.rasterP90;
      if (!ok) failures.add(name);
      rows.add(
        '| $name | $frames '
        '| ${_ms(json['90th_percentile_frame_build_time_millis'])} '
        '| ${_percent(jank)} (≤ ${_percent(budget.jank)}) '
        '| ${_ms(rasterP90)} (≤ ${_ms(budget.rasterP90)}) '
        '| ${ok ? '✅' : '❌'} |',
      );
    }

    final report = StringBuffer()
      ..writeln('## Frame timing')
      ..writeln()
      ..writeln(
        'Frames that took over 16 ms to build, and raster times, per '
        'interaction. CI rasterizes in software, so raster times are only '
        'comparable between CI runs. The timelines are in the `frame-timing` '
        'artifact.',
      )
      ..writeln()
      ..writeln(
        '| Interaction | Frames | Build p90 | Build over 16 ms | Raster p90 | |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | --- |')
      ..writeAll(rows.map((row) => '$row\n'));
    if (failures.isNotEmpty) {
      report
        ..writeln()
        ..writeln('Over budget: ${failures.join(', ')}.');
    }
    stdout.write(report);
    final summaryFile = Platform.environment['GITHUB_STEP_SUMMARY'];
    if (summaryFile != null && summaryFile.isNotEmpty) {
      File(summaryFile).writeAsStringSync('$report', mode: FileMode.append);
    }
    if (failures.isNotEmpty) exit(1);
  },
);

String _percent(double share) => '${(share * 100).toStringAsFixed(1)}%';

String _ms(Object? value) =>
    value is num ? '${value.toStringAsFixed(1)} ms' : '–';
