import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/ai/airborne_state_tracker.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/multi_phase_sequence_tracker.dart';

import 'motion_intelligence.dart';

// ============================================================================
// PHASE 8: EXPERIMENT CONFIG SYSTEM
// ============================================================================

class ExperimentConfig {
  final String candidateId;
  final String family;
  final String architecture;
  final Map<String, dynamic> parameters;
  final String notes;

  ExperimentConfig({
    required this.candidateId,
    this.family = 'deterministic',
    required this.architecture,
    required this.parameters,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
    'candidateId': candidateId,
    'family': family,
    'architecture': architecture,
    'parameters': parameters,
    'notes': notes,
  };
}

// ============================================================================
// PHASE 9: AUTOMATED PARAMETER SEARCH
// ============================================================================

class ParameterSearchSpace {
  final String name;
  final List<double> values;
  ParameterSearchSpace(this.name, this.values);
}

class SearchRunner {
  final List<ParameterSearchSpace> dimensions;
  final double Function(Map<String, double>) objective;

  SearchRunner(this.dimensions, this.objective);

  List<Map<String, double>> gridSearch() {
    final results = <Map<String, double>>[];
    _gridSearchRecursive({}, 0, results);
    return results..sort((a, b) => objective(b).compareTo(objective(a)));
  }

  void _gridSearchRecursive(
    Map<String, double> current,
    int dim,
    List<Map<String, double>> results,
  ) {
    if (dim >= dimensions.length) {
      results.add(Map.from(current));
      return;
    }
    for (final v in dimensions[dim].values) {
      current[dimensions[dim].name] = v;
      _gridSearchRecursive(current, dim + 1, results);
    }
  }

  Map<String, double> bestConfig() {
    final grid = gridSearch();
    return grid.isEmpty ? {} : grid.first;
  }
}

// ============================================================================
// DETERMINISTIC CANDIDATES (5+ required for M1)
// ============================================================================

// Candidate 3: Lowered airborne threshold
class CandidateLoweredAirborne extends MotionCandidate {
  @override
  final String id = 'det_lowered_airborne';
  @override
  final String family = 'deterministic';
  @override
  final String architecture = 'MultiPhaseSequenceValidator_tuned';

  late MultiPhaseSequenceValidator _validator;
  int _frames = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    _validator = MultiPhaseSequenceValidator(
      activity: AiMotionActivity.jumpSquats,
      targetValue: 100,
      definitions: (a) => [_buildDef(a)],
      statusText: 'Jump Squats',
      coachingTextActive: 'Keep jumping!',
      coachingTextIncomplete: 'Get full body in frame',
    );
    _frames = 0;
    _sw.reset();
  }

  MultiPhaseSequenceDefinition _buildDef(AirborneStateTracker ab) {
    final standing = const ComparisonCondition(PoseSignal.hipToKneeRatio, 0.55, greaterThan: true);
    final squat = const ComparisonCondition(PoseSignal.hipToKneeRatio, 0.58, greaterThan: false);
    final airborneCond = AirborneCondition(ab);
    final landing = AndCondition([standing, GroundedCondition(ab)]);

    return MultiPhaseSequenceDefinition(
      phases: [
        SequencePhaseDefinition(id: 'STANDING', condition: AndCondition([standing, GroundedCondition(ab)]), stableFrames: 2),
        SequencePhaseDefinition(id: 'SQUAT', condition: squat, stableFrames: 1),
        SequencePhaseDefinition(id: 'AIRBORNE', condition: airborneCond, stableFrames: 1),
        SequencePhaseDefinition(id: 'LANDING', condition: landing, stableFrames: 2),
      ],
      resetCondition: AndCondition([standing, GroundedCondition(ab)]),
      requiredLandmarks: ['leftShoulder', 'rightShoulder', 'leftHip', 'rightHip', 'leftKnee', 'rightKnee'],
      cooldownFrames: 3,
      noiseGraceFrames: 2,
    );
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();
    _validator.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _validator.currentValue,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

// Candidate 4: Foot separation guard (rejects jumping jacks)
class CandidateFootGuard extends MotionCandidate {
  @override
  final String id = 'det_foot_guard';
  @override
  final String family = 'deterministic';
  @override
  final String architecture = 'ConceptStateMachine_with_foot_guard';

  late double _flightRatio;
  late double _footSepThreshold;
  _FootGuardDetector? _detector;
  int _frames = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    _flightRatio = (config['flightThresholdRatio'] as num?)?.toDouble() ?? 0.20;
    _footSepThreshold = (config['footSepThreshold'] as num?)?.toDouble() ?? 0.15;
    _detector = _FootGuardDetector(
      flightRatio: _flightRatio,
      footSepThreshold: _footSepThreshold,
    );
    _frames = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();
    _detector!.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector!.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

class _FootGuardDetector extends ConceptDetector {
  final double footSepThreshold;
  double _footSeparation = 0;

  _FootGuardDetector({
    required double flightRatio,
    required this.footSepThreshold,
  }) : super(
          flightThresholdRatio: flightRatio,
          standingHkr: 0.60,
          squatHkr: 0.58,
          fastRiseThreshold: -0.012,
          airbornePeakRequired: 0.15,
        );

  @override
  void update(NuvoPoseFrame frame) {
    final la = frame.point('leftAnkle');
    final ra = frame.point('rightAnkle');
    if (la != null && ra != null) {
      _footSeparation = (la.x - ra.x).abs();
    }
    // Reject airborne if feet are spread (jumping jack pattern)
    if (airborne.isAirborne && _footSeparation > footSepThreshold) {
      // Don't count this as a rep — force rearm
      if (phase == V2Phase.airborne) {
        recordFailure('foot_separation_reject');
        phase = V2Phase.rearm;
        framesInPhase = 0;
      }
      return;
    }
    super.update(frame);
  }
}

// Candidate 5: Camera motion compensated
class CandidateCameraCompensated extends MotionCandidate {
  @override
  final String id = 'det_camera_comp';
  @override
  final String family = 'deterministic';
  @override
  final String architecture = 'ConceptStateMachine_with_camera_comp';

  late double _flightRatio;
  late double _cameraMotionThreshold;
  _CameraCompDetector? _detector;
  int _frames = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    _flightRatio = (config['flightThresholdRatio'] as num?)?.toDouble() ?? 0.20;
    _cameraMotionThreshold = (config['cameraMotionThreshold'] as num?)?.toDouble() ?? 0.008;
    _detector = _CameraCompDetector(
      flightRatio: _flightRatio,
      cameraMotionThreshold: _cameraMotionThreshold,
    );
    _frames = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();
    _detector!.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector!.repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

class _CameraCompDetector extends ConceptDetector {
  final double cameraMotionThreshold;
  double _prevShoulderY = 0;
  double _prevHipY2 = 0;
  bool _hasPrev2 = false;

  _CameraCompDetector({
    required double flightRatio,
    required this.cameraMotionThreshold,
  }) : super(
          flightThresholdRatio: flightRatio,
          standingHkr: 0.55,
          squatHkr: 0.58,
          fastRiseThreshold: -0.008,
          airbornePeakRequired: 0.10,
        );

  @override
  void update(NuvoPoseFrame frame) {
    // Estimate camera motion: if shoulders and hips move same direction,
    // it's likely camera translation, not body motion.
    final ls = frame.point('leftShoulder');
    final rs = frame.point('rightShoulder');
    final lh = frame.point('leftHip');
    final rh = frame.point('rightHip');

    if (ls != null && rs != null && lh != null && rh != null && _hasPrev2) {
      final shoulderY = (ls.y + rs.y) / 2;
      final hipY = (lh.y + rh.y) / 2;
      final shoulderVel = shoulderY - _prevShoulderY;
      final hipVel = hipY - _prevHipY2;

      // If both move same direction by > threshold, it's camera motion
      if ((shoulderVel * hipVel > 0) &&
          (shoulderVel.abs() > cameraMotionThreshold ||
           hipVel.abs() > cameraMotionThreshold)) {
        // Camera motion detected — skip this frame for rep detection
        // but still update airborne tracker
        airborne.update(frame);
        return;
      }
      _prevShoulderY = shoulderY;
      _prevHipY2 = hipY;
    } else if (ls != null && rs != null && lh != null && rh != null) {
      _prevShoulderY = (ls.y + rs.y) / 2;
      _prevHipY2 = (lh.y + rh.y) / 2;
      _hasPrev2 = true;
    }

    super.update(frame);
  }
}

// Candidate 6: Wider noise grace + lower standing
class CandidateRelaxedTemporal extends MotionCandidate {
  @override
  final String id = 'det_relaxed_temporal';
  @override
  final String family = 'deterministic';
  @override
  final String architecture = 'MultiPhaseSequenceValidator_relaxed';

  late MultiPhaseSequenceValidator _validator;
  int _frames = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    final flightRatio = (config['flightThresholdRatio'] as num?)?.toDouble() ?? 0.20;
    final standingHkr = (config['standingHkr'] as num?)?.toDouble() ?? 0.50;
    final noiseGrace = (config['noiseGraceFrames'] as num?)?.toInt() ?? 3;
    // flightRatio is used by the airborne tracker inside the definition builder
    final _ = flightRatio; // keep for future parameter injection

    _validator = MultiPhaseSequenceValidator(
      activity: AiMotionActivity.jumpSquats,
      targetValue: 100,
      definitions: (a) => [_buildDef(a, standingHkr, noiseGrace)],
      statusText: 'Jump Squats',
      coachingTextActive: 'Keep jumping!',
      coachingTextIncomplete: 'Get full body in frame',
    );
    _frames = 0;
    _sw.reset();
  }

  MultiPhaseSequenceDefinition _buildDef(AirborneStateTracker ab, double standingHkr, int noiseGrace) {
    final standing = ComparisonCondition(PoseSignal.hipToKneeRatio, standingHkr, greaterThan: true);
    final squat = const ComparisonCondition(PoseSignal.hipToKneeRatio, 0.58, greaterThan: false);
    final airborneCond = AirborneCondition(ab);
    final landing = AndCondition([standing, GroundedCondition(ab)]);

    return MultiPhaseSequenceDefinition(
      phases: [
        SequencePhaseDefinition(id: 'STANDING', condition: AndCondition([standing, GroundedCondition(ab)]), stableFrames: 1),
        SequencePhaseDefinition(id: 'SQUAT', condition: squat, stableFrames: 1),
        SequencePhaseDefinition(id: 'AIRBORNE', condition: airborneCond, stableFrames: 1),
        SequencePhaseDefinition(id: 'LANDING', condition: landing, stableFrames: 1),
      ],
      resetCondition: AndCondition([standing, GroundedCondition(ab)]),
      requiredLandmarks: ['leftShoulder', 'rightShoulder', 'leftHip', 'rightHip', 'leftKnee', 'rightKnee'],
      cooldownFrames: 2,
      noiseGraceFrames: noiseGrace,
    );
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();
    _validator.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _validator.currentValue,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

// ============================================================================
// PHASE 18: ML BASELINE — Feature-based MLP (simulated)
// ============================================================================

class MLCandidate extends MotionCandidate {
  @override
  final String id;
  @override
  final String family = 'ml';
  @override
  final String architecture;

  final double Function(NuvoPoseFrame, List<NuvoPoseFrame>) _predictFn;
  final List<NuvoPoseFrame> _history = [];
  int _repCount = 0;
  int _frames = 0;
  final _sw = Stopwatch();
  double _threshold;
  bool _inRep = false;

  MLCandidate({
    required this.id,
    required this.architecture,
    required this._predictFn,
    double threshold = 0.5,
  }) : _threshold = threshold;

  @override
  void initialize(Map<String, dynamic> config) {
    _threshold = (config['threshold'] as num?)?.toDouble() ?? _threshold;
    _history.clear();
    _repCount = 0;
    _frames = 0;
    _inRep = false;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();
    final score = _predictFn(frame, List.unmodifiable(_history));
    if (score > _threshold && !_inRep) {
      _repCount++;
      _inRep = true;
    } else if (score < _threshold * 0.5) {
      _inRep = false;
    }
    _history.add(frame);
    if (_history.length > 30) _history.removeAt(0);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _repCount,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
      diagnostics: {'threshold': _threshold, 'historyLen': _history.length},
    );
  }
}

// Heuristic ML feature function: uses hip velocity + knee angle + airborne
// This simulates a tiny learned model using hand-crafted features
double jsqHeuristicScore(NuvoPoseFrame frame, List<NuvoPoseFrame> history) {
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

  // Feature 1: deep flexion (squat bottom)
  if (hkr < 0.50) score += 0.2;

  // Feature 2: explosive ascent
  if (history.isNotEmpty) {
    final prevLh = history.last.point('leftHip');
    final prevRh = history.last.point('rightHip');
    final prevHipY = (prevLh != null && prevRh != null) ? (prevLh.y + prevRh.y) / 2 : hipY;
    final hipVel = hipY - prevHipY;
    if (hipVel < -0.015) score += 0.3;
  }

  // Feature 3: ankle rise (airborne)
  if (history.length > 3) {
    final pastLa = history[history.length - 3].point('leftAnkle');
    final pastRa = history[history.length - 3].point('rightAnkle');
    final pastAnkleY = (pastLa != null && pastRa != null) ? (pastLa.y + pastRa.y) / 2 : ankleY;
    final ankleRise = pastAnkleY - ankleY;
    if (ankleRise > torsoH * 0.15) score += 0.3;
  }

  // Feature 4: foot separation guard (reject jumping jacks)
  if (footSep > 0.20) score -= 0.3;

  // Feature 5: knee extension
  if (history.isNotEmpty) {
    final prevLk = history.last.point('leftKnee');
    final prevRk = history.last.point('rightKnee');
    final prevKneeY = (prevLk != null && prevRk != null) ? (prevLk.y + prevRk.y) / 2 : kneeY;
    final kneeVel = kneeY - prevKneeY;
    if (kneeVel < -0.008) score += 0.2;
  }

  return score.clamp(0.0, 1.0);
}
