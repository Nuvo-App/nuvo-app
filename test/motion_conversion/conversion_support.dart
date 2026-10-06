// Shared harness for motion-conversion differential tests.
//
// Each `<activity>_equivalence_test.dart` feeds the SAME synthetic pose
// sequence through (a) the native validator and (b) the remote runtime built
// from a declarative spec, and compares rep counts / hold durations.
//
// Pose sources used across the suite:
//   * `PoseSource.demo`   — key poses lerped from the app's own
//     movement-preview demos (lib/features/races/presentation/widgets/
//     preset_movement_demos.dart).
//   * `PoseSource.parametric` — simple parametric skeleton generators defined
//     inside each test file (canonical proportions, then transformed).
//
// Robustness transforms mirror the brief: scale about the pose centre
// (0.6x..1.4x), translation, and limb/torso proportion changes (~±15%).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/presentation/widgets/movement_demo.dart';
import 'package:nuvo/features/races/presentation/widgets/nuvo_character_painter.dart';

import '../support/realistic_pose.dart';

export '../support/realistic_pose.dart'
    show CleanPose, PoseNoise, RealisticReplay, p;
export 'package:nuvo/features/races/data/ai_motion_models.dart'
    show AiMotionActivity;

enum PoseSource { demo, parametric }

/// Converts a demo [NuvoCharacterPose] into a `CleanPose` point map.
/// `head` maps to the `nose` landmark; `neck` is dropped (not a runtime
/// landmark).
CleanPose demoToClean(NuvoCharacterPose pose) => {
      'nose': p(pose.head.dx, pose.head.dy),
      'leftShoulder': p(pose.leftShoulder.dx, pose.leftShoulder.dy),
      'rightShoulder': p(pose.rightShoulder.dx, pose.rightShoulder.dy),
      'leftElbow': p(pose.leftElbow.dx, pose.leftElbow.dy),
      'rightElbow': p(pose.rightElbow.dx, pose.rightElbow.dy),
      'leftWrist': p(pose.leftWrist.dx, pose.leftWrist.dy),
      'rightWrist': p(pose.rightWrist.dx, pose.rightWrist.dy),
      'leftHip': p(pose.leftHip.dx, pose.leftHip.dy),
      'rightHip': p(pose.rightHip.dx, pose.rightHip.dy),
      'leftKnee': p(pose.leftKnee.dx, pose.leftKnee.dy),
      'rightKnee': p(pose.rightKnee.dx, pose.rightKnee.dy),
      'leftAnkle': p(pose.leftAnkle.dx, pose.leftAnkle.dy),
      'rightAnkle': p(pose.rightAnkle.dx, pose.rightAnkle.dy),
    };

/// Samples a [MovementDemo] into a pose list. [cycles] full repetitions, each
/// covering [framesPerCycle] frames (the demo timeline already interpolates
/// through its key poses, which acts as the transition between states).
List<CleanPose> demoSequence(
  MovementDemo demo, {
  int cycles = 3,
  int framesPerCycle = 40,
}) {
  final poses = <CleanPose>[];
  for (var c = 0; c < cycles; c++) {
    for (var i = 0; i < framesPerCycle; i++) {
      final t = (c * framesPerCycle + i) / framesPerCycle;
      poses.add(demoToClean(demo.poseAt(t % 1)));
    }
  }
  return poses;
}

/// Linear interpolation between two poses that share the same landmarks.
CleanPose lerpPose(CleanPose a, CleanPose b, double t) => {
      for (final e in a.entries)
        e.key: p(
          e.value.x + (b[e.key]!.x - e.value.x) * t,
          e.value.y + (b[e.key]!.y - e.value.y) * t,
        ),
    };

/// Repeats [pose] [count] times.
List<CleanPose> holdPose(CleanPose pose, int count) =>
    List.filled(count, pose);

/// Builds a transition sequence stand -> A -> stand with [standDwell] frames
/// standing before/between reps, [activeDwell] frames at depth, and
/// [transitionSteps] interpolated frames in between.
///
/// The standing dwell is longer than the depth dwell deliberately: the remote
/// sequence engine must see ~3 consecutive "ready" frames to re-arm the next
/// rep — the same 3-frame stability the native RepCounterStateMachine needs
/// to register `start` again after a count.
List<CleanPose> repSequence(
  CleanPose stand,
  CleanPose active, {
  int reps = 1,
  int standDwell = 6,
  int activeDwell = 4,
  int transitionSteps = 4,
}) {
  final out = <CleanPose>[];
  List<CleanPose> blend(CleanPose a, CleanPose b) => [
        for (var i = 1; i <= transitionSteps; i++)
          lerpPose(a, b, i / (transitionSteps + 1)),
      ];
  out.addAll(holdPose(stand, standDwell));
  for (var r = 0; r < reps; r++) {
    out
      ..addAll(blend(stand, active))
      ..addAll(holdPose(active, activeDwell))
      ..addAll(blend(active, stand))
      ..addAll(holdPose(stand, standDwell));
  }
  return out;
}

/// Scales every landmark about the pose centre (or a fixed anchor). This is
/// the camera-distance change: body proportions are untouched.
CleanPose scaleAbout(
  CleanPose pose,
  double factor, {
  Point<double>? centre,
}) {
  final c = centre ?? poseCentre(pose);
  return {
    for (final e in pose.entries)
      e.key: p(
        c.x + (e.value.x - c.x) * factor,
        c.y + (e.value.y - c.y) * factor,
      ),
  };
}

Point<double> poseCentre(CleanPose pose) {
  var sx = 0.0;
  var sy = 0.0;
  for (final v in pose.values) {
    sx += v.x;
    sy += v.y;
  }
  return Point(sx / pose.length, sy / pose.length);
}

/// Shifts the whole pose — camera framing / off-centre placement change.
CleanPose translatePose(CleanPose pose, double dx, double dy) => {
      for (final e in pose.entries)
        e.key: p(e.value.x + dx, e.value.y + dy),
    };

/// Varies body proportions without changing the pose centre much:
///   * [legScale]  scales knee/ankle offsets away from their hip,
///   * [torsoScale] scales shoulder/head offsets away from the hip centre,
///   * [armScale]  scales elbow/wrist offsets away from their shoulder,
///   * [widthScale] scales the horizontal half-width around the x centre.
/// A ±0.15 factor is the ~±15% body-proportion change from the brief.
CleanPose morphProportions(
  CleanPose pose, {
  double legScale = 1.0,
  double torsoScale = 1.0,
  double armScale = 1.0,
  double widthScale = 1.0,
}) {
  final cx = poseCentre(pose).x;
  Point<double> hip(String side) => pose['${side}Hip']!;
  Point<double> shoulder(String side) => pose['${side}Shoulder']!;
  final hipCentre = Point(
    (pose['leftHip']!.x + pose['rightHip']!.x) / 2,
    (pose['leftHip']!.y + pose['rightHip']!.y) / 2,
  );
  Point<double> scaleFrom(Point<double> anchor, Point<double> v, double f) =>
      p(anchor.x + (v.x - anchor.x) * f, anchor.y + (v.y - anchor.y) * f);
  final out = <String, Point<double>>{};
  for (final e in pose.entries) {
    final v = e.value;
    var nv = v;
    final side = e.key.startsWith('left')
        ? 'left'
        : e.key.startsWith('right')
            ? 'right'
            : null;
    final name = side == null ? e.key : e.key.substring(side.length);
    if (name == 'Knee' || name == 'Ankle') {
      nv = scaleFrom(hip(side!), v, legScale);
    } else if (name == 'Elbow' || name == 'Wrist') {
      nv = scaleFrom(shoulder(side!), v, armScale);
    } else if (name == 'Shoulder' || e.key == 'nose') {
      nv = scaleFrom(hipCentre, v, torsoScale);
    }
    out[e.key] = p(cx + (nv.x - cx) * widthScale, nv.y);
  }
  return out;
}

/// Applies per-joint noise + confidence wobble through the existing replay
/// harness so jitter coverage matches the native replay tests.
List<CleanPose> jittered(
  List<CleanPose> poses, {
  PoseNoise noise = PoseNoise.phone,
  int seed = 7,
}) {
  final rnd = Random(seed);
  return [
    for (final pose in poses)
      {
        for (final e in pose.entries)
          e.key: p(
            e.value.x + (rnd.nextDouble() - 0.5) * noise.jitter * 2,
            e.value.y + (rnd.nextDouble() - 0.5) * noise.jitter * 2,
          ),
      },
  ];
}

/// Wraps a `CleanPose` into a frame (timestamps are synthetic and uniform).
NuvoPoseFrame frameOf(CleanPose pose, int index, {int stepMs = 33}) =>
    NuvoPoseFrame(
      points: {
        for (final e in pose.entries)
          e.key: NuvoPosePoint(
            x: e.value.x,
            y: e.value.y,
            z: 0,
            likelihood: 0.95,
          ),
      },
      imageWidth: 1080,
      imageHeight: 1920,
      createdAt: DateTime.fromMillisecondsSinceEpoch(index * stepMs),
    );

List<NuvoPoseFrame> framesOf(List<CleanPose> poses, {int stepMs = 33}) => [
      for (var i = 0; i < poses.length; i++) frameOf(poses[i], i, stepMs: stepMs),
    ];

/// Runs the NATIVE validator over [poses] and returns its current value.
int runNative(
  AiMotionActivity activity,
  List<CleanPose> poses, {
  int target = 30,
}) {
  final v = createMotionValidator(activity, target)..start();
  for (final frame in framesOf(poses)) {
    v.update(frame);
  }
  return v.currentValue;
}

/// Runs the REMOTE runtime built from [specJson] and returns its count (or
/// elapsed seconds for a hold engine, matching `currentValue` semantics).
int runRemote(
  Map<String, dynamic> specJson,
  List<CleanPose> poses, {
  int target = 30,
}) {
  final spec = RemoteVerifierSpec.fromJson(specJson);
  final rt = createRemoteVerifierRuntime(spec: spec, target: target)..start();
  var lastCount = 0;
  for (final frame in framesOf(poses)) {
    // Read the update's count rather than rt.count: HoldV1Runtime reports
    // elapsed seconds only through the returned update object.
    lastCount = rt.update(frame).count;
  }
  return lastCount;
}

/// Loads a spec file's JSON map (spec files live under
/// `server/worker/motion-releases/`). Kept in code so tests share the exact
/// same object the Worker checksum signs.
Map<String, dynamic> specJson(Map<String, dynamic> Function() loader) =>
    loader();

/// Asserts remote == native counts for a named case. [tolerance] allows a
/// stated slack where a test documents a quantified divergence.
void expectRemoteEqualsNative(
  String label,
  num native,
  num remote, {
  double tolerance = 0,
}) {
  expect(
    remote,
    closeTo(native, tolerance),
    reason:
        '$label: native=$native remote=$remote tolerance=$tolerance',
  );
}
