import 'package:nuvo/features/races/data/ai_motion_models.dart';

NuvoPoseFrame neutralStandingPose({
  double dx = 0,
  double dy = 0,
  double scale = 1,
  DateTime? createdAt,
  Set<String> missing = const {},
  Map<String, double> likelihoods = const {},
}) {
  return _frame(
    {
      'nose': _p(0.50, 0.16),
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftElbow': _p(0.34, 0.47),
      'rightElbow': _p(0.66, 0.47),
      'leftWrist': _p(0.33, 0.64),
      'rightWrist': _p(0.67, 0.64),
      'leftHip': _p(0.42, 0.57),
      'rightHip': _p(0.58, 0.57),
      'leftKnee': _p(0.43, 0.76),
      'rightKnee': _p(0.57, 0.76),
      'leftAnkle': _p(0.43, 0.94),
      'rightAnkle': _p(0.57, 0.94),
    },
    dx: dx,
    dy: dy,
    scale: scale,
    createdAt: createdAt,
    missing: missing,
    likelihoods: likelihoods,
  );
}

NuvoPoseFrame armsOverheadPose({
  double dx = 0,
  double dy = 0,
  double scale = 1,
  DateTime? createdAt,
}) {
  return _frame(
    {
      'nose': _p(0.50, 0.16),
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftElbow': _p(0.34, 0.16),
      'rightElbow': _p(0.66, 0.16),
      'leftWrist': _p(0.31, 0.04),
      'rightWrist': _p(0.69, 0.04),
      'leftHip': _p(0.42, 0.57),
      'rightHip': _p(0.58, 0.57),
      'leftKnee': _p(0.43, 0.76),
      'rightKnee': _p(0.57, 0.76),
      'leftAnkle': _p(0.43, 0.94),
      'rightAnkle': _p(0.57, 0.94),
    },
    dx: dx,
    dy: dy,
    scale: scale,
    createdAt: createdAt,
  );
}

NuvoPoseFrame handsNearKneesPose() {
  return _frame({
    'nose': _p(0.50, 0.17),
    'leftShoulder': _p(0.38, 0.32),
    'rightShoulder': _p(0.62, 0.32),
    'leftElbow': _p(0.39, 0.52),
    'rightElbow': _p(0.61, 0.52),
    'leftWrist': _p(0.43, 0.73),
    'rightWrist': _p(0.57, 0.73),
    'leftHip': _p(0.42, 0.58),
    'rightHip': _p(0.58, 0.58),
    'leftKnee': _p(0.43, 0.77),
    'rightKnee': _p(0.57, 0.77),
    'leftAnkle': _p(0.43, 0.94),
    'rightAnkle': _p(0.57, 0.94),
  });
}

NuvoPoseFrame leftArmRaisedPose({double dx = 0, double dy = 0}) {
  return _frame(
    {
      'nose': _p(0.50, 0.16),
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftElbow': _p(0.34, 0.15),
      'rightElbow': _p(0.66, 0.47),
      'leftWrist': _p(0.31, 0.04),
      'rightWrist': _p(0.67, 0.64),
      'leftHip': _p(0.42, 0.57),
      'rightHip': _p(0.58, 0.57),
      'leftKnee': _p(0.43, 0.76),
      'rightKnee': _p(0.57, 0.76),
      'leftAnkle': _p(0.43, 0.94),
      'rightAnkle': _p(0.57, 0.94),
    },
    dx: dx,
    dy: dy,
  );
}

NuvoPoseFrame rightArmRaisedPose({double dx = 0, double dy = 0}) {
  return _frame(
    {
      'nose': _p(0.50, 0.16),
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftElbow': _p(0.34, 0.47),
      'rightElbow': _p(0.66, 0.15),
      'leftWrist': _p(0.33, 0.64),
      'rightWrist': _p(0.69, 0.04),
      'leftHip': _p(0.42, 0.57),
      'rightHip': _p(0.58, 0.57),
      'leftKnee': _p(0.43, 0.76),
      'rightKnee': _p(0.57, 0.76),
      'leftAnkle': _p(0.43, 0.94),
      'rightAnkle': _p(0.57, 0.94),
    },
    dx: dx,
    dy: dy,
  );
}

NuvoPoseFrame _frame(
  Map<String, _FixturePoint> points, {
  double dx = 0,
  double dy = 0,
  double scale = 1,
  DateTime? createdAt,
  Set<String> missing = const {},
  Map<String, double> likelihoods = const {},
}) {
  final transformed = <String, NuvoPosePoint>{};
  for (final entry in points.entries) {
    if (missing.contains(entry.key)) continue;
    final point = entry.value;
    transformed[entry.key] = NuvoPosePoint(
      x: 0.5 + (point.x - 0.5) * scale + dx,
      y: 0.5 + (point.y - 0.5) * scale + dy,
      z: 0,
      likelihood: likelihoods[entry.key] ?? 0.95,
    );
  }
  return NuvoPoseFrame(
    points: transformed,
    imageWidth: 1000,
    imageHeight: 1000,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
  );
}

_FixturePoint _p(double x, double y) => _FixturePoint(x, y);

class _FixturePoint {
  const _FixturePoint(this.x, this.y);

  final double x;
  final double y;
}
