import 'dart:math' as math;
import 'replay_fixture.dart';

/// Generates synthetic pose fixtures that simulate real-world conditions:
/// - ML Kit noise (jitter, confidence variation)
/// - Frame rate variation (dropped frames, timing gaps)
/// - Ankle landmark loss during jumps
/// - Imperfect squat depth
/// - Brief airborne phases (2-3 frames)
///
/// TECH DEBT: These are synthetic, not from real video. They simulate
/// known failure modes from the phone testing report. Real data should
/// be ingested via the fixture format when available.
class SyntheticFixtureFactory {
  SyntheticFixtureFactory({int? seed}) : _rng = math.Random(seed);

  final math.Random _rng;

  // Base poses — calibrated to match existing test fixture scale:
  //   shoulderY = 0.30, hipY = 0.50 → torsoHeight = 0.20
  //   Standing: kneeY = 0.72 → hipToKneeRatio = 1.10 > 0.86 ✓
  //   Squat: hipY = 0.60, kneeY = 0.60 → hipToKneeRatio = 0.00 < 0.58 ✓
  //   Airborne: ankles rise from 0.90 → 0.84 (rise=0.06 > flightThreshold=0.036)
  //   groundedTolerance = 0.020

  Map<String, RecordedLandmark> _standing({double noise = 0.005}) =>
      _pose(
        leftShoulder: (0.40, 0.30), rightShoulder: (0.60, 0.30),
        leftHip: (0.42, 0.50), rightHip: (0.58, 0.50),
        leftKnee: (0.43, 0.72), rightKnee: (0.57, 0.72),
        leftAnkle: (0.47, 0.90), rightAnkle: (0.53, 0.90),
        noise: noise,
      );

  Map<String, RecordedLandmark> _squat({double noise = 0.005}) =>
      _pose(
        leftShoulder: (0.40, 0.30), rightShoulder: (0.60, 0.30),
        leftHip: (0.42, 0.60), rightHip: (0.58, 0.60),
        leftKnee: (0.43, 0.60), rightKnee: (0.57, 0.60),
        leftAnkle: (0.47, 0.90), rightAnkle: (0.53, 0.90),
        noise: noise,
      );

  Map<String, RecordedLandmark> _airborne({double noise = 0.005}) =>
      _pose(
        leftShoulder: (0.40, 0.25), rightShoulder: (0.60, 0.25),
        leftHip: (0.42, 0.42), rightHip: (0.58, 0.42),
        leftKnee: (0.43, 0.58), rightKnee: (0.57, 0.58),
        leftAnkle: (0.47, 0.78), rightAnkle: (0.53, 0.78),
        noise: noise,
      );

  /// Partial squat — hipToKneeRatio ≈ 0.75 (between 0.58 and 0.86, NOT squat).
  /// Shallow squat that shouldn't trigger the squat condition even with noise.
  Map<String, RecordedLandmark> _partialSquat({double noise = 0.005}) =>
      _pose(
        leftShoulder: (0.40, 0.30), rightShoulder: (0.60, 0.30),
        leftHip: (0.42, 0.53), rightHip: (0.58, 0.53),
        leftKnee: (0.43, 0.68), rightKnee: (0.57, 0.68),
        leftAnkle: (0.47, 0.90), rightAnkle: (0.53, 0.90),
        noise: noise,
      );

  /// Plain vertical jump — standing body with ankles risen, no squat, no tuck.
  /// hipToKneeRatio = 1.10 (same as standing) — won't match SQUAT, so the
  /// sequence STANDING → AIRBORNE never starts because SQUAT is required first.
  Map<String, RecordedLandmark> _jump({double noise = 0.005}) =>
      _pose(
        leftShoulder: (0.40, 0.30), rightShoulder: (0.60, 0.30),
        leftHip: (0.42, 0.50), rightHip: (0.58, 0.50),
        leftKnee: (0.43, 0.72), rightKnee: (0.57, 0.72),
        leftAnkle: (0.47, 0.84), rightAnkle: (0.53, 0.84),
        noise: noise,
      );

  Map<String, RecordedLandmark> _jackOpen({double noise = 0.005}) =>
      _pose(
        leftShoulder: (0.40, 0.30), rightShoulder: (0.60, 0.30),
        leftHip: (0.42, 0.50), rightHip: (0.58, 0.50),
        leftKnee: (0.43, 0.72), rightKnee: (0.57, 0.72),
        leftAnkle: (0.25, 0.90), rightAnkle: (0.75, 0.90),
        leftWrist: (0.30, 0.20), rightWrist: (0.70, 0.20),
        noise: noise,
      );

  Map<String, RecordedLandmark> _jackClosed({double noise = 0.005}) =>
      _pose(
        leftShoulder: (0.40, 0.30), rightShoulder: (0.60, 0.30),
        leftHip: (0.42, 0.50), rightHip: (0.58, 0.50),
        leftKnee: (0.43, 0.72), rightKnee: (0.57, 0.72),
        leftAnkle: (0.47, 0.90), rightAnkle: (0.53, 0.90),
        leftWrist: (0.44, 0.35), rightWrist: (0.56, 0.35),
        noise: noise,
      );

  Map<String, RecordedLandmark> _pose({
    required (double, double) leftShoulder,
    required (double, double) rightShoulder,
    required (double, double) leftHip,
    required (double, double) rightHip,
    required (double, double) leftKnee,
    required (double, double) rightKnee,
    required (double, double) leftAnkle,
    required (double, double) rightAnkle,
    (double, double)? leftWrist,
    (double, double)? rightWrist,
    double noise = 0.0,
  }) {
    final m = <String, RecordedLandmark>{};
    m['leftShoulder'] = _lm(leftShoulder, noise);
    m['rightShoulder'] = _lm(rightShoulder, noise);
    m['leftHip'] = _lm(leftHip, noise);
    m['rightHip'] = _lm(rightHip, noise);
    m['leftKnee'] = _lm(leftKnee, noise);
    m['rightKnee'] = _lm(rightKnee, noise);
    m['leftAnkle'] = _lm(leftAnkle, noise);
    m['rightAnkle'] = _lm(rightAnkle, noise);
    if (leftWrist != null) m['leftWrist'] = _lm(leftWrist, noise);
    if (rightWrist != null) m['rightWrist'] = _lm(rightWrist, noise);
    return m;
  }

  RecordedLandmark _lm((double, double) pos, double noise) {
    final (x, y) = pos;
    final jx = noise > 0 ? (_rng.nextDouble() - 0.5) * noise * 2 : 0.0;
    final jy = noise > 0 ? (_rng.nextDouble() - 0.5) * noise * 2 : 0.0;
    return RecordedLandmark(
      (x + jx).clamp(0.0, 1.0),
      (y + jy).clamp(0.0, 1.0),
      0.0,
      _confidence(),
    );
  }

  double _confidence() => 0.85 + _rng.nextDouble() * 0.15;

  /// Simulates ankle landmark loss with given probability PER ANKLE.
  /// This is more realistic than dropping both at once — ML Kit typically
  /// loses one ankle before the other.
  Map<String, RecordedLandmark> _maybeDropAnkles(
    Map<String, RecordedLandmark> pose,
    double probabilityPerAnkle,
  ) {
    final copy = Map<String, RecordedLandmark>.from(pose);
    if (_rng.nextDouble() < probabilityPerAnkle) {
      copy.remove('leftAnkle');
    }
    if (_rng.nextDouble() < probabilityPerAnkle) {
      copy.remove('rightAnkle');
    }
    return copy;
  }

  RecordedFrame _frame(Map<String, RecordedLandmark> landmarks, int index) =>
      RecordedFrame(landmarks: landmarks, frameIndex: index);

  // === POSITIVE FIXTURES: Jump Squats ===

  /// Clean jump squat: 3 reps with ideal form.
  ReplayFixture cleanJumpSquat3Reps({String id = 'jsq_clean_3'}) {
    final frames = <RecordedFrame>[];
    var idx = 0;
    for (var rep = 0; rep < 3; rep++) {
      // Standing (8 frames for baseline + STANDING stability)
      for (var i = 0; i < 8; i++) {
        frames.add(_frame(_standing(), idx++));
      }
      // Squat (3 frames)
      for (var i = 0; i < 3; i++) {
        frames.add(_frame(_squat(), idx++));
      }
      // Airborne (2 frames)
      for (var i = 0; i < 2; i++) {
        frames.add(_frame(_airborne(), idx++));
      }
      // Landing (3 frames)
      for (var i = 0; i < 3; i++) {
        frames.add(_frame(_standing(), idx++));
      }
    }
    return _fixture(id, 'jump_squats', 3, true, frames, 'clean_3rep');
  }

  /// Noisy jump squat: 3 reps with realistic ML Kit noise.
  /// - Higher coordinate jitter
  /// - Ankle dropout during airborne
  /// - Confidence variation
  /// - Occasional dropped frames
  ReplayFixture noisyJumpSquat3Reps({String id = 'jsq_noisy_3'}) {
    final frames = <RecordedFrame>[];
    var idx = 0;
    for (var rep = 0; rep < 3; rep++) {
      // Standing (8 frames, with noise)
      for (var i = 0; i < 8; i++) {
        if (_rng.nextDouble() > 0.08) {
          frames.add(_frame(_standing(noise: 0.015), idx));
        }
        idx++;
      }
      // Squat (3 frames, with noise)
      for (var i = 0; i < 3; i++) {
        frames.add(_frame(_squat(noise: 0.015), idx++));
      }
      // Airborne (3 frames, with per-ankle dropout)
      for (var i = 0; i < 3; i++) {
        var pose = _airborne(noise: 0.020);
        pose = _maybeDropAnkles(pose, 0.20);
        frames.add(_frame(pose, idx++));
      }
      // Landing (3 frames, with noise)
      for (var i = 0; i < 3; i++) {
        frames.add(_frame(_standing(noise: 0.015), idx++));
      }
    }
    return _fixture(id, 'jump_squats', 3, true, frames, 'noisy_3rep');
  }

  /// Very noisy jump squat: simulates worst-case phone conditions.
  /// - High jitter
  /// - Frequent ankle dropout (50%)
  /// - Low confidence
  /// - Frame drops
  /// - Only 1-2 airborne frames (brief flight)
  ReplayFixture veryNoisyJumpSquat2Reps({String id = 'jsq_very_noisy_2'}) {
    final frames = <RecordedFrame>[];
    var idx = 0;
    for (var rep = 0; rep < 2; rep++) {
      // Standing (6 frames — shorter baseline)
      for (var i = 0; i < 6; i++) {
        if (_rng.nextDouble() > 0.12) {
          final pose = _standing(noise: 0.025);
          frames.add(_frame(_lowConfidence(pose), idx));
        }
        idx++;
      }
      // Squat (2 frames — may not hit 3 stableFrames)
      for (var i = 0; i < 2; i++) {
        frames.add(_frame(_lowConfidence(_squat(noise: 0.025)), idx++));
      }
      // Airborne (1-2 frames — very brief)
      final airFrames = _rng.nextInt(2) + 1;
      for (var i = 0; i < airFrames; i++) {
        var pose = _airborne(noise: 0.030);
        pose = _maybeDropAnkles(pose, 0.50);
        frames.add(_frame(_lowConfidence(pose), idx++));
      }
      // Landing (2 frames — may not hit 3 stableFrames)
      for (var i = 0; i < 2; i++) {
        frames.add(_frame(_lowConfidence(_standing(noise: 0.025)), idx++));
      }
    }
    return _fixture(id, 'jump_squats', 2, true, frames, 'very_noisy_2rep');
  }

  /// Single rep jump squat with minimal frames.
  ReplayFixture minimalJumpSquat1Rep({String id = 'jsq_minimal_1'}) {
    final frames = <RecordedFrame>[];
    var idx = 0;
    // Standing (5 frames — just enough for baseline)
    for (var i = 0; i < 5; i++) {
      frames.add(_frame(_standing(noise: 0.010), idx++));
    }
    // Squat (3 frames)
    for (var i = 0; i < 3; i++) {
      frames.add(_frame(_squat(noise: 0.010), idx++));
    }
    // Airborne (2 frames)
    for (var i = 0; i < 2; i++) {
      frames.add(_frame(_airborne(noise: 0.010), idx++));
    }
    // Landing (3 frames)
    for (var i = 0; i < 3; i++) {
      frames.add(_frame(_standing(noise: 0.010), idx++));
    }
    return _fixture(id, 'jump_squats', 1, true, frames, 'minimal_1rep');
  }

  // === NEGATIVE / CONFUSER FIXTURES ===

  /// Normal squat: 3 reps (should NOT count as jump squat).
  ReplayFixture normalSquat3Reps({String id = 'squat_confuser_3'}) {
    final frames = <RecordedFrame>[];
    var idx = 0;
    for (var rep = 0; rep < 3; rep++) {
      for (var i = 0; i < 8; i++) {
        frames.add(_frame(_standing(noise: 0.010), idx++));
      }
      for (var i = 0; i < 3; i++) {
        frames.add(_frame(_squat(noise: 0.010), idx++));
      }
      // Return to standing (no airborne phase)
      for (var i = 0; i < 5; i++) {
        frames.add(_frame(_standing(noise: 0.010), idx++));
      }
    }
    return _fixture(id, 'jump_squats', 0, false, frames, 'normal_squat_confuser');
  }

  /// Plain vertical jump: 3 reps (should NOT count as jump squat).
  /// Has airborne but no squat phase.
  ReplayFixture plainJump3Reps({String id = 'jump_confuser_3'}) {
    final frames = <RecordedFrame>[];
    var idx = 0;
    for (var rep = 0; rep < 3; rep++) {
      for (var i = 0; i < 8; i++) {
        frames.add(_frame(_standing(noise: 0.010), idx++));
      }
      // No squat — go straight to airborne
      for (var i = 0; i < 2; i++) {
        frames.add(_frame(_jump(noise: 0.010), idx++));
      }
      for (var i = 0; i < 5; i++) {
        frames.add(_frame(_standing(noise: 0.010), idx++));
      }
    }
    return _fixture(id, 'jump_squats', 0, false, frames, 'plain_jump_confuser');
  }

  /// Jumping jacks: 3 reps (should NOT count as jump squat).
  ReplayFixture jumpingJacks3Reps({String id = 'jacks_confuser_3'}) {
    final frames = <RecordedFrame>[];
    var idx = 0;
    for (var rep = 0; rep < 3; rep++) {
      for (var i = 0; i < 4; i++) {
        frames.add(_frame(_jackClosed(noise: 0.010), idx++));
      }
      for (var i = 0; i < 4; i++) {
        frames.add(_frame(_jackOpen(noise: 0.010), idx++));
      }
      for (var i = 0; i < 4; i++) {
        frames.add(_frame(_jackClosed(noise: 0.010), idx++));
      }
    }
    return _fixture(id, 'jump_squats', 0, false, frames, 'jumping_jack_confuser');
  }

  /// Partial squat + jump: not deep enough squat (should NOT count).
  ReplayFixture partialSquatJump3Reps({String id = 'partial_confuser_3'}) {
    final frames = <RecordedFrame>[];
    var idx = 0;
    for (var rep = 0; rep < 3; rep++) {
      for (var i = 0; i < 8; i++) {
        frames.add(_frame(_standing(noise: 0.010), idx++));
      }
      for (var i = 0; i < 3; i++) {
        frames.add(_frame(_partialSquat(noise: 0.010), idx++));
      }
      for (var i = 0; i < 2; i++) {
        frames.add(_frame(_airborne(noise: 0.010), idx++));
      }
      for (var i = 0; i < 3; i++) {
        frames.add(_frame(_standing(noise: 0.010), idx++));
      }
    }
    return _fixture(id, 'jump_squats', 0, false, frames, 'partial_squat_confuser');
  }

  // === LUNGE JUMP FIXTURES ===

  /// Right lunge — matches existing test fixture coordinates.
  /// rightKneeAngle ≈ 113° < 120° (bent), leftKneeAngle ≈ 170° > 160° (straight).
  Map<String, RecordedLandmark> _rightLunge({double noise = 0.005}) => _pose(
        leftShoulder: (0.40, 0.30), rightShoulder: (0.60, 0.30),
        leftHip: (0.48, 0.50), rightHip: (0.52, 0.50),
        leftKnee: (0.35, 0.70), rightKnee: (0.78, 0.62),
        leftAnkle: (0.25, 0.90), rightAnkle: (0.78, 0.90),
        noise: noise,
      );

  /// Left lunge — matches existing test fixture coordinates.
  /// leftKneeAngle ≈ 113° < 120° (bent), rightKneeAngle ≈ 170° > 160° (straight).
  Map<String, RecordedLandmark> _leftLunge({double noise = 0.005}) => _pose(
        leftShoulder: (0.40, 0.30), rightShoulder: (0.60, 0.30),
        leftHip: (0.48, 0.50), rightHip: (0.52, 0.50),
        leftKnee: (0.22, 0.62), rightKnee: (0.65, 0.70),
        leftAnkle: (0.22, 0.90), rightAnkle: (0.75, 0.90),
        noise: noise,
      );

  /// Clean lunge jump: 2 reps alternating.
  ReplayFixture cleanLungeJump2Reps({String id = 'ljs_clean_2'}) {
    final frames = <RecordedFrame>[];
    var idx = 0;
    // Right lunge → air → left lunge (rep 1)
    for (var i = 0; i < 5; i++) frames.add(_frame(_standing(noise: 0.005), idx++));
    for (var i = 0; i < 3; i++) frames.add(_frame(_rightLunge(noise: 0.005), idx++));
    for (var i = 0; i < 2; i++) frames.add(_frame(_airborne(noise: 0.005), idx++));
    for (var i = 0; i < 3; i++) frames.add(_frame(_leftLunge(noise: 0.005), idx++));
    // Left lunge → air → right lunge (rep 2)
    for (var i = 0; i < 3; i++) frames.add(_frame(_leftLunge(noise: 0.005), idx++));
    for (var i = 0; i < 2; i++) frames.add(_frame(_airborne(noise: 0.005), idx++));
    for (var i = 0; i < 3; i++) frames.add(_frame(_rightLunge(noise: 0.005), idx++));
    return _fixture(id, 'lunge_jumps', 2, true, frames, 'clean_2rep');
  }

  /// Noisy lunge jump: 2 reps with realistic noise.
  ReplayFixture noisyLungeJump2Reps({String id = 'ljs_noisy_2'}) {
    final frames = <RecordedFrame>[];
    var idx = 0;
    for (var i = 0; i < 5; i++) {
      if (_rng.nextDouble() > 0.08) frames.add(_frame(_standing(noise: 0.015), idx));
      idx++;
    }
    for (var i = 0; i < 3; i++) frames.add(_frame(_rightLunge(noise: 0.015), idx++));
    for (var i = 0; i < 2; i++) {
      var pose = _airborne(noise: 0.020);
      pose = _maybeDropAnkles(pose, 0.30);
      frames.add(_frame(pose, idx++));
    }
    for (var i = 0; i < 3; i++) frames.add(_frame(_leftLunge(noise: 0.015), idx++));
    for (var i = 0; i < 3; i++) frames.add(_frame(_leftLunge(noise: 0.015), idx++));
    for (var i = 0; i < 2; i++) {
      var pose = _airborne(noise: 0.020);
      pose = _maybeDropAnkles(pose, 0.30);
      frames.add(_frame(pose, idx++));
    }
    for (var i = 0; i < 3; i++) frames.add(_frame(_rightLunge(noise: 0.015), idx++));
    return _fixture(id, 'lunge_jumps', 2, true, frames, 'noisy_2rep');
  }

  // === HELPER ===

  Map<String, RecordedLandmark> _lowConfidence(Map<String, RecordedLandmark> pose) {
    final out = <String, RecordedLandmark>{};
    for (final e in pose.entries) {
      out[e.key] = RecordedLandmark(
        e.value.x, e.value.y, e.value.z,
        (e.value.likelihood - 0.20).clamp(0.0, 1.0),
      );
    }
    return out;
  }

  ReplayFixture _fixture(
    String id,
    String movement,
    int reps,
    bool shouldMatch,
    List<RecordedFrame> frames,
    String label,
  ) {
    return ReplayFixture(
      id: id,
      movement: movement,
      expected: FixtureExpected(reps: reps, shouldMatch: shouldMatch),
      source: const FixtureSource(
        type: 'synthetic',
        name: 'nuvo_synthetic_factory',
        license: 'internal',
        reference: 'simulates ML Kit noise patterns from phone testing',
        extractor: 'synthetic_pose_generator',
        cameraView: 'front',
        qualityTier: 'synthetic',
      ),
      frames: frames,
      label: label,
      tags: ['synthetic', movement],
    );
  }

  /// Generates all base fixtures for the pilot.
  List<ReplayFixture> allPilotFixtures() {
    return [
      // Jump squat positives
      cleanJumpSquat3Reps(),
      noisyJumpSquat3Reps(),
      veryNoisyJumpSquat2Reps(),
      minimalJumpSquat1Rep(),
      // Jump squat confusers
      normalSquat3Reps(),
      plainJump3Reps(),
      jumpingJacks3Reps(),
      partialSquatJump3Reps(),
      // Lunge jump positives
      cleanLungeJump2Reps(),
      noisyLungeJump2Reps(),
    ];
  }
}
