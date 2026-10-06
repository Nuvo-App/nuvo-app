import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart' show Offset;
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/presentation/widgets/nuvo_character_painter.dart';
import 'package:nuvo/features/races/presentation/widgets/preset_movement_demos.dart';

/// Shared helpers for the W10 motion-conversion differential tests.
///
/// A pose is a `Map<String, Offset>` of normalized [0,1] landmark
/// coordinates (the same space [NuvoPosePoint.x]/[.y] live in). The helpers
/// below provide:
///
/// * [skeleton] — a parametric front-view rig whose segment lengths can be
///   scaled independently (body-proportion sweeps of ±15%);
/// * [transformPose] — uniform scale about the frame centre plus
///   translation (camera distance / framing shifts);
/// * [jitterPose] — uniform landmark noise (ML Kit wobble);
/// * [poseFromCharacterPose] — converts an app preview keyframe
///   (`NuvoCharacterPose`) into a test pose, so specs are exercised against
///   the same keyframes the product demo animates;
/// * [framesOf] — repeats a pose list into timed [NuvoPoseFrame]s;
/// * [runBoth] — feeds one frame stream through the native validator and the
///   remote runtime built from a release JSON on disk, returning both counts.
typedef PoseMap = Map<String, Offset>;

/// Canonical standing rig (front view). Segment lengths default to the same
/// proportions the `test/support/realistic_pose.dart` harness uses so noise
/// behaviour matches the existing replay suites.
///
/// Torso = shoulder-to-hip vertical span (0.30). Hip→knee (thigh) = 0.27 and
/// knee→ankle (shin) = 0.18, so the ankle rests at ~0.95 for a 0.50 hip.
PoseMap skeleton({
  double torsoLen = 0.30,
  double hipY = 0.50,
  double shoulderHalfWidth = 0.06,
  double hipHalfWidth = 0.05,
  double thigh = 0.27,
  double shin = 0.18,
  double legHalfGap = 0.05,
  // Arms hang at the sides: elbow ~0.18 below shoulder, wrist ~0.36 below.
  double upperArm = 0.18,
  double foreArm = 0.18,
  double armOut = 0.045,
  double headUp = 0.085,
  double centerX = 0.50,
}) {
  final shoulderY = hipY - torsoLen;
  final kneeY = hipY + thigh;
  final ankleY = kneeY + shin;
  return {
    'nose': Offset(centerX, shoulderY - headUp),
    'leftShoulder': Offset(centerX - shoulderHalfWidth, shoulderY),
    'rightShoulder': Offset(centerX + shoulderHalfWidth, shoulderY),
    'leftElbow': Offset(centerX - shoulderHalfWidth - armOut * 0.5,
        shoulderY + upperArm),
    'rightElbow': Offset(centerX + shoulderHalfWidth + armOut * 0.5,
        shoulderY + upperArm),
    'leftWrist': Offset(centerX - shoulderHalfWidth - armOut,
        shoulderY + upperArm + foreArm),
    'rightWrist': Offset(centerX + shoulderHalfWidth + armOut,
        shoulderY + upperArm + foreArm),
    'leftHip': Offset(centerX - hipHalfWidth, hipY),
    'rightHip': Offset(centerX + hipHalfWidth, hipY),
    'leftKnee': Offset(centerX - legHalfGap, kneeY),
    'rightKnee': Offset(centerX + legHalfGap, kneeY),
    'leftAnkle': Offset(centerX - legHalfGap, ankleY),
    'rightAnkle': Offset(centerX + legHalfGap, ankleY),
  };
}

/// Uniformly scales a pose about the frame centre (camera-distance change)
/// and translates it (framing shift).
PoseMap transformPose(PoseMap pose, {double scale = 1, double dx = 0, double dy = 0}) {
  const cx = 0.5, cy = 0.5;
  return pose.map(
    (name, p) => MapEntry(
      name,
      Offset(cx + (p.dx - cx) * scale + dx, cy + (p.dy - cy) * scale + dy),
    ),
  );
}

/// Applies independent limb/torso proportion changes (±) to an existing pose
/// by rescaling each skeletal segment relative to its parent joint. This
/// exercises body-proportion robustness without touching global scale.
///
/// * [torso] scales shoulder↔hip span (and everything attached above).
/// * [legs] scales hip→knee→ankle on both sides.
/// * [arms] scales shoulder→elbow→wrist on both sides.
/// * [shoulderW]/[hipW] scale the respective half-widths.
PoseMap warpProportions(
  PoseMap pose, {
  double torso = 1,
  double legs = 1,
  double arms = 1,
  double shoulderW = 1,
  double hipW = 1,
}) {
  Offset? at(String name) => pose[name];
  Offset mid(String a, String b) =>
      Offset((at(a)!.dx + at(b)!.dx) / 2, (at(a)!.dy + at(b)!.dy) / 2);
  Offset offset(Offset base, Offset from, double s) =>
      Offset(base.dx + (from.dx - base.dx) * s, base.dy + (from.dy - base.dy) * s);

  final out = Map<String, Offset>.of(pose);
  final hipMid = mid('leftHip', 'rightHip');
  final shoulderMid = mid('leftShoulder', 'rightShoulder');

  for (final side in ['left', 'right']) {
    final hip = out['${side}Hip']!;
    final knee = out['${side}Knee']!;
    final ankle = out['${side}Ankle']!;
    // Leg segments scale about the hip.
    final newKnee = offset(hip, knee, legs);
    final newAnkle = Offset(
      newKnee.dx + (ankle.dx - knee.dx) * legs,
      newKnee.dy + (ankle.dy - knee.dy) * legs,
    );
    out['${side}Knee'] = newKnee;
    out['${side}Ankle'] = newAnkle;

    // Torso scales about the hip midpoint; the shoulder keeps its own
    // half-width scaled by shoulderW.
    final shoulder = out['${side}Shoulder']!;
    final hipSide = out['${side}Hip']!;
    final newShoulder = Offset(
      hipMid.dx + (shoulder.dx - hipMid.dx) * shoulderW,
      hipMid.dy + (shoulder.dy - hipMid.dy) * torso,
    );
    out['${side}Shoulder'] = newShoulder;
    out['${side}Hip'] = Offset(
      hipMid.dx + (hipSide.dx - hipMid.dx) * hipW,
      hipSide.dy,
    );

    // Arm chain follows the (moved) shoulder.
    final elbow = out['${side}Elbow']!;
    final wrist = out['${side}Wrist']!;
    final newElbow = offset(newShoulder, elbow, arms);
    out['${side}Elbow'] = newElbow;
    out['${side}Wrist'] = Offset(
      newElbow.dx + (wrist.dx - elbow.dx) * arms,
      newElbow.dy + (wrist.dy - elbow.dy) * arms,
    );
  }
  // Nose rides the head — keep it glued above the moved shoulder midpoint.
  out['nose'] = Offset(
    shoulderMid.dx + (at('nose')!.dx - shoulderMid.dx) * shoulderW,
    out['leftShoulder']!.dy - (shoulderMid.dy - at('nose')!.dy) * torso,
  );
  return out;
}

/// Adds uniform ±[magnitude] jitter to every landmark (ML Kit wobble).
PoseMap jitterPose(PoseMap pose, Random rng, double magnitude) {
  double j() => (rng.nextDouble() * 2 - 1) * magnitude;
  return pose.map((name, p) => MapEntry(name, p + Offset(j(), j())));
}

// ── Parametric motion generators ────────────────────────────────────────────
// These are the pose sources for activities that have no preview keyframes
// (marching, butt kicks, lateral steps, calf raises, burpees) and the
// controllable-depth fixtures for those that do.

/// Rotates both arms upward around the shoulders. [lift] 0 = at sides,
/// 1 = overhead. Scale/proportion-invariant motion primitive for arm_raises,
/// jumping_jacks, and the burpee hands-up phase.
PoseMap armsUp(PoseMap base, double lift) {
  Offset swing(Offset shoulder, Offset joint) {
    final sx = joint.dx - shoulder.dx;
    final sy = joint.dy - shoulder.dy;
    final len = sqrt(sx * sx + sy * sy);
    final target = pi * lift;
    final dir = sx >= 0 ? 1 : -1;
    return Offset(
      shoulder.dx + dir * len * sin(target),
      shoulder.dy + len * cos(target),
    );
  }

  final out = {...base};
  for (final side in ['left', 'right']) {
    final sh = base['${side}Shoulder']!;
    out['${side}Elbow'] = swing(sh, base['${side}Elbow']!);
    out['${side}Wrist'] = swing(sh, base['${side}Wrist']!);
  }
  return out;
}

/// Bilateral squat. [depth] 0 = standing, 1 = hips at/below knee level.
PoseMap squatDepth(PoseMap base, double depth) {
  final hipDrop = 0.18 * depth;
  final shoulderDrop = hipDrop * 0.85;
  final out = {...base};
  for (final side in ['left', 'right']) {
    out['${side}Hip'] =
        Offset(base['${side}Hip']!.dx, base['${side}Hip']!.dy + hipDrop);
    for (final j in ['Shoulder', 'Elbow', 'Wrist']) {
      final p = base['$side$j']!;
      out['$side$j'] = Offset(p.dx, p.dy + shoulderDrop);
    }
    final knee = base['${side}Knee']!;
    final dir = side == 'left' ? -1 : 1;
    out['${side}Knee'] =
        Offset(knee.dx + dir * 0.05 * depth, knee.dy - 0.10 * depth);
  }
  out['nose'] = Offset(base['nose']!.dx, base['nose']!.dy + shoulderDrop);
  return out;
}

/// One-knee drive. [lift] 1 ≈ knee at hip height; ankle follows the fold.
PoseMap kneeLift(PoseMap base, {required String side, required double lift}) {
  final hip = base['${side}Hip']!;
  final knee = base['${side}Knee']!;
  final ankle = base['${side}Ankle']!;
  final dir = side == 'left' ? -1 : 1;
  final newKnee = Offset(
      knee.dx + dir * 0.02 * lift, knee.dy + (hip.dy - 0.02 - knee.dy) * lift);
  final newAnkle = Offset(
      ankle.dx + dir * 0.01 * lift,
      ankle.dy - (ankle.dy - newKnee.dy - 0.10) * 0.9 * lift);
  return {...base, '${side}Knee': newKnee, '${side}Ankle': newAnkle};
}

/// Heel-to-glute fold: ankle rises toward the hip while the knee stays low —
/// the butt-kick signature (thigh stays down).
PoseMap heelKick(PoseMap base, {required String side, required double kick}) {
  final hip = base['${side}Hip']!;
  final knee = base['${side}Knee']!;
  final ankle = base['${side}Ankle']!;
  final dir = side == 'left' ? -1 : 1;
  final newKnee =
      Offset(knee.dx + dir * 0.03 * kick, knee.dy - 0.04 * kick);
  final newAnkle = Offset(ankle.dx + dir * 0.02 * kick,
      ankle.dy - (ankle.dy - hip.dy - 0.10) * kick * 0.9);
  return {...base, '${side}Knee': newKnee, '${side}Ankle': newAnkle};
}

/// Front-view lunge: stepping leg reaches out, knee marker swings forward and
/// up (~113° knee angle at full depth), torso drops with the hips.
PoseMap lungePose(PoseMap base, {required String side, double depth = 1}) {
  final out = {...base};
  final dir = side == 'left' ? -1 : 1;
  final knee = out['${side}Knee']!;
  final ankle = out['${side}Ankle']!;
  out['${side}Knee'] =
      Offset(knee.dx + dir * 0.20 * depth, knee.dy - 0.14 * depth);
  out['${side}Ankle'] = Offset(ankle.dx + dir * 0.24 * depth, ankle.dy);
  for (final s in ['left', 'right']) {
    for (final j in ['Hip', 'Shoulder', 'Elbow', 'Wrist']) {
      final p = out['$s$j']!;
      out['$s$j'] = Offset(p.dx + dir * 0.03 * depth, p.dy + 0.08 * depth);
    }
  }
  final n = out['nose']!;
  out['nose'] = Offset(n.dx + dir * 0.03 * depth, n.dy + 0.08 * depth);
  return out;
}

/// One ankle steps straight out. [out] is the lateral reach.
PoseMap lateralStep(PoseMap base, {required String side, double out = 0.22}) {
  final p = {...base};
  final dir = side == 'left' ? -1 : 1;
  final ankle = p['${side}Ankle']!;
  final knee = p['${side}Knee']!;
  p['${side}Ankle'] = Offset(ankle.dx + dir * out, ankle.dy);
  p['${side}Knee'] = Offset(knee.dx + dir * out * 0.5, knee.dy);
  return p;
}

/// Airborne tuck proxy: both ankles rise [rise] while the body keeps its
/// extended posture — what the native AirborneStateTracker sees as flight
/// (ankle displacement from the rolling baseline).
PoseMap flightTuck(PoseMap base, double rise) {
  final out = {...base};
  for (final side in ['left', 'right']) {
    final a = out['${side}Ankle']!;
    out['${side}Ankle'] = Offset(a.dx, a.dy - rise);
  }
  return out;
}

/// Burpee plant moment: squat depth + hands reaching for the floor.
PoseMap burpeeDown(PoseMap base) {
  final crouch = squatDepth(base, 0.9);
  return {
    ...crouch,
    'leftWrist': const Offset(0.42, 0.78),
    'rightWrist': const Offset(0.58, 0.78),
    'leftElbow': const Offset(0.42, 0.60),
    'rightElbow': const Offset(0.58, 0.60),
  };
}

/// Heels lifted — calf-raise top (the whole body rises rigidly; no
/// scale-invariant per-frame signature exists, which is why this motion has
/// no converted spec).
PoseMap calfRaise(PoseMap base, double lift) => {
      for (final e in base.entries)
        e.key: Offset(e.value.dx, e.value.dy - 0.045 * lift),
    };

/// Expands an interpolated pose list into held frames.
List<NuvoPoseFrame> framesFromPoses(
  List<PoseMap> poses, {
  int holdEach = 1,
  int msPerFrame = 50,
}) =>
    framesOf(poses.map((p) => (p, holdEach)).toList(), msPerFrame: msPerFrame);

/// Returns the same frame list with every landmark jittered by ±[magnitude].
List<NuvoPoseFrame> jitterFrames(
  List<NuvoPoseFrame> frames,
  Random rng,
  double magnitude,
) {
  double j() => (rng.nextDouble() * 2 - 1) * magnitude;
  return frames
      .map((f) => NuvoPoseFrame(
            points: {
              for (final e in f.points.entries)
                e.key: NuvoPosePoint(
                  x: e.value.x + j(),
                  y: e.value.y + j(),
                  z: e.value.z,
                  likelihood: e.value.likelihood,
                ),
            },
            imageWidth: f.imageWidth,
            imageHeight: f.imageHeight,
            createdAt: f.createdAt,
          ))
      .toList();
}

/// A rep-cycle frame stream: [schedule] of (pose, holdFrames) repeated
/// [reps] times, optionally surrounded by idle frames.
List<NuvoPoseFrame> repCycleFrames(
  List<(PoseMap, int)> oneRep, {
  int reps = 3,
  int idleBefore = 8,
  int idleAfter = 8,
  int msPerFrame = 50,
}) {
  final schedule = <(PoseMap, int)>[];
  if (idleBefore > 0) schedule.add((skeleton(), idleBefore));
  for (var r = 0; r < reps; r++) {
    schedule.addAll(oneRep);
  }
  if (idleAfter > 0) schedule.add((skeleton(), idleAfter));
  return framesOf(schedule, msPerFrame: msPerFrame);
}

/// Converts an app preview keyframe into a test pose. `head` maps to `nose`
/// (the only pose landmark above the shoulders); `neck` is dropped — it is
/// not one of the 13 supported pose landmarks.
PoseMap poseFromCharacterPose(NuvoCharacterPose pose) => {
      'nose': pose.head,
      'leftShoulder': pose.leftShoulder,
      'rightShoulder': pose.rightShoulder,
      'leftElbow': pose.leftElbow,
      'rightElbow': pose.rightElbow,
      'leftWrist': pose.leftWrist,
      'rightWrist': pose.rightWrist,
      'leftHip': pose.leftHip,
      'rightHip': pose.rightHip,
      'leftKnee': pose.leftKnee,
      'rightKnee': pose.rightKnee,
      'leftAnkle': pose.leftAnkle,
      'rightAnkle': pose.rightAnkle,
    };

/// Preview keyframes for an activity (null when the app has no authored demo).
/// `head` maps to `nose`; `neck` is dropped — see [poseFromCharacterPose].
List<PoseMap>? demoPoseMapsFor(AiMotionActivity activity) =>
    movementDemoForType(
      MotionActivityType.fromBackendValue(activity.backendValue) ??
          MotionActivityType.remote,
    )?.poses.map(poseFromCharacterPose).toList();

PoseMap lerpPose(PoseMap a, PoseMap b, double t) => {
      for (final key in a.keys)
        if (b.containsKey(key)) key: Offset.lerp(a[key]!, b[key]!, t)!,
    };

/// Expands a keyframe list into a frame-by-frame pose list by linear
/// interpolation — the same motion the preview widget animates.
List<PoseMap> interpolatePoses(List<PoseMap> keys, {int framesPerSegment = 8}) {
  final out = <PoseMap>[];
  for (var i = 0; i < keys.length - 1; i++) {
    for (var s = 0; s < framesPerSegment; s++) {
      out.add(lerpPose(keys[i], keys[i + 1], s / framesPerSegment));
    }
  }
  out.add(keys.last);
  return out;
}

/// Repeats each `(pose, holds)` pair into timed frames at ~20 fps, matching
/// the cadence a real ML Kit stream produces and staying inside every remote
/// timeout window.
List<NuvoPoseFrame> framesOf(
  List<(PoseMap, int)> schedule, {
  double likelihood = 0.95,
  int msPerFrame = 50,
  int startMs = 0,
}) {
  var t = startMs;
  final frames = <NuvoPoseFrame>[];
  for (final (pose, holds) in schedule) {
    for (var i = 0; i < holds; i++) {
      t += msPerFrame;
      frames.add(poseToFrame(pose, t, likelihood: likelihood));
    }
  }
  return frames;
}

NuvoPoseFrame poseToFrame(PoseMap pose, int tMs, {double likelihood = 0.95}) {
  return NuvoPoseFrame(
    points: {
      for (final entry in pose.entries)
        entry.key: NuvoPosePoint(
          x: entry.value.dx,
          y: entry.value.dy,
          z: 0,
          likelihood: likelihood,
        ),
    },
    imageWidth: 1000,
    imageHeight: 1000,
    createdAt: DateTime.fromMillisecondsSinceEpoch(tMs, isUtc: true),
  );
}

/// Loads a motion-release spec file from `server/worker/motion-releases/`
/// (relative to the package root) exactly as the catalog would deliver it:
/// parse the JSON, run it through [RemoteVerifierSpec.fromJson] — the strict
/// client parser — and build the runtime.
RemoteVerifierRuntime remoteRuntimeForFile(String fileName, {int target = 999}) {
  final file = File('server/worker/motion-releases/$fileName');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final spec = RemoteVerifierSpec.fromJson(json);
  return createRemoteVerifierRuntime(spec: spec, target: target);
}

/// Runs the same frame stream through the compiled native validator and the
/// remote runtime, returning both rep counts. [nativeValue]/[remoteCount]
/// are read after the stream ends — the differential assertion compares them.
({int nativeCount, int remoteCount}) runBoth({
  required AiMotionActivity activity,
  required List<NuvoPoseFrame> frames,
  required String specFile,
  int target = 999,
}) {
  final native = createMotionValidator(activity, target);
  final remote = remoteRuntimeForFile(specFile, target: target);
  native.start();
  remote.start();
  for (final frame in frames) {
    native.update(frame);
    remote.update(frame);
  }
  return (nativeCount: native.currentValue, remoteCount: remote.count);
}

/// Native validator alone (for NO/PARTIAL motions that document the native
/// baseline without a remote counterpart).
int runNative(AiMotionActivity activity, List<NuvoPoseFrame> frames,
    {int target = 999}) {
  final validator = createMotionValidator(activity, target);
  validator.start();
  for (final frame in frames) {
    validator.update(frame);
  }
  return validator.currentValue;
}

/// Remote runtime alone over a parsed spec (no native counterpart).
int runRemote(String specFile, List<NuvoPoseFrame> frames, {int target = 999}) {
  final runtime = remoteRuntimeForFile(specFile, target: target);
  runtime.start();
  for (final frame in frames) {
    runtime.update(frame);
  }
  return runtime.count;
}
