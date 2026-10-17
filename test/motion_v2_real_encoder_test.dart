// End-to-end Teach Nuvo on the REAL bundled MotionBERT encoder: pose frames ->
// adapter -> ONNX encoder -> learn from 3 demos -> match a same-movement
// sequence (accept) and a different movement (reject). Proves the whole Dart
// pipeline, not just the math with a mock encoder.
//
// Needs the ONNX Runtime shared library, so it is skipped unless it can be
// found. On Linux:
//   ORT=onnxruntime-linux-x64-1.15.1   (github.com/microsoft/onnxruntime v1.15.1)
//   LD_LIBRARY_PATH=$ORT/lib flutter test test/motion_v2_real_encoder_test.dart
// (macOS dev machines already have it through the plugin.)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/motion_v2_onnx_encoder.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/taught_motion_v2.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

List<NuvoPoseFrame> _frames(List<dynamic> wire) => [
  for (final f in wire)
    NuvoPoseFrame(
      points: {
        for (final e in (f['points'] as Map).entries)
          e.key as String: NuvoPosePoint(
            x: (e.value[0] as num).toDouble(),
            y: (e.value[1] as num).toDouble(),
            z: (e.value[2] as num).toDouble(),
            likelihood: (e.value[3] as num).toDouble(),
          ),
      },
      imageWidth: (f['w'] as num).toDouble(),
      imageHeight: (f['h'] as num).toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch((f['t'] as num).toInt()),
    ),
];

bool get _ortAvailable {
  if (!Platform.isLinux) return Platform.isMacOS;
  final paths = (Platform.environment['LD_LIBRARY_PATH'] ?? '').split(':');
  return paths.any(
    (p) => p.isNotEmpty && File('$p/libonnxruntime.so.1.15.1').existsSync(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'teach 3 demos on the real encoder; accept same movement, reject another',
    () async {
      final g =
          jsonDecode(
                File('test/fixtures/motion_v2_golden.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final demos = [for (final d in g['demos'] as List) _frames(d as List)];

      final sw = Stopwatch()..start();
      final encoder = await MotionV2OnnxEncoder.load();
      final loadMs = sw.elapsedMilliseconds;

      sw.reset();
      final spec = await TaughtMotionV2.learn(
        name: 'golden',
        demos: demos,
        encoder: encoder,
        encoderId: MotionV2OnnxEncoder.activeEncoderId,
      );
      final learnMs = sw.elapsedMilliseconds;

      final same = await spec.match(_frames(g['test'] as List), encoder);
      final other = await spec.match(_frames(g['other'] as List), encoder);
      // ignore: avoid_print
      print(
        'real encoder: load ${loadMs}ms learn ${learnMs}ms | '
        'same=${same.isSameFamily} (${same.decision}) '
        'other=${other.isSameFamily} (${other.decision})',
      );

      expect(same.isSameFamily, isTrue, reason: 'same movement must match');
      expect(
        other.isSameFamily,
        isFalse,
        reason: 'different movement must not',
      );
    },
    skip: _ortAvailable ? false : 'ONNX Runtime library not on LD_LIBRARY_PATH',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
