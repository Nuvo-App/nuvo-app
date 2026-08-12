import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/ai/airborne_state_tracker.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/preset_motion/multi_phase_definitions.dart';

import 'replay_fixture.dart';

// ============================================================================
// MOTION CONCEPT LAYER
// ============================================================================
// Runtime-safe, causal, per-frame concepts derived from pose landmarks.
// Each concept exposes a confidence [0..1] and a boolean active flag.
// No ground truth, no expected reps, no clip identity, no post-hoc knowledge.
// ============================================================================

/// A single motion concept evaluation result.
class ConceptResult {
  const ConceptResult({
    required this.name,
    required this.active,
    required this.confidence,
    this.rawValue,
  });

  final String name;
  final bool active;
  final double confidence;
  final double? rawValue;

  @override
  String toString() =>
      '$name: ${active ? "PASS" : "FAIL"} ${confidence.toStringAsFixed(2)}';
}

/// Extracts runtime-safe motion concepts from a single pose frame.
///
/// All concepts are derived from pose landmarks available at runtime.
/// No ground truth, no expected counts, no clip metadata.
class MotionConceptExtractor {
  MotionConceptExtractor({double flightThresholdRatio = 0.20})
      : _airborneTracker = AirborneStateTracker(
          flightThresholdRatio: flightThresholdRatio,
        );

  final AirborneStateTracker _airborneTracker;

  // Ring buffer for temporal smoothing (last N frames).
  final List<_FrameSignals> _history = [];
  static const int _historyLen = 8;

  // Baseline ankle Y for airborne detection (EMA-updated when grounded).
  double _baselineAnkleY = 0;
  bool _baselineEstablished = false;
  int _baselineSamples = 0;
  static const int _baselineFrames = 4;
  static const double _baselineEmaAlpha = 0.20;

  /// Process a frame and return all concept evaluations.
  List<ConceptResult> evaluate(NuvoPoseFrame frame) {
    final signals = _extractSignals(frame);
    _updateHistory(signals);
    _updateBaseline(signals);
    _airborneTracker.update(frame);
    return _classifyConcepts(signals, frame);
  }

  _FrameSignals _extractSignals(NuvoPoseFrame frame) {
    final ls = frame.point('leftShoulder');
    final rs = frame.point('rightShoulder');
    final lh = frame.point('leftHip');
    final rh = frame.point('rightHip');
    final lk = frame.point('leftKnee');
    final rk = frame.point('rightKnee');
    final la = frame.point('leftAnkle');
    final ra = frame.point('rightAnkle');

    final s = _FrameSignals();

    // Confidence tracking
    s.leftAnkleConf = la?.likelihood ?? 0;
    s.rightAnkleConf = ra?.likelihood ?? 0;
    s.leftKneeConf = lk?.likelihood ?? 0;
    s.rightKneeConf = rk?.likelihood ?? 0;
    s.leftHipConf = lh?.likelihood ?? 0;
    s.rightHipConf = rh?.likelihood ?? 0;

    s.missingAnkles = (la == null ? 1 : 0) + (ra == null ? 1 : 0);
    s.missingCore = (ls == null || rs == null || lh == null || rh == null ||
        lk == null || rk == null);

    if (s.missingCore) return s;

    s.shoulderY = (ls!.y + rs!.y) / 2;
    s.hipY = (lh!.y + rh!.y) / 2;
    s.kneeY = (lk!.y + rk!.y) / 2;
    s.torsoHeight = (s.hipY! - s.shoulderY!).abs().clamp(0.12, 0.6);

    // hipToKneeRatio: key posture signal
    s.hipToKneeRatio =
        ((s.kneeY! - s.hipY!) / s.torsoHeight!).clamp(-2.0, 3.0);

    // Knee angles (if ankles available)
    if (la != null && ra != null) {
      s.leftKneeAngle = _angle3(lh, lk, la);
      s.rightKneeAngle = _angle3(rh, rk, ra);
      s.avgKneeAngle = (s.leftKneeAngle! + s.rightKneeAngle!) / 2;
      s.kneeFlexion = 180 - s.avgKneeAngle!;
    } else if (la != null) {
      s.leftKneeAngle = _angle3(lh, lk, la);
      s.avgKneeAngle = s.leftKneeAngle;
      s.kneeFlexion = 180 - s.avgKneeAngle!;
    } else if (ra != null) {
      s.rightKneeAngle = _angle3(rh, rk, ra);
      s.avgKneeAngle = s.rightKneeAngle;
      s.kneeFlexion = 180 - s.avgKneeAngle!;
    }

    // Ankle signals
    if (la != null && ra != null) {
      s.ankleAvgY = (la.y + ra.y) / 2;
      s.footSeparation = (la.x - ra.x).abs();
    }

    // Velocities from history
    if (_history.isNotEmpty) {
      final prev = _history.last;
      if (prev.hipY != null && s.hipY != null) {
        s.hipVelocity = s.hipY! - prev.hipY!;
      }
      if (prev.shoulderY != null && s.shoulderY != null) {
        s.shoulderVelocity = s.shoulderY! - prev.shoulderY!;
      }
      if (prev.ankleAvgY != null && s.ankleAvgY != null) {
        s.ankleVelocity = s.ankleAvgY! - prev.ankleAvgY!;
      }
      if (prev.kneeY != null && s.kneeY != null) {
        s.kneeVelocity = s.kneeY! - prev.kneeY!;
      }
    }

    s.valid = true;
    return s;
  }

  void _updateHistory(_FrameSignals s) {
    _history.add(s);
    if (_history.length > _historyLen) {
      _history.removeAt(0);
    }
  }

  void _updateBaseline(_FrameSignals s) {
    if (s.ankleAvgY == null) return;

    if (!_baselineEstablished) {
      // Collect baseline samples
      if (_history.length >= 2) {
        final prev = _history[_history.length - 2];
        if (prev.ankleAvgY != null &&
            (s.ankleAvgY! - prev.ankleAvgY!).abs() < 0.030) {
          _baselineSamples++;
          _baselineAnkleY =
              _baselineAnkleY * (_baselineSamples - 1) / _baselineSamples +
              s.ankleAvgY! / _baselineSamples;
        } else {
          _baselineSamples = 1;
          _baselineAnkleY = s.ankleAvgY!;
        }
        if (_baselineSamples >= _baselineFrames) {
          _baselineEstablished = true;
        }
      } else {
        _baselineSamples = 1;
        _baselineAnkleY = s.ankleAvgY!;
      }
    } else if (s.ankleAvgY != null) {
      // EMA update when grounded (ankle near baseline)
      final rise = _baselineAnkleY - s.ankleAvgY!;
      final groundedTol = math.max(0.015, s.torsoHeight! * 0.10);
      if (rise.abs() < groundedTol) {
        _baselineAnkleY = _baselineAnkleY * (1 - _baselineEmaAlpha) +
            s.ankleAvgY! * _baselineEmaAlpha;
      }
    }
  }

  List<ConceptResult> _classifyConcepts(_FrameSignals s, NuvoPoseFrame frame) {
    final concepts = <ConceptResult>[];

    if (!s.valid) {
      concepts.add(ConceptResult(
        name: 'pose_quality_low',
        active: true,
        confidence: 1.0,
      ));
      return concepts;
    }

    final hkr = s.hipToKneeRatio!;
    final kneeFlex = s.kneeFlexion ?? 0;
    final hipVel = s.hipVelocity;
    final ankleVel = s.ankleVelocity;
    final shoulderVel = s.shoulderVelocity;
    final torsoH = s.torsoHeight!;
    // --- POSTURE CONCEPTS ---

    // standing_like: high hkr, knees relatively straight
    final standingConf = _linearConfidence(hkr, 0.55, 0.75);
    concepts.add(ConceptResult(
      name: 'standing_like',
      active: hkr > 0.60 && kneeFlex < 50,
      confidence: standingConf,
      rawValue: hkr,
    ));

    // athletic_stance: moderate hkr, slight knee bend
    final athleticConf = _peakConfidence(hkr, 0.50, 0.65, 0.80);
    concepts.add(ConceptResult(
      name: 'athletic_stance',
      active: hkr > 0.45 && hkr < 0.75 && kneeFlex > 15 && kneeFlex < 70,
      confidence: athleticConf,
      rawValue: hkr,
    ));

    // deep_flexion: low hkr (hips near or below knee level)
    final deepConf = _linearConfidence(0.58 - hkr, 0.0, 0.20);
    concepts.add(ConceptResult(
      name: 'deep_flexion',
      active: hkr < 0.50,
      confidence: deepConf,
      rawValue: hkr,
    ));

    // --- DIRECTION CONCEPTS (velocity-based) ---

    // descending: hip Y increasing (moving down in image coords)
    final descConf = _linearConfidence(hipVel, 0.003, 0.02);
    concepts.add(ConceptResult(
      name: 'descending',
      active: hipVel > 0.005,
      confidence: descConf,
      rawValue: hipVel,
    ));

    // ascending: hip Y decreasing (moving up)
    final ascConf = _linearConfidence(-hipVel, 0.003, 0.02);
    concepts.add(ConceptResult(
      name: 'ascending',
      active: hipVel < -0.005,
      confidence: ascConf,
      rawValue: hipVel,
    ));

    // body_rising_fast: significant upward hip velocity
    final fastRiseConf = _linearConfidence(-hipVel, 0.008, 0.025);
    concepts.add(ConceptResult(
      name: 'body_rising_fast',
      active: hipVel < -0.012,
      confidence: fastRiseConf,
      rawValue: hipVel,
    ));

    // --- KNEE DIRECTION ---

    // knees_flexing: knee Y increasing relative to hip (going deeper)
    final kneeVel = s.kneeVelocity;
    final flexConf = _linearConfidence(kneeVel, 0.002, 0.015);
    concepts.add(ConceptResult(
      name: 'knees_flexing',
      active: kneeVel > 0.004 && kneeFlex > 20,
      confidence: flexConf,
      rawValue: kneeVel,
    ));

    // knees_extending: knee Y decreasing (straightening)
    final extConf = _linearConfidence(-kneeVel, 0.002, 0.015);
    concepts.add(ConceptResult(
      name: 'knees_extending',
      active: kneeVel < -0.004 && kneeFlex > 15,
      confidence: extConf,
      rawValue: kneeVel,
    ));

    // --- AIRBORNE CONCEPTS ---

    if (s.ankleAvgY != null && _baselineEstablished) {
      final ankleRise = _baselineAnkleY - s.ankleAvgY!;
      final riseRatio = ankleRise / torsoH;
      // airborne_candidate: delegates to production AirborneStateTracker
      // which uses bilateral ankle check + baseline-relative threshold.
      // We use a lower flightThresholdRatio (0.20 vs 0.25) for more recall.
      final isAirborne = _airborneTracker.isAirborne;
      final airbConf = _linearConfidence(riseRatio, 0.12, 0.25);
      concepts.add(ConceptResult(
        name: 'airborne_candidate',
        active: isAirborne,
        confidence: isAirborne ? airbConf.clamp(0.5, 1.0) : airbConf,
        rawValue: riseRatio,
      ));

      // grounded_candidate: ankles near baseline
      final groundConf = _linearConfidence(0.12 - riseRatio.abs(), 0.0, 0.12);
      concepts.add(ConceptResult(
        name: 'grounded_candidate',
        active: riseRatio.abs() < 0.10,
        confidence: groundConf,
        rawValue: riseRatio,
      ));

      // landing_candidate: was airborne, now returning to grounded
      final wasAirborne = _history.length >= 2 &&
          (_history[_history.length - 2].concepts ?? const {})['airborne_candidate'] == true;
      final landConf = wasAirborne
          ? _linearConfidence(ankleVel, 0.005, 0.02)
          : 0.0;
      concepts.add(ConceptResult(
        name: 'landing_candidate',
        active: wasAirborne && ankleVel > 0.008,
        confidence: landConf,
        rawValue: ankleVel,
      ));
    } else {
      concepts.add(ConceptResult(
        name: 'airborne_candidate',
        active: false,
        confidence: 0.0,
      ));
      concepts.add(ConceptResult(
        name: 'grounded_candidate',
        active: false,
        confidence: 0.0,
      ));
      concepts.add(ConceptResult(
        name: 'landing_candidate',
        active: false,
        confidence: 0.0,
      ));
    }

    // --- POSE QUALITY ---

    final ankleConfAvg = (s.leftAnkleConf + s.rightAnkleConf) / 2;
    final ankleQualityConf = _linearConfidence(ankleConfAvg, 0.3, 0.7);
    concepts.add(ConceptResult(
      name: 'ankle_visibility_good',
      active: s.missingAnkles == 0 && ankleConfAvg > 0.5,
      confidence: ankleQualityConf,
      rawValue: ankleConfAvg,
    ));

    // --- CAMERA MOTION ESTIMATE ---
    // If shoulder and hip move same direction but ankle doesn't, likely camera
    final hipV = s.hipVelocity;
    if (shoulderVel.abs() > 0.008 && hipV.abs() > 0.008) {
      final sameDir = (shoulderVel > 0) == (hipV > 0);
      final ankleAlso =
          ankleVel.abs() > 0.004 &&
          (ankleVel > 0) == (shoulderVel > 0);
      concepts.add(ConceptResult(
        name: 'camera_motion_likely',
        active: sameDir && ankleAlso,
        confidence: sameDir ? 0.7 : 0.0,
        rawValue: shoulderVel,
      ));
    } else {
      concepts.add(ConceptResult(
        name: 'camera_motion_likely',
        active: false,
        confidence: 0.0,
      ));
    }

    // Store concept states in signals for temporal access
    s.concepts = {
      for (final c in concepts) c.name: c.active,
    };

    return concepts;
  }

  // --- Confidence helpers ---

  /// Linear ramp from 0 at lo to 1 at hi (clamped).
  double _linearConfidence(double value, double lo, double hi) {
    if (hi <= lo) return value >= hi ? 1.0 : 0.0;
    return ((value - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  /// Peak confidence: ramps up from lo to peak at mid, then down to hi.
  double _peakConfidence(double value, double lo, double mid, double hi) {
    if (value < lo || value > hi) return 0.0;
    if (value <= mid) return _linearConfidence(value, lo, mid);
    return 1.0 - _linearConfidence(value, mid, hi);
  }

  double _angle3(NuvoPosePoint a, NuvoPosePoint b, NuvoPosePoint c) {
    final abx = a.x - b.x;
    final aby = a.y - b.y;
    final cbx = c.x - b.x;
    final cby = c.y - b.y;
    final dot = abx * cbx + aby * cby;
    final ab = math.sqrt(abx * abx + aby * aby);
    final cb = math.sqrt(cbx * cbx + cby * cby);
    if (ab == 0 || cb == 0) return 180;
    final cosine = (dot / (ab * cb)).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }
}

/// Per-frame raw signals extracted from pose landmarks.
class _FrameSignals {
  bool valid = false;
  double? shoulderY, hipY, kneeY, ankleAvgY;
  double? torsoHeight;
  double? hipToKneeRatio;
  double? leftKneeAngle, rightKneeAngle, avgKneeAngle;
  double? kneeFlexion;
  double? footSeparation;
  double hipVelocity = 0;
  double shoulderVelocity = 0;
  double ankleVelocity = 0;
  double kneeVelocity = 0;
  int missingAnkles = 0;
  bool missingCore = false;
  double leftAnkleConf = 0, rightAnkleConf = 0;
  double leftKneeConf = 0, rightKneeConf = 0;
  double leftHipConf = 0, rightHipConf = 0;
  Map<String, bool>? concepts;
}

// ============================================================================
// TEMPORAL CONCEPT STATE MACHINE
// ============================================================================
// Accumulates concept evidence across temporal windows.
// Allows concepts to persist briefly, survive short dropouts, and
// track concept duration.
// ============================================================================

/// Tracks the active/inactive state of a single concept over time,
/// with persistence and dropout tolerance.
class ConceptState {
  ConceptState(this.name, {this.persistenceFrames = 3, this.dropoutTolerance = 2});

  final String name;
  final int persistenceFrames;
  final int dropoutTolerance;

  bool _active = false;
  int _activeFrames = 0;
  int _dropoutFrames = 0;
  double _lastConfidence = 0;
  double _peakConfidence = 0;

  bool get active => _active;
  int get activeFrames => _activeFrames;
  double get lastConfidence => _lastConfidence;
  double get peakConfidence => _peakConfidence;

  void update(ConceptResult result) {
    _lastConfidence = result.confidence;
    if (result.active) {
      _active = true;
      _activeFrames++;
      _dropoutFrames = 0;
      if (result.confidence > _peakConfidence) {
        _peakConfidence = result.confidence;
      }
    } else {
      if (_active) {
        _dropoutFrames++;
        if (_dropoutFrames > dropoutTolerance) {
          _active = false;
          _activeFrames = 0;
          _peakConfidence = 0;
        }
      }
    }
  }

  void reset() {
    _active = false;
    _activeFrames = 0;
    _dropoutFrames = 0;
    _lastConfidence = 0;
    _peakConfidence = 0;
  }
}

// ============================================================================
// JUMP SQUAT V2 — CONCEPT-BASED DETECTOR
// ============================================================================
// Uses motion concepts + temporal tolerance to detect jump squat reps.
// Does NOT use movement-specific magic constants for phase thresholds.
// Instead, it tracks concept sequences with temporal windows.
// ============================================================================

/// Phase in the JSQ V2 concept state machine.
enum JsqV2Phase { idle, compression, ascent, airborne, landing, rearm }

/// Per-rep failure explanation.
class RepFailureExplanation {
  final int repNumber;
  final String failedConcept;
  final double failedConfidence;
  final Map<String, ConceptResult> conceptSnapshot;
  final JsqV2Phase failedPhase;

  RepFailureExplanation({
    required this.repNumber,
    required this.failedConcept,
    required this.failedConfidence,
    required this.conceptSnapshot,
    required this.failedPhase,
  });

  @override
  String toString() {
    final buf = StringBuffer('rep $repNumber:\n');
    for (final entry in conceptSnapshot.entries) {
      buf.writeln('  ${entry.value}');
    }
    buf.writeln('  FAILED at $failedPhase: $failedConcept (${failedConfidence.toStringAsFixed(2)})');
    return buf.toString();
  }
}

/// Experimental Jump Squat V2 detector.
///
/// State machine:
///   IDLE → COMPRESSION → ASCENT → AIRBORNE → LANDING → REARM → IDLE
///
/// Each transition requires concept evidence within a temporal window.
/// Concepts can persist briefly (persistence) and survive short dropouts.
class JumpSquatV2Detector {
  JumpSquatV2Detector({this.target = 99});

  final int target;

  final MotionConceptExtractor _extractor = MotionConceptExtractor();

  // Concept states with temporal tolerance
  final ConceptState _descending = ConceptState('descending', persistenceFrames: 4, dropoutTolerance: 3);
  final ConceptState _deepFlexion = ConceptState('deep_flexion', persistenceFrames: 3, dropoutTolerance: 2);
  final ConceptState _ascending = ConceptState('ascending', persistenceFrames: 3, dropoutTolerance: 2);
  final ConceptState _bodyRisingFast = ConceptState('body_rising_fast', persistenceFrames: 2, dropoutTolerance: 2);
  final ConceptState _airborne = ConceptState('airborne_candidate', persistenceFrames: 2, dropoutTolerance: 3);
  final ConceptState _grounded = ConceptState('grounded_candidate', persistenceFrames: 2, dropoutTolerance: 2);
  final ConceptState _kneesExtending = ConceptState('knees_extending', persistenceFrames: 3, dropoutTolerance: 2);
  final ConceptState _standingLike = ConceptState('standing_like', persistenceFrames: 2, dropoutTolerance: 3);
  final ConceptState _athleticStance = ConceptState('athletic_stance', persistenceFrames: 3, dropoutTolerance: 3);

  JsqV2Phase _phase = JsqV2Phase.idle;
  int _repCount = 0;
  int _framesInPhase = 0;

  // Failure tracking
  final List<RepFailureExplanation> _failures = [];
  int _attemptNumber = 0;
  Map<String, ConceptResult>? _lastConcepts;

  int get currentValue => _repCount < target ? _repCount : target;
  int get repCount => _repCount;
  List<RepFailureExplanation> get failures => _failures;
  JsqV2Phase get phase => _phase;

  void start() {
    _extractor._history.clear();
    _extractor._baselineEstablished = false;
    _extractor._baselineSamples = 0;
    _extractor._baselineAnkleY = 0;
    _extractor._airborneTracker.reset();
    _descending.reset();
    _deepFlexion.reset();
    _ascending.reset();
    _bodyRisingFast.reset();
    _airborne.reset();
    _grounded.reset();
    _kneesExtending.reset();
    _standingLike.reset();
    _athleticStance.reset();
    _phase = JsqV2Phase.idle;
    _repCount = 0;
    _framesInPhase = 0;
    _failures.clear();
    _attemptNumber = 0;
    _lastConcepts = null;
  }

  void update(NuvoPoseFrame frame) {
    final concepts = _extractor.evaluate(frame);
    _lastConcepts = {for (final c in concepts) c.name: c};

    // Update temporal concept states
    for (final c in concepts) {
      _updateConceptState(c);
    }

    _framesInPhase++;

    switch (_phase) {
      case JsqV2Phase.idle:
        _handleIdle();
      case JsqV2Phase.compression:
        _handleCompression();
      case JsqV2Phase.ascent:
        _handleAscent();
      case JsqV2Phase.airborne:
        _handleAirborne();
      case JsqV2Phase.landing:
        _handleLanding();
      case JsqV2Phase.rearm:
        _handleRearm();
    }
  }

  void _updateConceptState(ConceptResult c) {
    switch (c.name) {
      case 'descending':
        _descending.update(c);
      case 'deep_flexion':
        _deepFlexion.update(c);
      case 'ascending':
        _ascending.update(c);
      case 'body_rising_fast':
        _bodyRisingFast.update(c);
      case 'airborne_candidate':
        _airborne.update(c);
      case 'grounded_candidate':
        _grounded.update(c);
      case 'knees_extending':
        _kneesExtending.update(c);
      case 'standing_like':
        _standingLike.update(c);
      case 'athletic_stance':
        _athleticStance.update(c);
    }
  }

  void _handleIdle() {
    // Start a rep attempt when we see descent or deep flexion.
    // No standing gate — the concept state machine's airborne requirement
    // is the primary confuser filter.
    if (_descending.active || _deepFlexion.active) {
      _attemptNumber++;
      _phase = JsqV2Phase.compression;
      _framesInPhase = 0;
    }
  }

  void _handleCompression() {
    // Compression: hips descending, knees flexing, or deep flexion reached.
    // Transition to ascent when body starts rising or knees extend.
    if (_ascending.active || _bodyRisingFast.active || _kneesExtending.active) {
      _phase = JsqV2Phase.ascent;
      _framesInPhase = 0;
    } else if (_framesInPhase > 30) {
      // Stuck in compression too long — abort
      _recordFailure('compression_timeout', JsqV2Phase.compression);
      _phase = JsqV2Phase.idle;
      _framesInPhase = 0;
    }
  }

  void _handleAscent() {
    // Ascent: body rising, knees extending.
    // Transition to airborne when ankles leave ground AND body was rising fast
    // at some point during ascent. The peak check tolerates velocity timing
    // noise while rejecting deep squats (which never have explosive ascent).
    if (_airborne.active && _bodyRisingFast.peakConfidence > 0.15) {
      _phase = JsqV2Phase.airborne;
      _framesInPhase = 0;
    } else if (_grounded.active && _framesInPhase > 8) {
      // Never went airborne — could be a squat without jump.
      // Check if we had any airborne evidence at all.
      if (_airborne.peakConfidence < 0.3) {
        _recordFailure('airborne_not_detected', JsqV2Phase.ascent);
        _phase = JsqV2Phase.rearm;
        _framesInPhase = 0;
      }
    } else if (_framesInPhase > 20) {
      _recordFailure('ascent_timeout', JsqV2Phase.ascent);
      _phase = JsqV2Phase.rearm;
      _framesInPhase = 0;
    }
  }

  void _handleAirborne() {
    // Airborne: ankles above baseline.
    // Transition to landing when ankles return to grounded.
    if (_grounded.active) {
      _phase = JsqV2Phase.landing;
      _framesInPhase = 0;
    } else if (_framesInPhase > 15) {
      // Airborne too long — likely camera motion or pose error
      _recordFailure('airborne_timeout', JsqV2Phase.airborne);
      _phase = JsqV2Phase.rearm;
      _framesInPhase = 0;
    }
  }

  void _handleLanding() {
    // Landing: grounded again after airborne.
    // Count the rep and transition to rearm.
    _repCount++;
    _phase = JsqV2Phase.rearm;
    _framesInPhase = 0;
  }

  void _handleRearm() {
    // Rearm: wait for stable standing/athletic stance before next rep.
    if (_standingLike.active || _athleticStance.active) {
      if (_framesInPhase >= 2) {
        _phase = JsqV2Phase.idle;
        _framesInPhase = 0;
      }
    } else if (_framesInPhase > 20) {
      // Force rearm after timeout
      _phase = JsqV2Phase.idle;
      _framesInPhase = 0;
    }
  }

  void _recordFailure(String reason, JsqV2Phase failedPhase) {
    _failures.add(RepFailureExplanation(
      repNumber: _attemptNumber,
      failedConcept: reason,
      failedConfidence: _lastConcepts?['airborne_candidate']?.confidence ?? 0,
      conceptSnapshot: _lastConcepts ?? {},
      failedPhase: failedPhase,
    ));
  }
}

// ============================================================================
// HEAD-TO-HEAD TEST HARNESS
// ============================================================================

void main() {
  final realDir = 'test/motion_qa/fixtures/real';
  final manifestPath = 'test/motion_qa/fixtures/manifest.json';

  group('Concept Detector V2 — Head-to-Head', () {
    late List<ReplayFixture> realFixtures;
    late List<ReplayFixture> syntheticFixtures;

    setUpAll(() {
      // Load real fixtures
      realFixtures = [];
      final dir = Directory(realDir);
      if (dir.existsSync()) {
        for (final file in dir.listSync()) {
          if (!file.path.endsWith('.json') || file.path.contains('import_log')) {
            continue;
          }
          final json = jsonDecode(File(file.path).readAsStringSync())
              as Map<String, dynamic>;
          realFixtures.add(ReplayFixture.fromJsonString(
              const JsonEncoder().convert(json)));
        }
      }

      // Load synthetic jump squat fixtures
      syntheticFixtures = [];
      final manifestFile = File(manifestPath);
      if (manifestFile.existsSync()) {
        final manifest = jsonDecode(manifestFile.readAsStringSync())
            as Map<String, dynamic>;
        for (final entry in manifest['fixtures'] as List<dynamic>) {
          final m = entry as Map<String, dynamic>;
          final fid = m['id'] as String;
          if (m['movement'] != 'jump_squats') continue;
          if (!(m['shouldMatch'] as bool)) continue;
          if (fid.contains('__')) continue;
          final fpath = 'test/motion_qa/fixtures/$fid.json';
          final file = File(fpath);
          if (!file.existsSync()) continue;
          final json = jsonDecode(file.readAsStringSync())
              as Map<String, dynamic>;
          syntheticFixtures
              .add(ReplayFixture.fromJsonString(jsonEncode(json)));
        }
      }
    });

    test('JSQ V2 vs Production — per-clip comparison', () {
      final jsqFixtures = realFixtures
          .where((f) => f.movement == 'jump_squats')
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

      // Production validator
      final prodValidator = MultiPhaseSequenceValidator(
        activity: AiMotionActivity.jumpSquats,
        targetValue: 99,
        definitions: (airborne) => [buildJumpSquatDefinition(airborne)],
        statusText: 'Production JSQ',
        coachingTextActive: '',
        coachingTextIncomplete: '',
      );

      // V2 detector
      final v2Detector = JumpSquatV2Detector(target: 99);

      print('\n=== HEAD-TO-HEAD: Production vs V2 ===');
      print(
          'clip                       truth   prod   v2    v2_failures');
      print('-' * 75);

      var totalExpected = 0;
      var totalProd = 0;
      var totalV2 = 0;
      var v2ExactMatches = 0;
      var prodExactMatches = 0;

      for (final fixture in jsqFixtures) {
        // Run production
        prodValidator.start();
        for (final frame in fixture.frames) {
          prodValidator.update(frame.toPoseFrame());
        }
        final prodReps = prodValidator.currentValue;

        // Run V2
        v2Detector.start();
        for (final frame in fixture.frames) {
          v2Detector.update(frame.toPoseFrame());
        }
        final v2Reps = v2Detector.repCount;
        final v2Failures = v2Detector.failures.length;

        totalExpected += fixture.expected.reps;
        totalProd += prodReps;
        totalV2 += v2Reps;

        if (prodReps == fixture.expected.reps) prodExactMatches++;
        if (v2Reps == fixture.expected.reps) v2ExactMatches++;

        final prodMark = prodReps == fixture.expected.reps ? '✓' : ' ';
        final v2Mark = v2Reps == fixture.expected.reps ? '✓' : ' ';

        print(
            '${fixture.id.padRight(26)} ${fixture.expected.reps.toString().padLeft(5)}   ${prodReps.toString().padLeft(5)}$prodMark  ${v2Reps.toString().padLeft(5)}$v2Mark   $v2Failures failures');
      }

      print('-' * 75);
      final prodRecall = (totalProd / totalExpected * 100).toStringAsFixed(1);
      final v2Recall = (totalV2 / totalExpected * 100).toStringAsFixed(1);
      print(
          'TOTAL                      ${totalExpected.toString().padLeft(5)}   ${totalProd.toString().padLeft(5)}    ${totalV2.toString().padLeft(5)}');
      print(
          'RECALL                                          ${prodRecall.padLeft(6)}%  ${v2Recall.padLeft(6)}%');
      print(
          'EXACT MATCHES                                  ${prodExactMatches.toString().padLeft(6)}    ${v2ExactMatches.toString().padLeft(6)}');

      // Print V2 failure explanations
      print('\n=== V2 FAILURE EXPLANATIONS ===');
      for (final fixture in jsqFixtures) {
        v2Detector.start();
        for (final frame in fixture.frames) {
          v2Detector.update(frame.toPoseFrame());
        }
        if (v2Detector.failures.isNotEmpty) {
          print('\n${fixture.id} (expected ${fixture.expected.reps}, detected ${v2Detector.repCount}):');
          for (final f in v2Detector.failures.take(5)) {
            print('  $f');
          }
        }
      }
    });

    test('JSQ V2 — confuser false accepts', () {
      final confuserMovements = <String>[
        'normal_squats', 'deep_squats', 'vertical_jumps',
        'jumping_jacks', 'squat_jacks', 'lunges',
      ];

      final v2Detector = JumpSquatV2Detector(target: 99);

      print('\n=== V2 CONFUSER FALSE ACCEPTS ===');
      for (final mv in confuserMovements) {
        final clips = realFixtures.where((f) => f.movement == mv).toList();
        var totalReps = 0;
        for (final fixture in clips) {
          v2Detector.start();
          for (final frame in fixture.frames) {
            v2Detector.update(frame.toPoseFrame());
          }
          totalReps += v2Detector.repCount;
        }
        if (totalReps > 0) {
          print('  $mv: $totalReps false reps (${clips.length} clips)');
        } else {
          print('  $mv: 0 (clean)');
        }
      }
    });

    test('JSQ V2 — synthetic regression', () {
      final v2Detector = JumpSquatV2Detector(target: 99);
      var passed = 0;
      for (final fixture in syntheticFixtures) {
        v2Detector.start();
        for (final frame in fixture.frames) {
          v2Detector.update(frame.toPoseFrame());
        }
        if (v2Detector.repCount == fixture.expected.reps) passed++;
      }
      final rate = syntheticFixtures.isEmpty
          ? 0.0
          : passed / syntheticFixtures.length * 100;
      print('\n=== V2 SYNTHETIC ===');
      print('  Passed: $passed/${syntheticFixtures.length} (${rate.toStringAsFixed(1)}%)');
    });

    test('JSQ V2 — per-clip concept trace', () {
      // For each JSQ clip, print the phase transitions and concept states
      final jsqFixtures = realFixtures
          .where((f) => f.movement == 'jump_squats')
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

      print('\n=== V2 PER-CLIP CONCEPT TRACE ===');
      for (final fixture in jsqFixtures) {
        final detector = JumpSquatV2Detector(target: 99);
        detector.start();

        final phaseLog = <String>[];
        JsqV2Phase? prevPhase;
        var phaseStartFrame = 0;

        for (var i = 0; i < fixture.frames.length; i++) {
          detector.update(fixture.frames[i].toPoseFrame());
          if (detector.phase != prevPhase) {
            if (prevPhase != null) {
              phaseLog.add(
                  '${prevPhase.name}[$phaseStartFrame-${i - 1}]');
            }
            prevPhase = detector.phase;
            phaseStartFrame = i;
          }
        }
        if (prevPhase != null) {
          phaseLog.add('${prevPhase.name}[$phaseStartFrame-${fixture.frames.length - 1}]');
        }

        print('\n${fixture.id} (expected ${fixture.expected.reps}, detected ${detector.repCount}):');
        print('  phases: ${phaseLog.join(" → ")}');
        if (detector.failures.isNotEmpty) {
          print('  failures:');
          for (final f in detector.failures.take(3)) {
            print('    rep ${f.repNumber}: FAILED at ${f.failedPhase.name} — ${f.failedConcept}');
          }
        }
      }
    });

    test('save V2 results', () {
      final jsqFixtures = realFixtures
          .where((f) => f.movement == 'jump_squats')
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

      final prodValidator = MultiPhaseSequenceValidator(
        activity: AiMotionActivity.jumpSquats,
        targetValue: 99,
        definitions: (airborne) => [buildJumpSquatDefinition(airborne)],
        statusText: 'Production JSQ',
        coachingTextActive: '',
        coachingTextIncomplete: '',
      );

      final v2Detector = JumpSquatV2Detector(target: 99);

      final results = <Map<String, dynamic>>[];
      for (final fixture in jsqFixtures) {
        prodValidator.start();
        for (final frame in fixture.frames) {
          prodValidator.update(frame.toPoseFrame());
        }
        final prodReps = prodValidator.currentValue;

        v2Detector.start();
        for (final frame in fixture.frames) {
          v2Detector.update(frame.toPoseFrame());
        }
        final v2Reps = v2Detector.repCount;

        results.add({
          'id': fixture.id,
          'expected': fixture.expected.reps,
          'production': prodReps,
          'v2': v2Reps,
          'v2_failures': v2Detector.failures
              .map((f) => {
                    'rep': f.repNumber,
                    'phase': f.failedPhase.name,
                    'reason': f.failedConcept,
                  })
              .toList(),
        });
      }

      // Confusers
      final confuserResults = <String, int>{};
      for (final mv in [
        'normal_squats', 'deep_squats', 'vertical_jumps',
        'jumping_jacks', 'squat_jacks', 'lunges',
      ]) {
        var total = 0;
        for (final fixture in realFixtures.where((f) => f.movement == mv)) {
          v2Detector.start();
          for (final frame in fixture.frames) {
            v2Detector.update(frame.toPoseFrame());
          }
          total += v2Detector.repCount;
        }
        confuserResults[mv] = total;
      }

      // Synthetic
      var synthPassed = 0;
      for (final fixture in syntheticFixtures) {
        v2Detector.start();
        for (final frame in fixture.frames) {
          v2Detector.update(frame.toPoseFrame());
        }
        if (v2Detector.repCount == fixture.expected.reps) synthPassed++;
      }

      final output = {
        'per_clip': results,
        'confusers': confuserResults,
        'synthetic_pass': synthPassed,
        'synthetic_total': syntheticFixtures.length,
      };

      final outputPath = 'test/motion_qa/v2_head_to_head_results.json';
      File(outputPath).writeAsStringSync(jsonEncode(output));
      print('\n=== V2 RESULTS SAVED ===');
      print('  File: $outputPath');
    });
  });
}
