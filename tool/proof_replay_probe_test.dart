// Replays a pulled motion-session artifact (proof frames, `landmarks` shape)
// through the pulled teach artifact's V2 spec — the same frames the phone
// counted on, through the same matcher. Prints per-eval score/progress so the
// rep gate can be calibrated against real data.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_models.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_native_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

List<NuvoPoseFrame> _frames(Map<String, dynamic> artifact) {
  final out = <NuvoPoseFrame>[];
  for (final f in artifact['frames'] as List) {
    final m = f as Map<String, dynamic>;
    final pts = m['landmarks'] as Map? ?? const {};
    out.add(
      NuvoPoseFrame(
        points: {
          for (final e in pts.entries)
            e.key as String: NuvoPosePoint(
              x: (e.value['x'] as num).toDouble(),
              y: (e.value['y'] as num).toDouble(),
              z: (e.value['z'] as num?)?.toDouble() ?? 0,
              likelihood: (e.value['confidence'] as num?)?.toDouble() ?? 0,
            ),
        },
        imageWidth: 720,
        imageHeight: 1280,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (m['timestampMs'] as num).toInt(),
        ),
      ),
    );
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('proof replay through the real learned spec', () async {
    final sess = jsonDecode(
      File('/home/server1/.nuvo-sessions/ms_3cdb701fe9be4fff96ce671ddb58c81e.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final teach = jsonDecode(
      utf8.decode(
        gzip.decode(
          File(
            '/home/server1/.nuvo-sessions/MV2-20261015-92AFAC.json.gz',
          ).readAsBytesSync(),
        ),
      ),
    ) as Map<String, dynamic>;
    final spec = TaughtMotionV2Spec.fromJson(
      teach['spec'] as Map<String, dynamic>,
    );
    final frames = _frames(sess);
    print('SPEC: ${spec.movementName} refs=${(spec.json['references'] as List).length}');
    print('FRAMES: ${frames.length}');

    // The demos that produced this spec must now be rejected by the motion
    // floor — this spec should never have existed.
    final demos = <List<NuvoPoseFrame>>[
      for (final t in teach['teaching'] as List)
        [
          for (final f in (t as Map)['frames'] as List)
            () {
              final m = f as Map<String, dynamic>;
              final pts = (m['smoothed'] as Map?) ?? (m['raw'] as Map?) ?? const {};
              return NuvoPoseFrame(
                points: {
                  for (final e in pts.entries)
                    e.key as String: NuvoPosePoint(
                      x: (e.value[0] as num).toDouble(),
                      y: (e.value[1] as num).toDouble(),
                      z: (e.value[2] as num?)?.toDouble() ?? 0,
                      likelihood: (e.value[3] as num?)?.toDouble() ?? 0,
                    ),
                },
                imageWidth: 720,
                imageHeight: 1280,
                createdAt: DateTime.fromMillisecondsSinceEpoch(
                  1792010462000 + (m['t'] as num).toInt(),
                ),
              );
            }(),
        ],
    ];
    final learner = MotionV2NativeRuntime();
    try {
      await learner.learn(movementName: 'Pull Ups', demos: demos);
      print('LEARN: unexpectedly passed');
    } on MotionV2LearnException catch (e) {
      print('LEARN rejected: ${e.message}');
    }

    final rt = MotionV2NativeRuntime();
    await rt.load(spec);
    var evalNo = 0;
    for (var i = 0; i < frames.length; i += 4) {
      final batch = frames.sublist(i, (i + 4).clamp(0, frames.length));
      final r = await rt.update(batch);
      if (r.bufferFrames < 8) continue;
      evalNo++;
      final t = batch.last.createdAt.millisecondsSinceEpoch -
          frames.first.createdAt.millisecondsSinceEpoch;
      print(
        'eval$evalNo t=${t}ms count=${r.count} newRep=${r.newRep} '
        'state=${r.state.name} matched=${r.matched} '
        'conf=${r.confidence.toStringAsFixed(3)} '
        'prog=${r.motionProgress.toStringAsFixed(3)} '
        'votes=${r.votes} traj=${r.trajSim?.toStringAsFixed(3)} '
        'proto=${r.protoMargin?.toStringAsFixed(3)} '
        'sep=${r.separation?.toStringAsFixed(3)} '
        'dec=${r.decision} ready=${r.poseReadiness} '
        'attempt=${r.attempt.outcome.name} "${r.attempt.userFeedback}"',
      );
    }
    await rt.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
