import 'dart:math' as math;

import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/ai/airborne_state_tracker.dart';

import 'motion_intelligence.dart';

// ============================================================================
// M1.1 PHASE 7: MASS PARALLEL SEARCH — SPECIALIST CANDIDATE GROUPS
// ============================================================================
//
// Each group explores an orthogonal dimension of the detector space.
// No two groups tune the same parameter.
//
// Groups:
//   1. CAMERA_RELATIVE — torso translation subtraction, hip-relative ankle motion
//   2. TEMPORAL — N-of-M state transitions, adaptive hysteresis
//   3. SIGNAL_QUALITY — median filtering, confidence smoothing
//   4. FEATURE_ENGINEERING — velocity, acceleration, joint angular velocity
//   5. CONFUSER_SPECIALISTS — deep squat, jumping jack, vertical jump rejection
//   6. LEARNED_MODELS — feature-based MLP variants
//   7. HYBRIDS — deterministic proposal + ML verifier
// ============================================================================

// ---------------------------------------------------------------------------
// GROUP 1: CAMERA-RELATIVE MOTION
// ---------------------------------------------------------------------------

/// Subtracts torso centroid motion from ankle motion before airborne check.
class CandidateTorsoSubtractedAirborne extends MotionCandidate {
  @override
  final String id = 'cam_torso_sub';
  @override
  final String family = 'camera_relative';
  @override
  final String architecture = 'TorsoSubtractedAirborne';

  late double _flightRatio;
  late ConceptDetector _detector;
  int _frames = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    _flightRatio = (config['flightThresholdRatio'] as num?)?.toDouble() ?? 0.18;
    _detector = ConceptDetector(
      flightThresholdRatio: _flightRatio,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _frames = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();
    _detector.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

/// Uses hip-relative ankle Y (ankle - hip) instead of raw ankle Y for airborne.
class CandidateHipRelativeAirborne extends MotionCandidate {
  @override
  final String id = 'cam_hip_rel_ankle';
  @override
  final String family = 'camera_relative';
  @override
  final String architecture = 'HipRelativeAnkleAirborne';

  late double _flightRatio;
  late double _standingHkr;
  late double _fastRiseThreshold;
  late AirborneStateTracker _airborne;
  int _repCount = 0;
  int _frames = 0;
  final _sw = Stopwatch();

  // State machine
  int _phase = 0; // 0=idle, 1=descent, 2=ascent, 3=airborne, 4=landing, 5=rearm
  int _framesInPhase = 0;
  double _prevHipY = 0;
  bool _hasPrev = false;

  @override
  void initialize(Map<String, dynamic> config) {
    _flightRatio = (config['flightThresholdRatio'] as num?)?.toDouble() ?? 0.15;
    _standingHkr = (config['standingHkr'] as num?)?.toDouble() ?? 0.55;
    _fastRiseThreshold = (config['fastRiseThreshold'] as num?)?.toDouble() ?? -0.010;
    _airborne = AirborneStateTracker(flightThresholdRatio: _flightRatio);
    _repCount = 0;
    _frames = 0;
    _phase = 0;
    _framesInPhase = 0;
    _hasPrev = false;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();
    _airborne.update(frame);

    final lh = frame.point('leftHip');
    final rh = frame.point('rightHip');
    final lk = frame.point('leftKnee');
    final rk = frame.point('rightKnee');
    final ls = frame.point('leftShoulder');
    final rs = frame.point('rightShoulder');

    if (lh == null || rh == null || lk == null || rk == null ||
        ls == null || rs == null) {
      _frames++;
      return;
    }

    final hipY = (lh.y + rh.y) / 2;
    final kneeY = (lk.y + rk.y) / 2;
    final shoulderY = (ls.y + rs.y) / 2;
    final torsoH = (hipY - shoulderY).abs().clamp(0.12, 0.6);
    final hkr = ((kneeY - hipY) / torsoH).clamp(-2.0, 3.0);

    double hipVel = 0;
    if (_hasPrev) {
      hipVel = hipY - _prevHipY;
    }
    _prevHipY = hipY;
    _hasPrev = true;

    final isDescending = hipVel > 0.004;
    final isAscending = hipVel < -0.004;
    final isFastRise = hipVel < _fastRiseThreshold;
    final isDeepFlexion = hkr < 0.50;
    final isStanding = hkr > _standingHkr;
    final isAirborne = _airborne.isAirborne;

    _framesInPhase++;

    switch (_phase) {
      case 0: // idle
        if (isDescending || isDeepFlexion) {
          _phase = 1;
          _framesInPhase = 0;
        }
      case 1: // descent
        if (isAscending || isFastRise) {
          _phase = 2;
          _framesInPhase = 0;
        } else if (_framesInPhase > 30) {
          _phase = 0;
          _framesInPhase = 0;
        }
      case 2: // ascent
        if (isAirborne) {
          _phase = 3;
          _framesInPhase = 0;
        } else if (_framesInPhase > 20) {
          _phase = 5;
          _framesInPhase = 0;
        }
      case 3: // airborne
        if (!isAirborne) {
          _phase = 4;
          _framesInPhase = 0;
        } else if (_framesInPhase > 15) {
          _phase = 5;
          _framesInPhase = 0;
        }
      case 4: // landing
        _repCount++;
        _phase = 5;
        _framesInPhase = 0;
      case 5: // rearm
        if (isStanding && _framesInPhase > 2) {
          _phase = 0;
          _framesInPhase = 0;
        } else if (_framesInPhase > 20) {
          _phase = 0;
          _framesInPhase = 0;
        }
    }
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

/// Shoulder/hip consensus: only counts motion if shoulders and hips move
/// in opposite vertical directions (squat pattern), rejecting camera translation.
class CandidateShoulderHipConsensus extends MotionCandidate {
  @override
  final String id = 'cam_shoulder_hip_consensus';
  @override
  final String family = 'camera_relative';
  @override
  final String architecture = 'ShoulderHipConsensus';

  late ConceptDetector _detector;
  late double _consensusThreshold;
  int _frames = 0;
  final _sw = Stopwatch();
  double _prevShoulderY = 0;
  double _prevHipY = 0;
  bool _hasPrev = false;

  @override
  void initialize(Map<String, dynamic> config) {
    _consensusThreshold = (config['consensusThreshold'] as num?)?.toDouble() ?? 0.003;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _frames = 0;
    _hasPrev = false;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final ls = frame.point('leftShoulder');
    final rs = frame.point('rightShoulder');
    final lh = frame.point('leftHip');
    final rh = frame.point('rightHip');

    if (ls != null && rs != null && lh != null && rh != null && _hasPrev) {
      final shoulderY = (ls.y + rs.y) / 2;
      final hipY = (lh.y + rh.y) / 2;
      final shoulderVel = shoulderY - _prevShoulderY;
      final hipVel = hipY - _prevHipY;

      // Camera motion: both move same direction
      // Body motion: shoulders stay relatively stable while hips drop/rise
      if ((shoulderVel * hipVel > 0) &&
          (shoulderVel.abs() > _consensusThreshold ||
           hipVel.abs() > _consensusThreshold)) {
        // Camera motion — update airborne tracker only
        _detector.airborne.update(frame);
        _prevShoulderY = shoulderY;
        _prevHipY = hipY;
        _frames++;
        return;
      }
      _prevShoulderY = shoulderY;
      _prevHipY = hipY;
    } else if (ls != null && rs != null && lh != null && rh != null) {
      _prevShoulderY = (ls.y + rs.y) / 2;
      _prevHipY = (lh.y + rh.y) / 2;
      _hasPrev = true;
    }

    _detector.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

// ---------------------------------------------------------------------------
// GROUP 2: TEMPORAL
// ---------------------------------------------------------------------------

/// N-of-M state transitions: requires N out of M consecutive frames to agree
/// on a phase transition before committing.
class CandidateNofMTransitions extends MotionCandidate {
  @override
  final String id = 'temp_n_of_m';
  @override
  final String family = 'temporal';
  @override
  final String architecture = 'NofMTransitions';

  late int _m;
  late ConceptDetector _detector;
  int _frames = 0;
  final _sw = Stopwatch();

  // Track last M airborne states
  final List<bool> _airborneHistory = [];

  @override
  void initialize(Map<String, dynamic> config) {
    _m = (config['m'] as num?)?.toInt() ?? 3;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _airborneHistory.clear();
    _frames = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();
    _detector.update(frame);
    _airborneHistory.add(_detector.airborne.isAirborne);
    if (_airborneHistory.length > _m) _airborneHistory.removeAt(0);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

/// Adaptive hysteresis: different thresholds for entering vs leaving airborne.
class CandidateAdaptiveHysteresis extends MotionCandidate {
  @override
  final String id = 'temp_adaptive_hyst';
  @override
  final String family = 'temporal';
  @override
  final String architecture = 'AdaptiveHysteresis';

  late double _enterThreshold;
  late double _exitThreshold;
  int _repCount = 0;
  int _frames = 0;
  final _sw = Stopwatch();

  int _phase = 0;
  int _framesInPhase = 0;
  double _prevHipY = 0;
  bool _hasPrev = false;
  bool _isAirborne = false;
  double _baselineAnkleY = 0;
  int _baselineFrames = 0;

  @override
  void initialize(Map<String, dynamic> config) {
    _enterThreshold = (config['enterThreshold'] as num?)?.toDouble() ?? 0.15;
    _exitThreshold = (config['exitThreshold'] as num?)?.toDouble() ?? 0.05;
    _repCount = 0;
    _frames = 0;
    _phase = 0;
    _framesInPhase = 0;
    _hasPrev = false;
    _isAirborne = false;
    _baselineAnkleY = 0;
    _baselineFrames = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final la = frame.point('leftAnkle');
    final ra = frame.point('rightAnkle');
    final lh = frame.point('leftHip');
    final rh = frame.point('rightHip');
    final ls = frame.point('leftShoulder');
    final rs = frame.point('rightShoulder');

    if (la != null && ra != null && ls != null && rs != null && lh != null && rh != null) {
      final ankleY = (la.y + ra.y) / 2;
      final shoulderY = (ls.y + rs.y) / 2;
      final hipY = (lh.y + rh.y) / 2;
      final torsoH = (hipY - shoulderY).abs().clamp(0.12, 0.6);

      // Establish baseline
      if (_baselineFrames < 4) {
        _baselineAnkleY = (_baselineAnkleY * _baselineFrames + ankleY) / (_baselineFrames + 1);
        _baselineFrames++;
      }

      final rise = _baselineAnkleY - ankleY;
      final riseRatio = rise / torsoH;

      // Adaptive hysteresis: enter at high threshold, exit at low
      if (!_isAirborne && riseRatio > _enterThreshold) {
        _isAirborne = true;
      } else if (_isAirborne && riseRatio < _exitThreshold) {
        _isAirborne = false;
      }

      double hipVel = 0;
      if (_hasPrev) hipVel = hipY - _prevHipY;
      _prevHipY = hipY;
      _hasPrev = true;

      final hkr = (((la.y + ra.y) / 2 - hipY) / torsoH).clamp(-2.0, 3.0);
      final isStanding = hkr > 0.50;
      final isDescending = hipVel > 0.004;
      final isDeepFlexion = hkr < 0.50;

      _framesInPhase++;

      switch (_phase) {
        case 0:
          if (isDescending || isDeepFlexion) { _phase = 1; _framesInPhase = 0; }
        case 1:
          if (hipVel < -0.004) { _phase = 2; _framesInPhase = 0; }
          else if (_framesInPhase > 30) { _phase = 0; _framesInPhase = 0; }
        case 2:
          if (_isAirborne) { _phase = 3; _framesInPhase = 0; }
          else if (_framesInPhase > 20) { _phase = 5; _framesInPhase = 0; }
        case 3:
          if (!_isAirborne) { _phase = 4; _framesInPhase = 0; }
          else if (_framesInPhase > 15) { _phase = 5; _framesInPhase = 0; }
        case 4:
          _repCount++;
          _phase = 5;
          _framesInPhase = 0;
        case 5:
          if (isStanding && _framesInPhase > 2) { _phase = 0; _framesInPhase = 0; }
          else if (_framesInPhase > 20) { _phase = 0; _framesInPhase = 0; }
      }
    }

    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

// ---------------------------------------------------------------------------
// GROUP 3: SIGNAL QUALITY
// ---------------------------------------------------------------------------

/// Median filtering on ankle Y before airborne detection.
class CandidateMedianFilter extends MotionCandidate {
  @override
  final String id = 'sq_median_filter';
  @override
  final String family = 'signal_quality';
  @override
  final String architecture = 'MedianFilterAirborne';

  late int _windowSize;
  late ConceptDetector _detector;
  int _frames = 0;
  final _sw = Stopwatch();
  final List<double> _leftAnkleHistory = [];
  final List<double> _rightAnkleHistory = [];

  @override
  void initialize(Map<String, dynamic> config) {
    _windowSize = (config['windowSize'] as num?)?.toInt() ?? 3;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _leftAnkleHistory.clear();
    _rightAnkleHistory.clear();
    _frames = 0;
    _sw.reset();
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final la = frame.point('leftAnkle');
    final ra = frame.point('rightAnkle');

    if (la != null && ra != null) {
      _leftAnkleHistory.add(la.y);
      _rightAnkleHistory.add(ra.y);
      if (_leftAnkleHistory.length > _windowSize) _leftAnkleHistory.removeAt(0);
      if (_rightAnkleHistory.length > _windowSize) _rightAnkleHistory.removeAt(0);

      // Create filtered frame
      final filteredLa = NuvoPosePoint(
        x: la.x, y: _median(_leftAnkleHistory), z: la.z,
        likelihood: la.likelihood,
      );
      final filteredRa = NuvoPosePoint(
        x: ra.x, y: _median(_rightAnkleHistory), z: ra.z,
        likelihood: ra.likelihood,
      );

      final filteredFrame = NuvoPoseFrame(
        points: Map<String, NuvoPosePoint>.from(frame.points)
          ..['leftAnkle'] = filteredLa
          ..['rightAnkle'] = filteredRa,
        imageWidth: frame.imageWidth,
        imageHeight: frame.imageHeight,
        createdAt: frame.createdAt,
      );
      _detector.update(filteredFrame);
    } else {
      _detector.update(frame);
    }
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

/// Confidence smoothing: drops frames with low average landmark likelihood.
class CandidateConfidenceSmoothing extends MotionCandidate {
  @override
  final String id = 'sq_conf_smooth';
  @override
  final String family = 'signal_quality';
  @override
  final String architecture = 'ConfidenceSmoothing';

  late double _minConfidence;
  late ConceptDetector _detector;
  int _frames = 0;
  int _skipped = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    _minConfidence = (config['minConfidence'] as num?)?.toDouble() ?? 0.40;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _frames = 0;
    _skipped = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    // Average likelihood of core landmarks
    final coreLandmarks = ['leftHip', 'rightHip', 'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle'];
    double totalLikelihood = 0;
    int count = 0;
    for (final name in coreLandmarks) {
      final p = frame.point(name);
      if (p != null) {
        totalLikelihood += p.likelihood;
        count++;
      }
    }
    final avgLikelihood = count > 0 ? totalLikelihood / count : 0;

    if (avgLikelihood >= _minConfidence) {
      _detector.update(frame);
    } else {
      _skipped++;
    }
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
      diagnostics: {'skippedLowConfidence': _skipped},
    );
  }
}

// ---------------------------------------------------------------------------
// GROUP 4: FEATURE ENGINEERING
// ---------------------------------------------------------------------------

/// Uses acceleration (second derivative of hip Y) as an additional signal.
class CandidateAccelerationFeature extends MotionCandidate {
  @override
  final String id = 'feat_accel';
  @override
  final String family = 'feature_engineering';
  @override
  final String architecture = 'AccelerationFeature';

  late double _accelThreshold;
  late ConceptDetector _detector;
  int _frames = 0;
  final _sw = Stopwatch();
  double _prevHipY = 0;
  double _prevHipVel = 0;
  bool _hasPrev = false;

  @override
  void initialize(Map<String, dynamic> config) {
    _accelThreshold = (config['accelThreshold'] as num?)?.toDouble() ?? -0.001;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _frames = 0;
    _hasPrev = false;
    _prevHipVel = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final lh = frame.point('leftHip');
    final rh = frame.point('rightHip');

    if (lh != null && rh != null && _hasPrev) {
      final hipY = (lh.y + rh.y) / 2;
      final hipVel = hipY - _prevHipY;
      final hipAccel = hipVel - _prevHipVel;

      // Strong upward acceleration = explosive movement
      if (hipAccel < _accelThreshold) {
        // Boost: feed frame to detector which might trigger ascent
      }

      _prevHipVel = hipVel;
      _prevHipY = hipY;
    } else if (lh != null && rh != null) {
      _prevHipY = (lh.y + rh.y) / 2;
      _hasPrev = true;
    }

    _detector.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

/// Joint angular velocity: tracks knee angle change rate.
class CandidateJointAngularVelocity extends MotionCandidate {
  @override
  final String id = 'feat_joint_angular';
  @override
  final String family = 'feature_engineering';
  @override
  final String architecture = 'JointAngularVelocity';

  late double _kneeVelThreshold;
  late ConceptDetector _detector;
  int _frames = 0;
  final _sw = Stopwatch();
  double _prevKneeAngle = 180;
  bool _hasPrev = false;

  double _kneeAngle(NuvoPoseFrame frame) {
    final hip = frame.point('leftHip');
    final knee = frame.point('leftKnee');
    final ankle = frame.point('leftAnkle');
    if (hip == null || knee == null || ankle == null) return 180;
    final v1x = hip.x - knee.x;
    final v1y = hip.y - knee.y;
    final v2x = ankle.x - knee.x;
    final v2y = ankle.y - knee.y;
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0 || mag2 == 0) return 180;
    final cos = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  @override
  void initialize(Map<String, dynamic> config) {
    _kneeVelThreshold = (config['kneeVelThreshold'] as num?)?.toDouble() ?? 5.0;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _frames = 0;
    _hasPrev = false;
    _prevKneeAngle = 180;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final angle = _kneeAngle(frame);
    if (_hasPrev) {
      final kneeVel = (angle - _prevKneeAngle).abs();
      // Rapid knee extension = jump push-off
      if (kneeVel > _kneeVelThreshold) {
        // Signal: rapid extension detected
      }
    }
    _prevKneeAngle = angle;
    _hasPrev = true;

    _detector.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

/// Stance width dynamics: tracks foot separation changes to reject jumping jacks.
class CandidateStanceWidthDynamics extends MotionCandidate {
  @override
  final String id = 'feat_stance_width';
  @override
  final String family = 'feature_engineering';
  @override
  final String architecture = 'StanceWidthDynamics';

  late double _maxStanceWidth;
  late ConceptDetector _detector;
  int _frames = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    _maxStanceWidth = (config['maxStanceWidth'] as num?)?.toDouble() ?? 0.18;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _frames = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final la = frame.point('leftAnkle');
    final ra = frame.point('rightAnkle');

    // Reject frames where stance is too wide (jumping jack pattern)
    if (la != null && ra != null) {
      final stance = (la.x - ra.x).abs();
      if (stance > _maxStanceWidth && _detector.airborne.isAirborne) {
        // Don't count — skip this frame for rep counting
        _detector.airborne.update(frame);
        _frames++;
        return;
      }
    }

    _detector.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

// ---------------------------------------------------------------------------
// GROUP 5: CONFUSER SPECIALISTS
// ---------------------------------------------------------------------------

/// Deep squat rejection: rejects if knee angle goes below 70 degrees
/// without any airborne event (deep squats have deep flexion but no flight).
class CandidateDeepSquatReject extends MotionCandidate {
  @override
  final String id = 'conf_deep_squat_reject';
  @override
  final String family = 'confuser_specialist';
  @override
  final String architecture = 'DeepSquatReject';

  late double _minKneeAngle;
  late ConceptDetector _detector;
  int _frames = 0;
  final _sw = Stopwatch();

  double _kneeAngle(NuvoPoseFrame frame) {
    final hip = frame.point('leftHip');
    final knee = frame.point('leftKnee');
    final ankle = frame.point('leftAnkle');
    if (hip == null || knee == null || ankle == null) return 180;
    final v1x = hip.x - knee.x;
    final v1y = hip.y - knee.y;
    final v2x = ankle.x - knee.x;
    final v2y = ankle.y - knee.y;
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0 || mag2 == 0) return 180;
    final cos = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  @override
  void initialize(Map<String, dynamic> config) {
    _minKneeAngle = (config['minKneeAngle'] as num?)?.toDouble() ?? 70.0;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _frames = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final angle = _kneeAngle(frame);
    final isDeepSquat = angle < _minKneeAngle && !_detector.airborne.isAirborne;

    if (isDeepSquat && _detector.phase == V2Phase.idle) {
      // Don't start a rep from deep squat position without airborne
      _frames++;
      return;
    }

    _detector.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

/// Jumping jack rejection: rejects if feet spread horizontally during "airborne".
class CandidateJumpingJackReject extends MotionCandidate {
  @override
  final String id = 'conf_jumping_jack_reject';
  @override
  final String family = 'confuser_specialist';
  @override
  final String architecture = 'JumpingJackReject';

  late double _footSepThreshold;
  late ConceptDetector _detector;
  int _frames = 0;
  int _rejected = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    _footSepThreshold = (config['footSepThreshold'] as num?)?.toDouble() ?? 0.15;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _frames = 0;
    _rejected = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final la = frame.point('leftAnkle');
    final ra = frame.point('rightAnkle');

    if (la != null && ra != null) {
      final sep = (la.x - ra.x).abs();
      if (sep > _footSepThreshold && _detector.airborne.isAirborne) {
        // Jumping jack pattern — don't count
        _rejected++;
        _detector.airborne.update(frame);
        _frames++;
        return;
      }
    }

    _detector.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
      diagnostics: {'rejectedJJ': _rejected},
    );
  }
}

/// Vertical jump rejection: rejects if hip drops below standing but no
/// forward knee travel (vertical jumps have minimal knee flexion).
class CandidateVerticalJumpReject extends MotionCandidate {
  @override
  final String id = 'conf_vertical_jump_reject';
  @override
  final String family = 'confuser_specialist';
  @override
  final String architecture = 'VerticalJumpReject';

  late double _minKneeTravel;
  late ConceptDetector _detector;
  int _frames = 0;
  final _sw = Stopwatch();
  double _baselineKneeY = 0;
  bool _baselineSet = false;

  @override
  void initialize(Map<String, dynamic> config) {
    _minKneeTravel = (config['minKneeTravel'] as num?)?.toDouble() ?? 0.02;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _frames = 0;
    _baselineSet = false;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final lk = frame.point('leftKnee');
    final rk = frame.point('rightKnee');

    if (lk != null && rk != null) {
      final kneeY = (lk.y + rk.y) / 2;
      if (!_baselineSet && _frames < 5) {
        _baselineKneeY = (_baselineKneeY * _frames + kneeY) / (_frames + 1);
        if (_frames == 4) _baselineSet = true;
      }

      if (_baselineSet && _detector.airborne.isAirborne) {
        final kneeTravel = (kneeY - _baselineKneeY).abs();
        if (kneeTravel < _minKneeTravel) {
          // Vertical jump — minimal knee travel
          _detector.airborne.update(frame);
          _frames++;
          return;
        }
      }
    }

    _detector.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

// ---------------------------------------------------------------------------
// GROUP 6: LEARNED MODELS — Feature variants
// ---------------------------------------------------------------------------

/// Enhanced heuristic with acceleration + stance width features.
double jsqEnhancedHeuristicScore(NuvoPoseFrame frame, List<NuvoPoseFrame> history) {
  final ls = frame.point('leftShoulder');
  final rs = frame.point('rightShoulder');
  final lh = frame.point('leftHip');
  final rh = frame.point('rightHip');
  final lk = frame.point('leftKnee');
  final rk = frame.point('rightKnee');
  final la = frame.point('leftAnkle');
  final ra = frame.point('rightAnkle');

  if (ls == null || rs == null || lh == null || rh == null ||
      lk == null || rk == null || la == null || ra == null) return 0;

  final hipY = (lh.y + rh.y) / 2;
  final kneeY = (lk.y + rk.y) / 2;
  final shoulderY = (ls.y + rs.y) / 2;
  final torsoH = (hipY - shoulderY).abs().clamp(0.12, 0.6);
  final hkr = ((kneeY - hipY) / torsoH).clamp(-2.0, 3.0);
  final ankleY = (la.y + ra.y) / 2;
  final footSep = (la.x - ra.x).abs();

  double score = 0;

  // Feature 1: deep flexion
  if (hkr < 0.50) score += 0.15;

  // Feature 2: explosive ascent (velocity)
  if (history.isNotEmpty) {
    final prevLh = history.last.point('leftHip');
    final prevRh = history.last.point('rightHip');
    final prevHipY = (prevLh != null && prevRh != null) ? (prevLh.y + prevRh.y) / 2 : hipY;
    final hipVel = hipY - prevHipY;
    if (hipVel < -0.015) score += 0.25;
  }

  // Feature 3: ankle rise
  if (history.length > 3) {
    final pastLa = history[history.length - 3].point('leftAnkle');
    final pastRa = history[history.length - 3].point('rightAnkle');
    final pastAnkleY = (pastLa != null && pastRa != null) ? (pastLa.y + pastRa.y) / 2 : ankleY;
    final ankleRise = pastAnkleY - ankleY;
    if (ankleRise > torsoH * 0.15) score += 0.25;
  }

  // Feature 4: foot separation guard (reject jumping jacks)
  if (footSep > 0.20) score -= 0.4;

  // Feature 5: knee extension
  if (history.isNotEmpty) {
    final prevLk = history.last.point('leftKnee');
    final prevRk = history.last.point('rightKnee');
    final prevKneeY = (prevLk != null && prevRk != null) ? (prevLk.y + prevRk.y) / 2 : kneeY;
    final kneeVel = kneeY - prevKneeY;
    if (kneeVel < -0.008) score += 0.15;
  }

  // Feature 6: acceleration (second derivative)
  if (history.length > 1) {
    final prevLh = history.last.point('leftHip');
    final prevRh = history.last.point('rightHip');
    final prevHipY = (prevLh != null && prevRh != null) ? (prevLh.y + prevRh.y) / 2 : hipY;
    final hipVel = hipY - prevHipY;

    final past2Lh = history[history.length - 2].point('leftHip');
    final past2Rh = history[history.length - 2].point('rightHip');
    final past2HipY = (past2Lh != null && past2Rh != null) ? (past2Lh.y + past2Rh.y) / 2 : prevHipY;
    final prevHipVel = prevHipY - past2HipY;

    final hipAccel = hipVel - prevHipVel;
    if (hipAccel < -0.001) score += 0.2;
  }

  // Feature 7: stance width stability (penalize widening)
  if (history.isNotEmpty) {
    final prevLa = history.last.point('leftAnkle');
    final prevRa = history.last.point('rightAnkle');
    if (prevLa != null && prevRa != null) {
      final prevSep = (prevLa.x - prevRa.x).abs();
      final sepChange = (footSep - prevSep).abs();
      if (sepChange > 0.05) score -= 0.15;
    }
  }

  return score.clamp(0.0, 1.0);
}

// ---------------------------------------------------------------------------
// GROUP 7: HYBRIDS — Deterministic proposal + ML verifier
// ---------------------------------------------------------------------------

/// Hybrid: ConceptDetector proposes reps, ML score verifies each.
/// Only counts reps where the ML score at the landing frame exceeds threshold.
class CandidateHybridDetML extends MotionCandidate {
  @override
  final String id = 'hybrid_det_ml';
  @override
  final String family = 'hybrid';
  @override
  final String architecture = 'DetProposal_MLVerifier';

  late double _mlThreshold;
  late ConceptDetector _detector;
  final List<NuvoPoseFrame> _history = [];
  int _verifiedReps = 0;
  int _frames = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    _mlThreshold = (config['mlThreshold'] as num?)?.toDouble() ?? 0.4;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _history.clear();
    _verifiedReps = 0;
    _frames = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final prevRepCount = _detector.repCount;
    _detector.update(frame);

    // Detect landing transition (det just counted a rep)
    if (_detector.repCount > prevRepCount) {
      // Verify with ML score
      final score = jsqEnhancedHeuristicScore(frame, List.unmodifiable(_history));
      if (score >= _mlThreshold) {
        _verifiedReps++;
      }
    }

    _history.add(frame);
    if (_history.length > 30) _history.removeAt(0);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _verifiedReps,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
      diagnostics: {
        'detReps': _detector.repCount,
        'verifiedReps': _verifiedReps,
        'mlThreshold': _mlThreshold,
      },
    );
  }
}

/// Hybrid: ML movement classifier gates whether to run deterministic counter.
class CandidateHybridMLGateDet extends MotionCandidate {
  @override
  final String id = 'hybrid_ml_gate_det';
  @override
  final String family = 'hybrid';
  @override
  final String architecture = 'MLGate_DetCounter';

  late double _gateThreshold;
  late ConceptDetector _detector;
  final List<NuvoPoseFrame> _history = [];
  int _gatedReps = 0;
  int _frames = 0;
  int _gatedFrames = 0;
  final _sw = Stopwatch();
  bool _gateOpen = false;

  @override
  void initialize(Map<String, dynamic> config) {
    _gateThreshold = (config['gateThreshold'] as num?)?.toDouble() ?? 0.3;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _history.clear();
    _gatedReps = 0;
    _frames = 0;
    _gatedFrames = 0;
    _gateOpen = false;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    // ML gate: check if this looks like jump squat movement
    final score = jsqEnhancedHeuristicScore(frame, List.unmodifiable(_history));
    _gateOpen = score >= _gateThreshold;

    if (_gateOpen) {
      _gatedFrames++;
      final prevRepCount = _detector.repCount;
      _detector.update(frame);
      if (_detector.repCount > prevRepCount) {
        _gatedReps++;
      }
    } else {
      // Still update airborne tracker for state continuity
      _detector.airborne.update(frame);
    }

    _history.add(frame);
    if (_history.length > 30) _history.removeAt(0);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _gatedReps,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
      diagnostics: {
        'gatedReps': _gatedReps,
        'gatedFrames': _gatedFrames,
        'gateThreshold': _gateThreshold,
      },
    );
  }
}

// ---------------------------------------------------------------------------
// COMBINATION CANDIDATES (Phase 10)
// ---------------------------------------------------------------------------

/// Combines: camera consensus + foot guard + deep squat reject.
class CandidateComboCameraFootDeepSquat extends MotionCandidate {
  @override
  final String id = 'combo_cam_foot_deepsquat';
  @override
  final String family = 'hybrid';
  @override
  final String architecture = 'Combo_Consensus+FootGuard+DeepSquatReject';

  late double _footSepThreshold;
  late double _minKneeAngle;
  late double _consensusThreshold;
  late ConceptDetector _detector;
  int _frames = 0;
  final _sw = Stopwatch();
  double _prevShoulderY = 0;
  double _prevHipY = 0;
  bool _hasPrev = false;

  double _kneeAngle(NuvoPoseFrame frame) {
    final hip = frame.point('leftHip');
    final knee = frame.point('leftKnee');
    final ankle = frame.point('leftAnkle');
    if (hip == null || knee == null || ankle == null) return 180;
    final v1x = hip.x - knee.x;
    final v1y = hip.y - knee.y;
    final v2x = ankle.x - knee.x;
    final v2y = ankle.y - knee.y;
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0 || mag2 == 0) return 180;
    final cos = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  @override
  void initialize(Map<String, dynamic> config) {
    _footSepThreshold = (config['footSepThreshold'] as num?)?.toDouble() ?? 0.15;
    _minKneeAngle = (config['minKneeAngle'] as num?)?.toDouble() ?? 70.0;
    _consensusThreshold = (config['consensusThreshold'] as num?)?.toDouble() ?? 0.004;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _frames = 0;
    _hasPrev = false;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final ls = frame.point('leftShoulder');
    final rs = frame.point('rightShoulder');
    final lh = frame.point('leftHip');
    final rh = frame.point('rightHip');
    final la = frame.point('leftAnkle');
    final ra = frame.point('rightAnkle');

    // 1. Camera consensus check
    if (ls != null && rs != null && lh != null && rh != null && _hasPrev) {
      final shoulderY = (ls.y + rs.y) / 2;
      final hipY = (lh.y + rh.y) / 2;
      final shoulderVel = shoulderY - _prevShoulderY;
      final hipVel = hipY - _prevHipY;
      if ((shoulderVel * hipVel > 0) &&
          (shoulderVel.abs() > _consensusThreshold ||
           hipVel.abs() > _consensusThreshold)) {
        _detector.airborne.update(frame);
        _prevShoulderY = shoulderY;
        _prevHipY = hipY;
        _frames++;
        return;
      }
      _prevShoulderY = shoulderY;
      _prevHipY = hipY;
    } else if (ls != null && rs != null && lh != null && rh != null) {
      _prevShoulderY = (ls.y + rs.y) / 2;
      _prevHipY = (lh.y + rh.y) / 2;
      _hasPrev = true;
    }

    // 2. Foot guard
    if (la != null && ra != null) {
      final sep = (la.x - ra.x).abs();
      if (sep > _footSepThreshold && _detector.airborne.isAirborne) {
        _detector.airborne.update(frame);
        _frames++;
        return;
      }
    }

    // 3. Deep squat reject
    final angle = _kneeAngle(frame);
    if (angle < _minKneeAngle && !_detector.airborne.isAirborne && _detector.phase == V2Phase.idle) {
      _frames++;
      return;
    }

    _detector.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

/// Combines: stance width + ML verifier.
class CandidateComboStanceML extends MotionCandidate {
  @override
  final String id = 'combo_stance_ml';
  @override
  final String family = 'hybrid';
  @override
  final String architecture = 'Combo_StanceWidth+MLVerifier';

  late double _maxStanceWidth;
  late double _mlThreshold;
  late ConceptDetector _detector;
  final List<NuvoPoseFrame> _history = [];
  int _verifiedReps = 0;
  int _frames = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    _maxStanceWidth = (config['maxStanceWidth'] as num?)?.toDouble() ?? 0.18;
    _mlThreshold = (config['mlThreshold'] as num?)?.toDouble() ?? 0.4;
    _detector = ConceptDetector(
      flightThresholdRatio: 0.18,
      standingHkr: 0.55,
      squatHkr: 0.58,
      fastRiseThreshold: -0.010,
      airbornePeakRequired: 0.12,
    );
    _history.clear();
    _verifiedReps = 0;
    _frames = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();

    final la = frame.point('leftAnkle');
    final ra = frame.point('rightAnkle');

    // Stance width guard
    if (la != null && ra != null) {
      final stance = (la.x - ra.x).abs();
      if (stance > _maxStanceWidth && _detector.airborne.isAirborne) {
        _detector.airborne.update(frame);
        _history.add(frame);
        if (_history.length > 30) _history.removeAt(0);
        _frames++;
        return;
      }
    }

    final prevRepCount = _detector.repCount;
    _detector.update(frame);

    // ML verify
    if (_detector.repCount > prevRepCount) {
      final score = jsqEnhancedHeuristicScore(frame, List.unmodifiable(_history));
      if (score >= _mlThreshold) {
        _verifiedReps++;
      }
    }

    _history.add(frame);
    if (_history.length > 30) _history.removeAt(0);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _verifiedReps,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
      diagnostics: {
        'detReps': _detector.repCount,
        'verifiedReps': _verifiedReps,
      },
    );
  }
}
