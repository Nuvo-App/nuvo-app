import 'dart:math';

import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// A realistic phone-pose replay harness. A "clean" pose is a `Map<String,
/// (double x, double y)>` in normalized [0,1] screen space. Feed a schedule of
/// clean poses through [RealisticReplay] and it applies the distortions a real
/// ML Kit stream shows: per-joint jitter, confidence wobble, short dropout,
/// uneven left/right visibility, camera scale drift, translation, asymmetric
/// human execution, and a variable 10–20 FPS frame clock.
///
/// The bar for a verifier is: it counts the intended reps through this, at
/// slow / normal / fast tempo, at low FPS — not just on the clean poses.

typedef CleanPose = Map<String, Point<double>>;

Point<double> p(double x, double y) => Point(x, y);

class PoseNoise {
  const PoseNoise({
    this.jitter = 0.006,
    this.confBase = 0.86,
    this.confWobble = 0.12,
    this.dropoutChance = 0.05,
    this.dropoutMaxFrames = 4,
    this.weakSideChance = 0.15,
    this.scaleDrift = 0.05,
    this.translateDrift = 0.03,
    this.asymmetry = 0.12,
    this.fpsMin = 10,
    this.fpsMax = 20,
  });

  /// Idealised, low-noise stream — for a "does the signal exist at all" check.
  static const clean = PoseNoise(
    jitter: 0.002,
    confWobble: 0.03,
    dropoutChance: 0,
    weakSideChance: 0,
    scaleDrift: 0.0,
    translateDrift: 0.0,
    asymmetry: 0.0,
    fpsMin: 30,
    fpsMax: 30,
  );

  /// A rough phone session — the acceptance bar.
  static const phone = PoseNoise();

  /// A bad phone session — a stretch goal, not a hard requirement.
  static const harsh = PoseNoise(
    jitter: 0.012,
    confWobble: 0.2,
    dropoutChance: 0.1,
    dropoutMaxFrames: 6,
    weakSideChance: 0.28,
    scaleDrift: 0.09,
    translateDrift: 0.06,
    asymmetry: 0.22,
    fpsMin: 8,
    fpsMax: 16,
  );

  final double jitter;
  final double confBase;
  final double confWobble;
  final double dropoutChance;
  final int dropoutMaxFrames;
  final double weakSideChance;
  final double scaleDrift;
  final double translateDrift;
  final double asymmetry;
  final int fpsMin;
  final int fpsMax;
}

class RealisticReplay {
  RealisticReplay(this.noise, {int seed = 7}) : _rng = Random(seed);

  final PoseNoise noise;
  final Random _rng;

  int _t = 0;
  int _dropoutLeft = 0;
  String? _weakSide;
  int _weakLeft = 0;
  final _leftJoints = <String>{'leftShoulder', 'leftHip', 'leftKnee',
      'leftAnkle', 'leftWrist', 'leftElbow', 'leftHeel'};

  double _j() => (_rng.nextDouble() * 2 - 1) * noise.jitter;

  /// Build frames for [holds] repeats of [pose]. Poses flow in the order given.
  List<NuvoPoseFrame> stream(List<({CleanPose pose, int holds})> schedule) {
    final frames = <NuvoPoseFrame>[];
    var phase = 0.0;
    for (final step in schedule) {
      for (var i = 0; i < step.holds; i++) {
        phase += 1;
        frames.add(_frame(step.pose, phase));
      }
    }
    return frames;
  }

  NuvoPoseFrame _frame(CleanPose clean, double phase) {
    // Variable FPS clock.
    final fps = noise.fpsMin +
        _rng.nextInt((noise.fpsMax - noise.fpsMin).clamp(0, 60) + 1);
    _t += (1000 / fps).round();

    // Slow camera scale + translation drift.
    final scale = 1.0 + sin(phase / 40) * noise.scaleDrift;
    final dx = sin(phase / 33) * noise.translateDrift;
    final dy = cos(phase / 29) * noise.translateDrift;

    // Occasional short full dropout of one lower-body joint.
    if (_dropoutLeft <= 0 && _rng.nextDouble() < noise.dropoutChance) {
      _dropoutLeft = 1 + _rng.nextInt(noise.dropoutMaxFrames);
      _droppedJoint = ['leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle',
          'leftHip', 'rightHip'][_rng.nextInt(6)];
    }

    // A weak side (one half of the body low-confidence for a stretch).
    if (_weakLeft <= 0 && _rng.nextDouble() < noise.weakSideChance) {
      _weakLeft = 4 + _rng.nextInt(10);
      _weakSide = _rng.nextBool() ? 'left' : 'right';
    }

    final out = <String, NuvoPosePoint>{};
    const cx = 0.5, cy = 0.5;
    for (final e in clean.entries) {
      if (_dropoutLeft > 0 && e.key == _droppedJoint) continue;
      // Asymmetric execution: nudge the left half of the body a touch.
      final asym = _leftJoints.contains(e.key)
          ? sin(phase / 3) * noise.asymmetry * 0.04
          : 0.0;
      final sx = cx + (e.value.x - cx) * scale + dx + _j() + asym;
      final sy = cy + (e.value.y - cy) * scale + dy + _j();
      var conf = noise.confBase +
          (_rng.nextDouble() * 2 - 1) * noise.confWobble;
      if (_weakLeft > 0 &&
          _weakSide != null &&
          e.key.toLowerCase().startsWith(_weakSide!)) {
        conf -= 0.35;
      }
      out[e.key] = NuvoPosePoint(
        x: sx.clamp(0.0, 1.0),
        y: sy.clamp(0.0, 1.0),
        z: 0,
        likelihood: conf.clamp(0.0, 1.0),
      );
    }
    if (_dropoutLeft > 0) _dropoutLeft--;
    if (_weakLeft > 0) _weakLeft--;

    return NuvoPoseFrame(
      points: out,
      imageWidth: 1000,
      imageHeight: 1000,
      createdAt: DateTime.fromMillisecondsSinceEpoch(_t),
    );
  }

  String _droppedJoint = 'leftKnee';
}
