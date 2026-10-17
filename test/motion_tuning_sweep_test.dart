// Threshold sweep against the real-video pose fixtures.
//
// For each over-the-air motion that has real clips, sweeps the spec's key
// thresholds and prints the baseline score next to the best candidates, so a
// Cloudflare release can be justified by numbers. Score = sum over clips of
// |counted - expected| (lower is better). Among equal scores the candidate
// closest to today's values wins (smallest change = least risk).
//
//   flutter test test/motion_tuning_sweep_test.dart
//   WRITE_CANDIDATES=1 flutter test test/motion_tuning_sweep_test.dart
//     -> also writes server/worker/motion_specs/candidates/<id>.json
//
// Candidates live in their own folder so the parity tests (which pin the
// shipped specs to the compiled validators) are untouched.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'motion_qa/replay_fixture.dart';

typedef _Path = List<Object>;

class _Knob {
  _Knob(this.name, this.paths, this.values);
  final String name;
  final List<_Path> paths; // tied: all set to the same value
  final List<double> values;
}

List<double> _r(double a, double b, double step) => [
  for (var v = a; v <= b + 1e-9; v += step) double.parse(v.toStringAsFixed(3)),
];

final _motions = <String, List<_Knob>>{
  'squats': [
    _Knob('start>', [
      ['repTree', 'start', 'gt'],
    ], _r(0.40, 0.80, 0.05)),
    _Knob('active<', [
      ['repTree', 'active', 'lt'],
    ], _r(0.30, 0.60, 0.05)),
  ],
  // Alternative squat definition built on knee angle instead of hip height:
  // same engine, different signal. Swept against the same clips as 'squats'.
  'squats_knee': [
    _Knob('standKnee>', [
      ['repTree', 'start', 'all', 0, 'gt'],
      ['repTree', 'start', 'all', 1, 'gt'],
    ], _r(135, 170, 5)),
    _Knob('squatKnee<', [
      ['repTree', 'active', 'any', 0, 'lt'],
      ['repTree', 'active', 'any', 1, 'lt'],
    ], _r(85, 140, 5)),
  ],
  'deep_squats': [
    _Knob('start>', [
      ['repTree', 'start', 'gt'],
    ], _r(0.40, 0.80, 0.05)),
    _Knob('active<', [
      ['repTree', 'active', 'lt'],
    ], _r(0.05, 0.45, 0.05)),
  ],
  'jumping_jacks': [
    _Knob('feetClosed<', [
      ['repTree', 'start', 'all', 1, 'lt'],
    ], _r(1.0, 1.5, 0.05)),
    _Knob('feetWide>', [
      ['repTree', 'active', 'all', 1, 'gt'],
    ], _r(1.1, 1.7, 0.05)),
  ],
  'lunges': [
    _Knob('standKnee>', [
      ['repTree', 'start', 'all', 0, 'gt'],
      ['repTree', 'start', 'all', 1, 'gt'],
    ], _r(135, 165, 5)),
    _Knob('kneeSep>', [
      ['repTree', 'active', 'all', 0, 'gt'],
    ], _r(0.2, 0.8, 0.1)),
    _Knob('bentKnee<', [
      ['repTree', 'active', 'all', 1, 'any', 0, 'lt'],
      ['repTree', 'active', 'all', 1, 'any', 1, 'lt'],
    ], _r(100, 140, 5)),
  ],
  'squat_jacks': [
    _Knob('standing>', [
      ['repTree', 'start', 'all', 2, 'gt'],
    ], _r(0.40, 0.80, 0.05)),
    _Knob('squatting<', [
      ['repTree', 'active', 'all', 2, 'lt'],
    ], _r(0.40, 0.75, 0.05)),
    _Knob('feetWide>', [
      ['repTree', 'active', 'all', 1, 'gt'],
    ], _r(1.1, 1.6, 0.1)),
  ],
  'jump_squats': [
    _Knob('standing', [
      ['params', 'standingRatio'],
    ], _r(0.40, 0.90, 0.05)),
    _Knob('squat', [
      ['params', 'squatRatio'],
    ], _r(0.40, 0.85, 0.05)),
    _Knob('flight', [
      ['params', 'flightThresholdRatio'],
    ], _r(0.06, 0.26, 0.04)),
  ],
  'lunge_jumps': [
    _Knob('lungeKnee<', [
      ['params', 'lungeKneeAngle'],
    ], _r(100, 145, 5)),
    _Knob('trailKnee>', [
      ['params', 'trailingKneeAngle'],
    ], _r(135, 170, 5)),
    _Knob('standing', [
      ['params', 'standingRatio'],
    ], _r(0.5, 0.95, 0.05)),
  ],
};

const _movementAlias = {'normal_squats': 'squats'};

dynamic _deepCopy(dynamic v) => jsonDecode(jsonEncode(v));

void _set(Map<String, dynamic> spec, _Path path, double value) {
  dynamic node = spec;
  for (var i = 0; i < path.length - 1; i++) {
    final k = path[i];
    node = k is int ? (node as List)[k] : (node as Map)[k];
  }
  final last = path.last;
  if (last is int) {
    (node as List)[last] = value;
  } else {
    (node as Map)[last] = value;
  }
}

class _Clip {
  _Clip(this.id, this.expected, this.frames);
  final String id;
  final int expected;
  final List<NuvoPoseFrame> frames;
}

int _count(Map<String, dynamic> spec, List<NuvoPoseFrame> frames) {
  final rt = createRemoteVerifierRuntime(
    spec: RemoteVerifierSpec.fromJson(spec),
    target: 100000,
  );
  var n = 0;
  for (final f in frames) {
    n = rt.update(f).count;
  }
  return n;
}

void main() {
  test('threshold sweep on real clips', () {
    final clips = <String, List<_Clip>>{};
    for (final f in Directory(
      'test/motion_qa/fixtures/real',
    ).listSync().whereType<File>()) {
      if (!f.path.endsWith('.json') || f.path.endsWith('import_log.json')) {
        continue;
      }
      final fx = ReplayFixture.fromJson(
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      );
      final id = _movementAlias[fx.movement] ?? fx.movement;
      if (!_motions.containsKey(id)) continue;
      var ms = 0;
      final frames = [
        for (final rf in fx.frames)
          () {
            final p = rf.toPoseFrame();
            final out = NuvoPoseFrame(
              points: p.points,
              imageWidth: p.imageWidth,
              imageHeight: p.imageHeight,
              createdAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
            );
            ms += 33;
            return out;
          }(),
      ];
      clips
          .putIfAbsent(id, () => [])
          .add(_Clip(fx.id, fx.expected.reps, frames));
    }
    clips['squats_knee'] = clips['squats'] ?? [];

    final write = Platform.environment['WRITE_CANDIDATES'] == '1';
    final out = StringBuffer();
    for (final entry in _motions.entries) {
      final id = entry.key;
      final knobs = entry.value;
      final data = clips[id];
      if (data == null || data.isEmpty) continue;
      final base =
          jsonDecode(
                File(
                  'server/worker/motion_specs/${id == 'squats_knee' ? 'squats' : id}.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      if (id == 'squats_knee') {
        base['repTree'] = {
          'start': {
            'all': [
              {'signal': 'leftKneeAngle', 'gt': 155},
              {'signal': 'rightKneeAngle', 'gt': 155},
            ],
          },
          'active': {
            'any': [
              {'signal': 'leftKneeAngle', 'lt': 120},
              {'signal': 'rightKneeAngle', 'lt': 120},
            ],
          },
        };
      }

      int score(Map<String, dynamic> spec) {
        var s = 0;
        for (final c in data) {
          s += (_count(spec, c.frames) - c.expected).abs();
        }
        return s;
      }

      final baseline = score(base);
      final totalExpected = data.fold<int>(0, (a, c) => a + c.expected);

      // Enumerate the grid.
      var best = baseline;
      List<double>? bestVals;
      var bestDist = 0.0;
      List<double> current(Map<String, dynamic> spec) => [
        for (final k in knobs)
          () {
            dynamic node = spec;
            for (final key in k.paths.first) {
              node = key is int ? (node as List)[key] : (node as Map)[key];
            }
            return (node as num).toDouble();
          }(),
      ];
      final baseVals = current(base);
      void walk(int i, List<double> vals) {
        if (i == knobs.length) {
          final spec = _deepCopy(base) as Map<String, dynamic>;
          for (var j = 0; j < knobs.length; j++) {
            for (final p in knobs[j].paths) {
              _set(spec, p, vals[j]);
            }
          }
          final s = score(spec);
          var dist = 0.0;
          for (var j = 0; j < vals.length; j++) {
            final span = knobs[j].values.last - knobs[j].values.first;
            dist += ((vals[j] - baseVals[j]).abs() / (span == 0 ? 1 : span));
          }
          if (s < best || (s == best && bestVals != null && dist < bestDist)) {
            best = s;
            bestVals = List.of(vals);
            bestDist = dist;
          }
          return;
        }
        for (final v in knobs[i].values) {
          walk(i + 1, [...vals, v]);
        }
      }

      walk(0, []);
      final names = knobs.map((k) => k.name).toList();
      out.writeln(
        '## $id  (${data.length} clips, $totalExpected expected reps)',
      );
      out.writeln('baseline  score $baseline   ${_fmt(names, baseVals)}');
      if (bestVals != null && best < baseline) {
        out.writeln('best      score $best   ${_fmt(names, bestVals!)}');
        // per-clip breakdown for the best candidate
        final spec = _deepCopy(base) as Map<String, dynamic>;
        for (var j = 0; j < knobs.length; j++) {
          for (final p in knobs[j].paths) {
            _set(spec, p, bestVals![j]);
          }
        }
        for (final c in data) {
          out.writeln(
            '   ${c.id.padRight(22)} expected ${c.expected}  baseline ${_count(base, c.frames)}  best ${_count(spec, c.frames)}',
          );
        }
        if (write) {
          final dir = Directory('server/worker/motion_specs/candidates')
            ..createSync(recursive: true);
          spec['releaseId'] =
              '${id == 'squats_knee' ? 'squats' : id}-sweep-2026.10.1';
          File('${dir.path}/$id.json').writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert(spec)}\n',
          );
        }
      } else {
        out.writeln('best      no combination beat the baseline');
      }
      out.writeln();
    }
    stdout.write(out);
  });
}

String _fmt(List<String> names, List<double> vals) => [
  for (var i = 0; i < names.length; i++) '${names[i]} ${vals[i]}',
].join('  ');
