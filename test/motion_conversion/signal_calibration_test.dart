// Calibration probe for Batch B conversion thresholds.
//
// Prints, for every canonical generator pose, the exact scalar signals the
// native validator consumes (via PoseFeatureExtractor) next to the remote
// derived features (RemotePoseFeatures) the declarative specs will use. Used
// to pick predicate thresholds with measurable margin — the printed table is
// the evidence behind each spec constant.
//
// Run: flutter test test/motion_conversion/signal_calibration_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/remote_pose_features.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';

NuvoPoseFrame _f(CleanPose pose) => frameOf(pose, 0);

double _sr(
  NuvoPoseFrame f,
  String a,
  String b,
  String ra,
  String rb,
) =>
    RemotePoseFeatures.segmentRatio(
      a: f.point(a),
      b: f.point(b),
      refA: f.point(ra),
      refB: f.point(rb),
    ) ??
    double.nan;

double _ang(NuvoPoseFrame f, String a, String b, String c) =>
    RemotePoseFeatures.angle(a: f.point(a), b: f.point(b), c: f.point(c)) ??
    double.nan;

String _n(double v) => v.isNaN ? 'null' : v.toStringAsFixed(3);

void _report(String name, CleanPose pose) {
  final f = _f(pose);
  final fx = PoseFeatureExtractor(f);
  // ignore: avoid_print
  print(
    '$name: hipToKnee=${_n(fx.hipToKneeRatio())} '
    'ankleW/bodyW=${_n(fx.ankleWidth / fx.bodyWidth)} '
    'kneeSep/hipW=${_n((f.point('leftKnee')!.x - f.point('rightKnee')!.x).abs() / fx.hipWidth)} '
    'kneeL=${_n(fx.kneeAngle(left: true))} kneeR=${_n(fx.kneeAngle(left: false))} '
    'elbowL=${_n(fx.elbowAngle(left: true))} elbowR=${_n(fx.elbowAngle(left: false))} '
    'wristsUp=${fx.wristsAboveShoulders} wristsNear=${fx.wristsNearBody} '
    '| segRatio(hip,knee) L=${_n(_sr(f, 'leftHip', 'leftKnee', 'leftShoulder', 'leftHip'))} '
    'R=${_n(_sr(f, 'rightHip', 'rightKnee', 'rightShoulder', 'rightHip'))} '
    'ankleW/shoulderW=${_n(_sr(f, 'leftAnkle', 'rightAnkle', 'leftShoulder', 'rightShoulder'))} '
    'ankleW/hipW=${_n(_sr(f, 'leftAnkle', 'rightAnkle', 'leftHip', 'rightHip'))} '
    'kneeSep/shoulderW=${_n(_sr(f, 'leftKnee', 'rightKnee', 'leftShoulder', 'rightShoulder'))} '
    'kneeSep/hipW_euclid=${_n(_sr(f, 'leftKnee', 'rightKnee', 'leftHip', 'rightHip'))} '
    'angle(W,S,H) L=${_n(_ang(f, 'leftWrist', 'leftShoulder', 'leftHip'))} '
    'R=${_n(_ang(f, 'rightWrist', 'rightShoulder', 'rightHip'))} '
    'segRatio(S,W)/torso L=${_n(_sr(f, 'leftShoulder', 'leftWrist', 'leftShoulder', 'leftHip'))} '
    'R=${_n(_sr(f, 'rightShoulder', 'rightWrist', 'rightShoulder', 'rightHip'))}',
  );
}

void main() {
  test('print calibration table', () {
    _report('frontStanding', frontStanding());
    for (final d in [0.2, 0.4, 0.6, 0.8, 1.0]) {
      _report('squat d=$d', squatAt(d));
    }
    _report('sumoStanding', sumoStanding());
    _report('sumoDeep', sumoAt(1.0));
    _report('squatJackClosed', squatJackClosed());
    _report('squatJackOpen d=0.6', squatJackOpen(0.6));
    _report('squatJackOpen d=1.0', squatJackOpen(1.0));
    _report('sideLungeLeft', sideLunge('left'));
    _report('sideLungeRight', sideLunge('right'));
    for (final b in [0.0, 0.4, 0.7, 1.0]) {
      _report('pushup b=$b', pushupAt(b));
    }
    _report('plank', plankAt());
    _report('plankSag', plankAt(sag: 0.08));
    _report('plankKnees', plankAt(kneeBend: 1.0));
    _report('gaitLeft', gaitPose('left'));
    _report('gaitRight', gaitPose('right'));
    _report('climberLeft', mountainClimberPose('left'));
    _report('climberRight', mountainClimberPose('right'));
  });
}
