// Real-data scorecard: replays every real-video pose fixture through the
// PRODUCTION validator for its motion and reports count vs expected. Not a
// pass/fail gate on accuracy (several motions are known-weak) — it prints the
// table so tuning work has a number to move, and fails only if a fixture can't
// be loaded. Run: flutter test test/motion_real_scorecard_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'motion_qa/replay_fixture.dart';

const _alias = {
  'normal_squats': 'squats',
  'jump_squats': 'jump_squats',
  'lunge_jumps': 'lunge_jumps',
};

void main() {
  test('real-video scorecard', () {
    final dir = Directory('test/motion_qa/fixtures/real');
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.json') && !f.path.endsWith('import_log.json'),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);

    final rows = <String>[];
    final byMotion = <String, List<(int, int)>>{};
    for (final file in files) {
      final fixture = ReplayFixture.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
      final id = _alias[fixture.movement] ?? fixture.movement;
      final activity = AiMotionActivity.fromBackendValue(id);
      if (activity == AiMotionActivity.remote) {
        rows.add('| ${fixture.id} | ${fixture.movement} | - | - | no validator |');
        continue;
      }
      final v = createMotionValidator(activity, 999)..start();
      var ms = 0;
      for (final f in fixture.frames) {
        final frame = f.toPoseFrame();
        v.update(
          NuvoPoseFrame(
            points: frame.points,
            imageWidth: frame.imageWidth,
            imageHeight: frame.imageHeight,
            createdAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
          ),
        );
        ms += 33;
      }
      final expected = fixture.expected.reps;
      final got = v.currentValue;
      byMotion.putIfAbsent(id, () => []).add((expected, got));
      final tag = got == expected
          ? 'exact'
          : got < expected
          ? 'UNDER'
          : 'OVER';
      rows.add('| ${fixture.id} | $id | $expected | $got | $tag |');
    }

    final out = StringBuffer()
      ..writeln('| fixture | motion | expected | counted | result |')
      ..writeln('|---|---|---|---|---|')
      ..writeAll(rows.map((r) => '$r\n'))
      ..writeln()
      ..writeln('| motion | clips | exact | rep recall | over-count |')
      ..writeln('|---|---|---|---|---|');
    for (final e in byMotion.entries) {
      final exact = e.value.where((p) => p.$1 == p.$2).length;
      final exp = e.value.fold<int>(0, (s, p) => s + p.$1);
      final hit = e.value.fold<int>(0, (s, p) => s + (p.$2 < p.$1 ? p.$2 : p.$1));
      final over = e.value.fold<int>(0, (s, p) => s + (p.$2 > p.$1 ? p.$2 - p.$1 : 0));
      out.writeln(
        '| ${e.key} | ${e.value.length} | $exact/${e.value.length} | '
        '${exp == 0 ? '-' : '${(100 * hit / exp).round()}%'} | $over |',
      );
    }
    stdout.write(out);
  });
}
