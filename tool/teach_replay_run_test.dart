// Entry point for tool/teach-replay.sh — `flutter test` is the runner that can
// load the app's Dart code (matchers + the ONNX encoder live behind
// Flutter-only imports like rootBundle).
//
// TEACH_REPLAY_SELFTEST=1 first builds a real artifact: a genuine V1 spec
// learned from three fixture demos plus a live-test frame stream, written as
// .json.gz — so the whole replay path can be validated without a phone.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_flow.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/ai/motion_v2/diagnostics/motion_diagnostic_session.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_native_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import '../test/fixtures/pose_fixtures.dart';
import 'teach_replay.dart' as replay;

bool get _ortAvailable {
  if (!Platform.isLinux) return Platform.isMacOS;
  final paths = (Platform.environment['LD_LIBRARY_PATH'] ?? '').split(':');
  return paths.any(
    (p) => p.isNotEmpty && File('$p/libonnxruntime.so.1.15.1').existsSync(),
  );
}

Future<Map<String, dynamic>> _selfTestArtifact() async {
  var now = DateTime.utc(2026, 10, 14);

  NuvoPoseFrame frame(int ms, NuvoPoseFrame base) => NuvoPoseFrame(
    points: base.points,
    imageWidth: base.imageWidth,
    imageHeight: base.imageHeight,
    createdAt: now.add(Duration(milliseconds: ms)),
  );

  // 4+ still frames up front so the flow's stable-pose capture locks the
  // neutral start; mid-demo the movement; ends back at neutral so the next
  // rep can re-arm — the same shape a real recording has.
  List<NuvoPoseFrame> demo([int t0 = 0]) => [
    for (var i = 0; i < 10; i++)
      frame(
        t0 + i * 120,
        switch (i) {
          >= 4 && < 8 => armsOverheadPose(),
          _ => neutralStandingPose(),
        },
      ),
  ];

  // A real V1 spec through the same builder the teach flow uses.
  final capture = SingleSessionTeachingCapture(
    now: () => now,
    buildDelay: Duration.zero,
  );
  capture.setMovementName('Side reach');
  final n = const PoseNormalizer();
  for (var r = 0; r < 3; r++) {
    capture.startRecordingExample();
    final raw = demo();
    for (var i = 0; i < raw.length; i++) {
      capture.addFrame(n.normalize(raw[i]), raw[i].createdAt);
    }
    capture.stopRecordingExampleAt(raw.last.createdAt);
  }
  capture.buildWhenReady();
  final spec = capture.verifierSpec!;

  Map<String, dynamic> diagFrames(List<NuvoPoseFrame> frames, int t0) => {
    'frames': [
      for (final f in frames)
        MotionDiagFrame.fromFrames(
          tMs: f.createdAt.difference(now).inMilliseconds - t0,
          raw: f,
          smoothed: f,
        ).toJson(),
    ],
  };

  final demos = [
    for (var i = 0; i < 3; i++)
      MotionDiagDemo(
        index: i + 1,
        startMs: i * 3000,
        endMs: i * 3000 + 960,
        rawFrameCount: 8,
        trimmedFrameCount: 8,
        estFps: 8.3,
        frames: [
          for (final f in demo())
            MotionDiagFrame.fromFrames(
              tMs: f.createdAt.difference(now).inMilliseconds,
              raw: f,
              smoothed: f,
            ),
        ],
      ).toJson(),
  ];

  // Live test = the same movement five times over — V1 replay should count.
  final liveFrames = [for (var rep = 0; rep < 5; rep++) ...demo(rep * 1600)];

  // When the ONNX shared lib is on LD_LIBRARY_PATH, learn a real V2 spec from
  // the same demos so the replay exercises both matchers.
  Map<String, dynamic>? v2Spec;
  if (_ortAvailable) {
    final rt = MotionV2NativeRuntime();
    try {
      v2Spec = (await rt.learn(
        movementName: 'Side reach',
        demos: [demo(0), demo(1200), demo(2400)],
      )).toJson();
    } finally {
      await rt.dispose();
    }
  }

  return NuvoMotionDiagnosticSession(
    sessionId: 'MV2-20261014-SELFTEST',
    timestamp: now,
    meta: const {'appVersion': 'test', 'liveTestMatched': true},
    teaching: [for (final d in demos) MotionDiagDemo(
      index: d['index'] as int,
      startMs: d['startMs'] as int,
      endMs: d['endMs'] as int,
      rawFrameCount: d['rawFrameCount'] as int,
      trimmedFrameCount: d['trimmedFrameCount'] as int,
      estFps: (d['estFps'] as num).toDouble(),
      frames: [
        for (final f in (d['frames'] as List).cast<Map<String, dynamic>>())
          MotionDiagFrame(
            tMs: f['t'] as int,
            raw: {
              for (final e in (f['raw'] as Map).entries)
                e.key as String: [
                  for (final x in e.value as List) (x as num).toDouble(),
                ],
            },
          ),
      ],
    )],
    v1: {
      'spec': spec.toJson(),
      'build': capture.debugReport(),
      // 5 synthetic reps land 2 counts in the V1 runtime (the 24-frame
      // canonical spans more than one synthetic rep) — the test target is 2.
      'testResult': const {'isVerified': true, 'count': 2},
    },
    spec: v2Spec,
    movementName: 'Side reach',
    outcome: 'used',
    engine: 'v1',
    durationMs: 30000,
  ).toJson()
    ..['liveTest'] = diagFrames(liveFrames, 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('teach replay', () async {
    final args =
        (jsonDecode(Platform.environment['TEACH_REPLAY_ARGS'] ?? '[]') as List)
            .cast<String>();
    if (Platform.environment['TEACH_REPLAY_SELFTEST'] == '1') {
      final dir = await Directory.systemTemp.createTemp('teach_selftest');
      final artifact = await _selfTestArtifact();
      final file = File('${dir.path}/MV2-20261014-SELFTEST.json.gz');
      await file.writeAsBytes(
        gzip.encode(utf8.encode(jsonEncode(artifact))),
      );
      args.addAll([file.path, '--demos', '--target', '2']);
    }
    await replay.main(args);
  });
}
