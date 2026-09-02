import 'dart:math' as math;

import '../data/ai_motion_models.dart';

/// Phase of the flight/air detection state machine.
enum AirbornePhase {
  /// Baseline ankle position has not yet been established.
  /// No flight can be declared in this phase.
  awaitingBaseline,

  /// Both ankles are near the established baseline (ground contact).
  /// Baseline is slowly updated to track standing position.
  grounded,

  /// Both ankles have risen above the flight threshold relative to baseline.
  /// Baseline is frozen to prevent drift during the jump.
  airborne,
}

/// Reusable flight-phase primitive that detects when both feet leave the
/// ground relative to a stable standing ankle baseline.
///
/// This is a **baseline-relative** detector — it does NOT use a raw fixed
/// ankle Y threshold. Instead, it establishes a standing ankle baseline
/// over multiple stable frames, then declares airborne when both ankles
/// rise above a torso-relative threshold from that baseline.
///
/// ## Design
///
/// - **Baseline**: Average ankle Y over [baselineFrames] consecutive stable
///   frames (where "stable" means ankle Y varies less than [jitterTolerance]
///   from the previous frame). The baseline represents the ground-contact
///   ankle position.
/// - **Flight threshold**: `max(minFlightThreshold, torsoHeight *
///   flightThresholdRatio)`. Both ankles must independently rise above
///   this threshold from the baseline. This is body-scale-relative,
///   making it invariant to camera distance and body size.
/// - **Grounded tolerance**: `max(minGroundedTolerance, torsoHeight *
///   groundedToleranceRatio)`. Both ankles within this tolerance of
///   baseline = grounded. Baseline is updated via EMA when grounded.
/// - **Landing**: Transition from airborne to grounded when both ankles
///   return within grounded tolerance. Increments [flightCount].
///
/// ## Rejection properties
///
/// - **One-foot lifts** (high knees, marching, calf raises): Only one
///   ankle rises → the AND of both rises exceeding threshold fails.
/// - **Squats**: Ankles stay on ground, hips drop → ankle Y unchanged.
/// - **Jumping jacks**: Feet spread horizontally but stay on ground.
/// - **Camera movement**: Small shifts produce small rises in both ankles
///   that stay below the flight threshold. The baseline EMA adapts.
/// - **Pose jitter**: Noise (~0.01-0.02) is below the flight threshold
///   (~0.03+).
/// - **Missing ankles**: If either ankle is absent or low-likelihood,
///   no state change occurs (fail-safe).
///
/// ## Timing
///
/// This tracker is purely frame-based — it does not depend on wall-clock
/// timing. All stability requirements are expressed in frame counts,
/// matching the existing [RepCounterStateMachine] pattern.
class AirborneStateTracker {
  AirborneStateTracker({
    this.baselineFrames = 4,
    // Flight threshold = max(minFlightThreshold, torsoHeight * this). 0.18
    // matches the documented spec + the tracker's regression tests and makes
    // a real jump squat / lunge jump clear the bar; 0.25 was silently missing
    // shallow-but-valid jumps. Used only by jump-squat / lunge-jump verifiers.
    this.flightThresholdRatio = 0.18,
    this.groundedToleranceRatio = 0.10,
    this.minFlightThreshold = 0.025,
    this.minGroundedTolerance = 0.015,
    this.jitterTolerance = 0.030,
    this.minLikelihood = 0.35,
    this.baselineEmaAlpha = 0.20,
  });

  /// Consecutive stable frames required to establish the initial baseline.
  final int baselineFrames;

  /// Flight threshold as a fraction of torsoHeight.
  /// Both ankles must rise by at least this fraction of torsoHeight.
  final double flightThresholdRatio;

  /// Grounded tolerance as a fraction of torsoHeight.
  /// Both ankles within this fraction of baseline = grounded.
  final double groundedToleranceRatio;

  /// Absolute floor for the flight threshold (normalized frame units).
  /// Prevents false triggers when torsoHeight is at its clamp minimum.
  final double minFlightThreshold;

  /// Absolute floor for the grounded tolerance (normalized frame units).
  final double minGroundedTolerance;

  /// Maximum consecutive-frame ankle Y variation for baseline stability.
  final double jitterTolerance;

  /// Minimum landmark likelihood to accept a pose point.
  final double minLikelihood;

  /// EMA weight for baseline update when grounded (0.0–1.0).
  /// Higher = faster adaptation. 0.20 = 20% weight to new sample.
  final double baselineEmaAlpha;

  AirbornePhase _phase = AirbornePhase.awaitingBaseline;
  final List<double> _baselineSamples = [];
  double _baselineAnkleY = 0;
  int _flightCount = 0;
  double? _prevAvgAnkleY;

  /// Current phase of the state machine.
  AirbornePhase get phase => _phase;

  /// Whether both feet are currently detected as off the ground.
  bool get isAirborne => _phase == AirbornePhase.airborne;

  /// Whether the standing baseline has been established.
  bool get baselineEstablished => _phase != AirbornePhase.awaitingBaseline;

  /// Number of complete flight events detected (grounded → airborne → grounded).
  int get flightCount => _flightCount;

  /// The current standing ankle Y baseline. Returns 0 if not yet established.
  double get baselineAnkleY => _baselineAnkleY;

  /// Resets all state. Call when starting a new verification session.
  void reset() {
    _phase = AirbornePhase.awaitingBaseline;
    _baselineSamples.clear();
    _baselineAnkleY = 0;
    _flightCount = 0;
    _prevAvgAnkleY = null;
  }

  /// Processes a single pose frame and updates the state machine.
  ///
  /// Requires: leftAnkle, rightAnkle, leftShoulder, rightShoulder,
  /// leftHip, rightHip — all with likelihood >= [minLikelihood].
  /// If any are missing, no state change occurs (fail-safe).
  void update(NuvoPoseFrame frame) {
    final leftAnkle = frame.point('leftAnkle');
    final rightAnkle = frame.point('rightAnkle');
    final leftShoulder = frame.point('leftShoulder');
    final rightShoulder = frame.point('rightShoulder');
    final leftHip = frame.point('leftHip');
    final rightHip = frame.point('rightHip');

    // All required landmarks must be present with sufficient likelihood.
    if (leftAnkle == null ||
        rightAnkle == null ||
        leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      return;
    }
    if (leftAnkle.likelihood < minLikelihood ||
        rightAnkle.likelihood < minLikelihood ||
        leftShoulder.likelihood < minLikelihood ||
        rightShoulder.likelihood < minLikelihood ||
        leftHip.likelihood < minLikelihood ||
        rightHip.likelihood < minLikelihood) {
      return;
    }

    // Body-scale-relative thresholds using the same torsoHeight formula
    // as PoseFeatureExtractor (clamped to [0.12, 0.6]).
    final shoulderY = (leftShoulder.y + rightShoulder.y) / 2;
    final hipY = (leftHip.y + rightHip.y) / 2;
    final torsoHeight = (hipY - shoulderY).abs().clamp(0.12, 0.6);
    final flightThreshold = math.max(
      minFlightThreshold,
      torsoHeight * flightThresholdRatio,
    );
    final groundedTolerance = math.max(
      minGroundedTolerance,
      torsoHeight * groundedToleranceRatio,
    );

    final avgAnkleY = (leftAnkle.y + rightAnkle.y) / 2;
    final leftRise = _baselineAnkleY - leftAnkle.y;
    final rightRise = _baselineAnkleY - rightAnkle.y;

    switch (_phase) {
      case AirbornePhase.awaitingBaseline:
        _handleAwaitingBaseline(avgAnkleY, jitterTolerance);
      case AirbornePhase.grounded:
        _handleGrounded(
          leftRise,
          rightRise,
          avgAnkleY,
          flightThreshold,
          groundedTolerance,
        );
      case AirbornePhase.airborne:
        _handleAirborne(leftRise, rightRise, groundedTolerance);
    }

    _prevAvgAnkleY = avgAnkleY;
  }

  void _handleAwaitingBaseline(double avgAnkleY, double jitter) {
    final prev = _prevAvgAnkleY;
    if (prev != null && (avgAnkleY - prev).abs() > jitter) {
      // Unstable — reset sample collection.
      _baselineSamples.clear();
    }
    _baselineSamples.add(avgAnkleY);
    if (_baselineSamples.length >= baselineFrames) {
      // Baseline = average of stable samples (ground-contact ankle Y).
      _baselineAnkleY =
          _baselineSamples.reduce((a, b) => a + b) / _baselineSamples.length;
      _baselineSamples.clear();
      _phase = AirbornePhase.grounded;
    }
  }

  void _handleGrounded(
    double leftRise,
    double rightRise,
    double avgAnkleY,
    double flightThreshold,
    double groundedTolerance,
  ) {
    // Check for flight: both ankles must rise above threshold.
    if (leftRise > flightThreshold && rightRise > flightThreshold) {
      _phase = AirbornePhase.airborne;
      return;
    }
    // If both ankles are within grounded tolerance, update baseline via EMA.
    if (leftRise.abs() < groundedTolerance &&
        rightRise.abs() < groundedTolerance) {
      _baselineAnkleY =
          _baselineAnkleY * (1 - baselineEmaAlpha) +
          avgAnkleY * baselineEmaAlpha;
    }
    // If one ankle moved but not both above threshold, don't update baseline
    // and don't declare airborne (ambiguous state — could be high knee prep).
  }

  void _handleAirborne(
    double leftRise,
    double rightRise,
    double groundedTolerance,
  ) {
    // Check for landing: both ankles return within grounded tolerance.
    if (leftRise.abs() < groundedTolerance &&
        rightRise.abs() < groundedTolerance) {
      _phase = AirbornePhase.grounded;
      _flightCount++;
    }
    // While airborne, baseline is frozen — no EMA update.
  }
}
