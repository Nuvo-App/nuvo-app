import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_models.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_native_runtime.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_verifier_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('wave proof frames through the real adapter', () async {
    final sess = jsonDecode(File(
      '/home/server1/.nuvo-sessions/ms_3cdb701fe9be4fff96ce671ddb58c81e.json',
    ).readAsStringSync());
    final spec = TaughtMotionV2Spec.fromJson(
      jsonDecode(File('/home/server1/.nuvo-sessions/race_1e49bec7_spec.json').readAsStringSync()),
    );
    final rt = MotionV2VerifierRuntime(spec: spec, target: 1);
    // wrap the engine's update to log every call — count what reaches the matcher
    rt.start();
    int repAtMs = -1;
    int pushed = 0;
    for (final f in sess['frames'] as List) {
      final m = f as Map<String, dynamic>;
      final pts = m['landmarks'] as Map? ?? const {};
      final frame = NuvoPoseFrame(
        points: {for (final e in pts.entries) e.key as String: NuvoPosePoint(
          x: (e.value['x'] as num).toDouble(), y: (e.value['y'] as num).toDouble(),
          z: (e.value['z'] as num?)?.toDouble() ?? 0,
          likelihood: (e.value['confidence'] as num?)?.toDouble() ?? 0)},
        imageWidth: 720, imageHeight: 1280,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['timestampMs'] as num).toInt()),
      );
      final u = rt.update(frame);
      if ((pushed++ % 4) == 3) {
        final dbg = u.debugValues;
        print('f=$pushed state=${u.validatorState} count=${u.count} matched=${dbg['matched']} votes=${dbg['votes']} buf=${dbg['bufferFrames']} ready=${dbg['engineReady']}');
      }
      if (u.customPoseUpdate?.frameAdvancedVerification == true && repAtMs < 0) {
        repAtMs = frame.createdAt.difference(
          DateTime.fromMillisecondsSinceEpoch((sess['frames'][0]['timestampMs'] as num).toInt()),
        ).inMilliseconds;
      }
    }
    await Future.delayed(const Duration(seconds: 15)); // let pump drain
    print('pumps seen: $pushed');
    final r = rt.customResult();
    print('ADAPTER: count=${r.count} status=${r.verificationStatus} repAt=${repAtMs}ms reason=${r.finalFailureReason}');
    rt.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
