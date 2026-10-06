// Temporary calibration probe for W10. Prints native signals next to
// candidate remote-predicate values so thresholds can be picked on evidence.
import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/remote_pose_features.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

Map<String, NuvoPosePoint> _pts(PoseMap pose, {double l = 0.95}) => {
      for (final e in pose.entries)
        e.key: NuvoPosePoint(x: e.value.dx, y: e.value.dy, z: 0, likelihood: l),
    };

NuvoPoseFrame _f(PoseMap pose) => NuvoPoseFrame(
      points: _pts(pose),
      imageWidth: 1000,
      imageHeight: 1000,
      createdAt: DateTime.utc(2026, 1, 1),
    );

double _segR(NuvoPoseFrame f, String a, String b, String rA, String rB) =>
    RemotePoseFeatures.segmentRatio(
            a: f.point(a), b: f.point(b), refA: f.point(rA), refB: f.point(rB)) ??
        double.nan;

double _ang(NuvoPoseFrame f, String a, String b, String c) =>
    RemotePoseFeatures.angle(a: f.point(a), b: f.point(b), c: f.point(c)) ??
    double.nan;

double _dy(NuvoPoseFrame f, String a, String b) =>
    RemotePoseFeatures.axisDelta(
            a: f.point(a), b: f.point(b), isX: false) ??
        double.nan;

double _dx(NuvoPoseFrame f, String a, String b) =>
    RemotePoseFeatures.axisDelta(
            a: f.point(a), b: f.point(b), isX: true) ??
        double.nan;

String _n(num v) => v.isNaN ? '  nan ' : v.toStringAsFixed(3).padLeft(6);

void _row(String label, PoseMap pose) {
  final f = _f(pose);
  final feats = PoseFeatureExtractor(f);
  final torso = feats.torsoHeight;
  final h2k = feats.hipToKneeRatio();
  final kneeL = feats.kneeAngle(left: true);
  final kneeR = feats.kneeAngle(left: false);
  final kneeSep = (f.point('leftKnee')!.x - f.point('rightKnee')!.x).abs() /
      feats.hipWidth;
  final ankleW = feats.ankleWidth / feats.bodyWidth;
  // Candidate remote predicates:
  final khL = _segR(f, 'leftKnee', 'leftHip', 'leftShoulder', 'leftHip');
  final khR = _segR(f, 'rightKnee', 'rightHip', 'rightShoulder', 'rightHip');
  final kneePair = _segR(f, 'leftKnee', 'rightKnee', 'leftHip', 'rightHip');
  final anklePair =
      _segR(f, 'leftAnkle', 'rightAnkle', 'leftShoulder', 'rightShoulder');
  final armAngL = _ang(f, 'leftWrist', 'leftShoulder', 'leftHip');
  final armAngR = _ang(f, 'rightWrist', 'rightShoulder', 'rightHip');
  final whL = _segR(f, 'leftWrist', 'leftHip', 'leftShoulder', 'leftHip');
  final foldR = _ang(f, 'leftKnee', 'rightKnee', 'rightHip');
  final foldL = _ang(f, 'rightKnee', 'leftKnee', 'leftHip');
  final stepR = _ang(f, 'leftHip', 'rightHip', 'rightAnkle');
  final stepL = _ang(f, 'rightHip', 'leftHip', 'leftAnkle');
  final wHipDyL = _dy(f, 'leftWrist', 'leftHip');
  final wShDyL = _dy(f, 'leftWrist', 'leftShoulder');
  final ahL = _segR(f, 'leftAnkle', 'leftHip', 'leftShoulder', 'leftHip');
  final ahR = _segR(f, 'rightAnkle', 'rightHip', 'rightShoulder', 'rightHip');
  final kneeStagDy = _dy(f, 'rightKnee', 'leftKnee');
  final ankleStagDy = _dy(f, 'rightAnkle', 'leftAnkle');
  print(
    '$label | torso=${_n(torso)} h2k=${_n(h2k)} kneeL=${_n(kneeL)} '
    'kneeR=${_n(kneeR)} kSep=${_n(kneeSep)} ankW=${_n(ankleW)} || '
    'khL=${_n(khL)} khR=${_n(khR)} kneePair=${_n(kneePair)} '
    'ankPair=${_n(anklePair)} armL=${_n(armAngL)} armR=${_n(armAngR)} '
    'whL=${_n(whL)} foldR=${_n(foldR)} foldL=${_n(foldL)} '
    'stepR=${_n(stepR)} stepL=${_n(stepL)} wHip=${_n(wHipDyL)} '
    'wSh=${_n(wShDyL)} ahL=${_n(ahL)} ahR=${_n(ahR)} '
    'kStag=${_n(kneeStagDy)} aStag=${_n(ankleStagDy)}',
  );
}

void _section(String title) => print('\n=== $title ===');

PoseMap _with(PoseMap base, Map<String, Offset> overrides) =>
    {...base, ...overrides};

PoseMap _raiseArms(PoseMap base, double lift) {
  // lift 0 = arms at sides, 1 = overhead. Rotate each arm up around the
  // shoulder in the image plane (upper arm + forearm as one segment chain).
  Offset armJoint(Offset shoulder, Offset joint, double t) {
    // rotate from "down" (0,+) direction toward "up" (0,-) through the side.
    final sx = (joint.dx - shoulder.dx);
    final sy = (joint.dy - shoulder.dy);
    final len = math.sqrt(sx * sx + sy * sy);
    final ang = math.atan2(sx.abs(), sy); // 0 = straight down, pi = straight up
    final target = math.pi * t;
    final dir = sx >= 0 ? 1 : -1; // left arm swings left, right swings right
    return Offset(shoulder.dx + dir * len * math.sin(target * (dir > 0 ? 1 : 1)) * dir.abs(),
        shoulder.dy + len * math.cos(target));
  }

  final out = {...base};
  for (final side in ['left', 'right']) {
    final sh = base['${side}Shoulder']!;
    final el = base['${side}Elbow']!;
    final wr = base['${side}Wrist']!;
    out['${side}Elbow'] = armJoint(sh, el, lift);
    out['${side}Wrist'] = armJoint(sh, wr, lift);
  }
  return out;
}

PoseMap _kneeLift(PoseMap base, {required String side, required double lift}) {
  // lift 0..1 = knee drive toward hip; ankle follows the shin fold.
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

PoseMap _heelKick(PoseMap base, {required String side, required double kick}) {
  final hip = base['${side}Hip']!;
  final knee = base['${side}Knee']!;
  final ankle = base['${side}Ankle']!;
  final dir = side == 'left' ? -1 : 1;
  final newKnee = Offset(knee.dx + dir * 0.03 * kick, knee.dy - 0.04 * kick);
  final newAnkle = Offset(ankle.dx + dir * 0.02 * kick,
      ankle.dy - (ankle.dy - hip.dy - 0.10) * kick * 0.9);
  return {...base, '${side}Knee': newKnee, '${side}Ankle': newAnkle};
}

PoseMap _squatDepth(PoseMap base, double depth) {
  // depth 0 = standing, 1 = hips to knee level. Shoulders follow hips with
  // slight forward lean; knees splay slightly forward.
  final hipDrop = 0.18 * depth;
  final shoulderDrop = hipDrop * 0.85;
  final out = {...base};
  for (final side in ['left', 'right']) {
    final hip = out['${side}Hip']!;
    out['${side}Hip'] = Offset(hip.dx, hip.dy + hipDrop);
    final sh = out['${side}Shoulder']!;
    out['${side}Shoulder'] = Offset(sh.dx, sh.dy + shoulderDrop);
    final el = out['${side}Elbow']!;
    out['${side}Elbow'] = Offset(el.dx, el.dy + shoulderDrop);
    final wr = out['${side}Wrist']!;
    out['${side}Wrist'] = Offset(wr.dx, wr.dy + shoulderDrop);
    final knee = out['${side}Knee']!;
    final dir = side == 'left' ? -1 : 1;
    out['${side}Knee'] = Offset(
        knee.dx + dir * 0.05 * depth, knee.dy - 0.10 * depth);
  }
  out['nose'] =
      Offset(base['nose']!.dx, base['nose']!.dy + shoulderDrop);
  return out;
}

PoseMap _lunge(PoseMap base, {required String side, double depth = 1}) {
  // Front-view lunge: stepping leg reaches out; knee marker swings forward
  // and up (knee flexes to ~110-120deg), hips+torso drop together.
  final out = {...base};
  final dir = side == 'left' ? -1 : 1;
  final knee = out['${side}Knee']!;
  final ankle = out['${side}Ankle']!;
  out['${side}Knee'] = Offset(
      knee.dx + dir * 0.20 * depth, knee.dy - 0.14 * depth);
  out['${side}Ankle'] = Offset(ankle.dx + dir * 0.24 * depth, ankle.dy);
  // Whole body drops ~0.08 at full depth and leans slightly toward the step.
  for (final s in ['left', 'right']) {
    for (final j in ['Hip', 'Shoulder', 'Elbow', 'Wrist']) {
      final p = out['$s$j']!;
      out['$s$j'] =
          Offset(p.dx + dir * 0.03 * depth, p.dy + 0.08 * depth);
    }
  }
  final n = out['nose']!;
  out['nose'] = Offset(n.dx + dir * 0.03 * depth, n.dy + 0.08 * depth);
  return out;
}

PoseMap _lateralStep(PoseMap base, {required String side, double out = 0.22}) {
  final p = {...base};
  final dir = side == 'left' ? -1 : 1;
  final ankle = p['${side}Ankle']!;
  final knee = p['${side}Knee']!;
  p['${side}Ankle'] = Offset(ankle.dx + dir * out, ankle.dy);
  p['${side}Knee'] = Offset(knee.dx + dir * out * 0.5, knee.dy);
  return p;
}

PoseMap _calfRaise(PoseMap base, double lift) {
  // On toes: the whole body rises except the toe contact — approximated by
  // lifting every landmark except ankles only rise slightly (joint moves up).
  // Real: ankle joint rises ~0.04-0.05 normalized; everything above follows.
  final out = <String, Offset>{};
  for (final e in base.entries) {
    if (e.key.endsWith('Ankle')) {
      out[e.key] = Offset(e.value.dx, e.value.dy - 0.045 * lift);
    } else {
      out[e.key] = Offset(e.value.dx, e.value.dy - 0.045 * lift);
    }
  }
  return out;
}

void main() {
  test('probe', () {
    final base = skeleton();

    _section('ARM RAISES');
    for (final lift in [0.0, 0.4, 0.7, 0.9, 1.0]) {
      _row('arm lift ${(lift * 100).round()}%', _raiseArms(base, lift));
    }
    for (final s in [0.6, 1.0, 1.4]) {
      _row('arm up scale $s',
          transformPose(_raiseArms(base, 1.0), scale: s));
      _row('arm down scale $s',
          transformPose(_raiseArms(base, 0.0), scale: s));
    }

    _section('JUMPING JACKS');
    _row('closed', base);
    final jjOpen = _with(_raiseArms(base, 0.95), {
      'leftAnkle': const Offset(0.30, 0.95),
      'rightAnkle': const Offset(0.70, 0.95),
      'leftKnee': const Offset(0.36, 0.77),
      'rightKnee': const Offset(0.64, 0.77),
    });
    _row('open', jjOpen);
    _row('arms up only', _raiseArms(base, 0.95));
    _row('feet wide only', _with(base, {
      'leftAnkle': const Offset(0.30, 0.95),
      'rightAnkle': const Offset(0.70, 0.95),
    }));
    for (final s in [0.6, 1.0, 1.4]) {
      _row('open s$s', transformPose(jjOpen, scale: s));
      _row('closed s$s', transformPose(base, scale: s));
    }

    _section('DEEP SQUATS');
    for (final d in [0.0, 0.4, 0.6, 0.8, 1.0]) {
      _row('squat depth ${(d * 100).round()}%', _squatDepth(base, d));
    }
    for (final s in [0.6, 1.0, 1.4]) {
      _row('deep s$s', transformPose(_squatDepth(base, 1.0), scale: s));
      _row('stand s$s', transformPose(base, scale: s));
    }
    // torso bend confuser: shoulders down, hips/knees stay
    final bend = _with(base, {
      'leftShoulder': const Offset(0.44, 0.38),
      'rightShoulder': const Offset(0.56, 0.38),
      'nose': const Offset(0.50, 0.30),
      'leftElbow': const Offset(0.42, 0.55),
      'rightElbow': const Offset(0.58, 0.55),
      'leftWrist': const Offset(0.41, 0.72),
      'rightWrist': const Offset(0.59, 0.72),
    });
    _row('torso bend', bend);

    _section('LUNGES');
    _row('right lunge', _lunge(base, side: 'right'));
    _row('left lunge', _lunge(base, side: 'left'));
    _row('half lunge', _lunge(base, side: 'right', depth: 0.6));
    final wideStance = _with(base, {
      'leftKnee': const Offset(0.34, 0.77),
      'rightKnee': const Offset(0.66, 0.77),
      'leftAnkle': const Offset(0.30, 0.95),
      'rightAnkle': const Offset(0.70, 0.95),
    });
    _row('wide straight legs', wideStance);
    _row('lunge s0.6', transformPose(_lunge(base, side: 'right'), scale: 0.6));
    _row('lunge s1.4', transformPose(_lunge(base, side: 'right'), scale: 1.4));

    _section('BURPEES');
    final handsUp = _raiseArms(base, 0.8);
    _row('stand hands up', handsUp);
    _row('stand hands at sides', base);
    final handsDown = _with(_squatDepth(base, 0.9), {
      'leftWrist': const Offset(0.42, 0.78),
      'rightWrist': const Offset(0.58, 0.78),
      'leftElbow': const Offset(0.42, 0.60),
      'rightElbow': const Offset(0.58, 0.60),
    });
    _row('squat+hands down', handsDown);
    _row('squat+hands up', _with(_squatDepth(base, 0.9), {
      'leftWrist': const Offset(0.30, 0.30),
      'rightWrist': const Offset(0.70, 0.30),
    }));
    for (final s in [0.6, 1.0, 1.4]) {
      _row('handsDown s$s', transformPose(handsDown, scale: s));
    }

    _section('HIGH KNEES');
    _row('left knee up', _kneeLift(base, side: 'left', lift: 1));
    _row('right knee up', _kneeLift(base, side: 'right', lift: 1));
    _row('knee half up', _kneeLift(base, side: 'left', lift: 0.5));
    _row('march lift 0.7', _kneeLift(base, side: 'left', lift: 0.7));
    _row('mid-swap (both mid)', _kneeLift(_kneeLift(base, side: 'left', lift: 0.5), side: 'right', lift: 0.5));
    for (final s in [0.6, 1.0, 1.4]) {
      _row('kneeup s$s', transformPose(_kneeLift(base, side: 'left', lift: 1), scale: s));
    }

    _section('BUTT KICKS');
    _row('left heel up', _heelKick(base, side: 'left', kick: 1));
    _row('right heel up', _heelKick(base, side: 'right', kick: 1));
    _row('heel half', _heelKick(base, side: 'left', kick: 0.5));
    _row('knee up confuser', _kneeLift(base, side: 'left', lift: 1));

    _section('LATERAL STEPS');
    _row('neutral', base);
    _row('right out', _lateralStep(base, side: 'right'));
    _row('left out', _lateralStep(base, side: 'left'));
    _row('both out', _lateralStep(_lateralStep(base, side: 'left'), side: 'right'));
    _row('right half', _lateralStep(base, side: 'right', out: 0.10));

    _section('CALF RAISES');
    _row('flat', base);
    _row('on toes', _calfRaise(base, 1.0));
    _row('toes s0.6', transformPose(_calfRaise(base, 1.0), scale: 0.6));

    _section('PROPORTION WARP sanity');
    _row('legs-15%', warpProportions(base, legs: 0.85));
    _row('legs+15%', warpProportions(base, legs: 1.15));
    _row('torso-15%', warpProportions(base, torso: 0.85));
    _row('torso+15%', warpProportions(base, torso: 1.15));

    _section('PREVIEW DEMO KEYFRAMES');
    for (final activity in [
      AiMotionActivity.armRaises,
      AiMotionActivity.jumpingJacks,
      AiMotionActivity.deepSquats,
      AiMotionActivity.lunges,
      AiMotionActivity.highKnees,
      AiMotionActivity.jumpSquats,
      AiMotionActivity.lungeJumps,
    ]) {
      final keys = demoPoseMapsFor(activity);
      if (keys == null) {
        print('${activity.name}: no demo');
        continue;
      }
      for (var i = 0; i < keys.length; i++) {
        _row('${activity.name}[$i]', keys[i]);
      }
    }
  });
}
