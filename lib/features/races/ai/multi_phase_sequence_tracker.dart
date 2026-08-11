import '../data/ai_motion_models.dart';
import 'airborne_state_tracker.dart';
import 'motion_validators.dart';

/// A single phase in an ordered multi-phase movement sequence.
///
/// Each phase has a [condition] (reusing the existing [PoseCondition] system)
/// and a [stableFrames] requirement — the number of consecutive frames where
/// the condition must evaluate true before the tracker advances to the next
/// phase.
class SequencePhaseDefinition {
  const SequencePhaseDefinition({
    required this.id,
    required this.condition,
    this.stableFrames = 3,
  });

  /// Unique identifier for this phase (e.g., 'STANDING', 'SQUAT', 'AIRBORNE').
  final String id;

  /// Condition that must be true for this phase to be detected.
  /// Reuses the existing [PoseCondition] hierarchy:
  /// [ComparisonCondition], [BooleanCondition], [AndCondition], [OrCondition],
  /// and [AirborneCondition] (for flight-phase integration).
  final PoseCondition condition;

  /// Consecutive frames where [condition] must be true before advancing.
  /// Defaults to 3, matching [RepCounterStateMachine].
  final int stableFrames;
}

/// A complete multi-phase movement sequence definition.
///
/// Defines an ordered list of [SequencePhaseDefinition]s plus a
/// [resetCondition] that must be satisfied after completion before another
/// cycle can begin.
///
/// Example (Jump Squat):
/// ```
/// phases: [STANDING, SQUAT, AIRBORNE, LANDING]
/// resetCondition: standingCondition
/// cooldownFrames: 3
/// ```
///
/// The tracker counts one completion each time all phases are satisfied in
/// order, then enters cooldown. After cooldown, the [resetCondition] must
/// evaluate true before a new cycle starts.
class MultiPhaseSequenceDefinition {
  const MultiPhaseSequenceDefinition({
    required this.phases,
    required this.resetCondition,
    required this.requiredLandmarks,
    this.cooldownFrames = 3,
    this.noiseGraceFrames = 0,
  });

  /// Ordered list of phases. Phase 0 is the start phase.
  final List<SequencePhaseDefinition> phases;

  /// Condition that must be true to allow a new cycle to start after
  /// cooldown. Typically the first phase's condition (e.g., standing).
  final PoseCondition resetCondition;

  /// Landmarks that must be present (with sufficient likelihood) for any
  /// phase evaluation to occur. Missing landmarks = no progress.
  final List<String> requiredLandmarks;

  /// Minimum frames to wait after completion before checking resetCondition.
  /// Prevents multiple completions from holding the final pose.
  final int cooldownFrames;

  /// Number of non-matching (noise) frames tolerated before resetting
  /// candidate frame progress. 0 = strict consecutive (original behavior).
  /// 1 = allow 1 noise frame in a row without losing progress.
  /// Set based on replay evidence of real-world noise patterns.
  final int noiseGraceFrames;
}

/// State of the multi-phase sequence tracker.
enum SequenceState {
  /// Waiting for the first phase condition to be met.
  /// No progress has been made yet.
  idle,

  /// Progressing through the phase sequence.
  tracking,

  /// All phases completed. In cooldown before reset condition check.
  completed,

  /// Cooldown elapsed. Waiting for [resetCondition] to become true.
  awaitingReset,
}

/// Tracks progress through an ordered N-phase movement sequence.
///
/// This is a generic temporal state machine that extends the
/// [RepCounterStateMachine] pattern from 2 phases (start/active) to N
/// ordered phases. It is purely frame-based — no wall-clock timing.
///
/// ## Policies
///
/// **Noise policy (UNKNOWN frames):** When no phase condition matches, the
/// tracker stays in its current phase but resets the candidate frame count.
/// This matches [RepCounterStateMachine] which returns early on `unknown`.
/// A brief noise frame does not destroy phase progress, but the user must
/// re-satisfy the current phase condition to resume advancing.
///
/// **Wrong-phase policy (out-of-order):** When a frame matches a phase that
/// is neither the current phase nor the expected next phase, the tracker
/// resets to [SequenceState.idle] with zero progress. This is the simplest
/// deterministic policy — no rewind logic, no partial credit.
///
/// **Stability model:** Each phase requires [stableFrames] consecutive
/// matching frames before advancing. Reuses the candidate/stable pattern
/// from [RepCounterStateMachine].
///
/// **Completion + rearm:** When the final phase's stability requirement is
/// met, [completionCount] increments and the tracker enters
/// [SequenceState.completed] for [cooldownFrames] frames. After cooldown,
/// the tracker enters [SequenceState.awaitingReset] until
/// [MultiPhaseSequenceDefinition.resetCondition] evaluates true, then
/// returns to [SequenceState.idle] ready for the next cycle.
///
/// **Missing landmarks:** If required landmarks are absent or low-likelihood,
/// no state change occurs (fail-safe).
class MultiPhaseSequenceTracker {
  MultiPhaseSequenceTracker({required this.definition});

  final MultiPhaseSequenceDefinition definition;

  SequenceState _state = SequenceState.idle;
  int _currentPhaseIndex = -1;
  int _candidatePhaseIndex = -1;
  int _candidateFrames = 0;
  int _completionCount = 0;
  int _cooldownFramesRemaining = 0;
  int _noiseGraceRemaining = 0;

  /// Current state of the tracker.
  SequenceState get state => _state;

  /// Index of the current phase (-1 when idle or awaiting reset).
  int get currentPhaseIndex => _currentPhaseIndex;

  /// ID of the current phase, or null when not tracking.
  String? get currentPhaseId {
    if (_currentPhaseIndex < 0 ||
        _currentPhaseIndex >= definition.phases.length) {
      return null;
    }
    return definition.phases[_currentPhaseIndex].id;
  }

  /// Number of complete sequences detected.
  int get completionCount => _completionCount;

  /// Whether the tracker is in cooldown after a completion.
  bool get isInCooldown => _state == SequenceState.completed;

  /// Resets all state to initial conditions.
  void reset() {
    _state = SequenceState.idle;
    _currentPhaseIndex = -1;
    _candidatePhaseIndex = -1;
    _candidateFrames = 0;
    _completionCount = 0;
    _cooldownFramesRemaining = 0;
    _noiseGraceRemaining = 0;
  }

  /// Processes a single pose frame and updates sequence progress.
  ///
  /// Returns true if a completion occurred on this frame.
  ///
  /// [temporalUpdaters] is an optional list of callbacks that should be
  /// invoked once per frame BEFORE phase conditions are evaluated. This is
  /// how [AirborneStateTracker] participates — the caller passes its
  /// `update` method here so the tracker's state is fresh when the
  /// [AirborneCondition] reads `isAirborne`.
  bool update(
    NuvoPoseFrame frame, {
    List<void Function(NuvoPoseFrame)>? temporalUpdaters,
  }) {
    // Fail-safe: missing required landmarks = no progress.
    if (!frame.hasPoints(definition.requiredLandmarks)) {
      return false;
    }

    // Update temporal primitives (e.g., AirborneStateTracker) once per frame.
    if (temporalUpdaters != null) {
      for (final updater in temporalUpdaters) {
        updater(frame);
      }
    }

    // Handle cooldown after completion.
    if (_state == SequenceState.completed) {
      _cooldownFramesRemaining--;
      if (_cooldownFramesRemaining <= 0) {
        _state = SequenceState.awaitingReset;
      }
      return false;
    }

    // After cooldown, wait for reset condition before rearming.
    if (_state == SequenceState.awaitingReset) {
      final features = PoseFeatureExtractor(frame);
      if (definition.resetCondition.evaluate(features)) {
        _state = SequenceState.idle;
        _currentPhaseIndex = -1;
        _candidatePhaseIndex = -1;
        _candidateFrames = 0;
      }
      return false;
    }

    // Evaluate phase conditions to find which phase matches.
    //
    // Priority: the expected next phase is checked first, then the current
    // phase (for holding), then all others in order. This ensures that when
    // multiple phases could match (e.g., a jump squat's airborne body still
    // looks "standing-like" by hipToKneeRatio), the expected-next phase wins.
    final features = PoseFeatureExtractor(frame);
    int matchedPhaseIndex = -1;
    final expectedNext = _currentPhaseIndex + 1;

    // 1. Check expected next phase first.
    if (expectedNext < definition.phases.length &&
        definition.phases[expectedNext].condition.evaluate(features)) {
      matchedPhaseIndex = expectedNext;
    }
    // 2. Check current phase (holding).
    else if (_currentPhaseIndex >= 0 &&
        _currentPhaseIndex < definition.phases.length &&
        definition.phases[_currentPhaseIndex].condition.evaluate(features)) {
      matchedPhaseIndex = _currentPhaseIndex;
    }
    // 3. Check all other phases in order.
    else {
      for (var i = 0; i < definition.phases.length; i++) {
        if (i == _currentPhaseIndex || i == expectedNext) continue;
        if (definition.phases[i].condition.evaluate(features)) {
          matchedPhaseIndex = i;
          break;
        }
      }
    }

    // Noise policy: no phase matches → use grace if available, else reset.
    if (matchedPhaseIndex == -1) {
      if (_noiseGraceRemaining > 0) {
        _noiseGraceRemaining--;
        // Grace: keep candidate frames, tolerate this noise frame.
        return false;
      }
      _candidateFrames = 0;
      return false;
    }
    // Reset grace on a matching frame.
    _noiseGraceRemaining = definition.noiseGraceFrames;

    // Wrong-phase policy: matched phase is neither current nor expected next.
    // (expectedNext was computed above for priority matching.)
    if (matchedPhaseIndex != _currentPhaseIndex &&
        matchedPhaseIndex != expectedNext) {
      // Backward match (earlier phase) — could be noise during a transient
      // phase like AIRBORNE where ankle dropout causes a false match on an
      // earlier phase (e.g., STANDING). Use grace if available.
      if (matchedPhaseIndex < _currentPhaseIndex &&
          _noiseGraceRemaining > 0) {
        _noiseGraceRemaining--;
        return false;
      }
      _state = SequenceState.idle;
      _currentPhaseIndex = -1;
      _candidatePhaseIndex = -1;
      _candidateFrames = 0;
      return false;
    }

    // Stability model: count consecutive frames for candidate phase.
    if (matchedPhaseIndex == _candidatePhaseIndex) {
      _candidateFrames++;
    } else {
      _candidatePhaseIndex = matchedPhaseIndex;
      _candidateFrames = 1;
    }

    final candidatePhase = definition.phases[matchedPhaseIndex];
    if (_candidateFrames < candidatePhase.stableFrames) {
      return false;
    }

    // Stability requirement met — advance to the matched phase.
    _currentPhaseIndex = matchedPhaseIndex;
    _state = SequenceState.tracking;
    _candidatePhaseIndex = matchedPhaseIndex + 1;
    _candidateFrames = 0;

    // Completion: final phase reached.
    if (_currentPhaseIndex == definition.phases.length - 1) {
      _completionCount++;
      _state = SequenceState.completed;
      _cooldownFramesRemaining = definition.cooldownFrames;
      return true;
    }

    return false;
  }
}

/// A [PoseCondition] that evaluates to true when the associated
/// [AirborneStateTracker] is in the airborne phase.
///
/// This is the adapter that bridges the temporal [AirborneStateTracker]
/// primitive into the per-frame [PoseCondition] system used by
/// [MultiPhaseSequenceTracker].
///
/// **Important:** This condition does NOT update the tracker. The caller
/// must update the tracker once per frame via the `temporalUpdaters`
/// parameter of [MultiPhaseSequenceTracker.update]. This ensures the
/// tracker is updated exactly once per frame regardless of how many
/// conditions reference it.
class AirborneCondition extends PoseCondition {
  const AirborneCondition(this.tracker);

  final AirborneStateTracker tracker;

  @override
  bool evaluate(PoseFeatureExtractor features) => tracker.isAirborne;
}

/// A [PoseCondition] that evaluates to true when the associated
/// [AirborneStateTracker] is NOT in the airborne phase (i.e., grounded or
/// awaiting baseline).
///
/// Used to distinguish "landing" (standing AND grounded) from "standing
/// while airborne" during jump sequences.
class GroundedCondition extends PoseCondition {
  const GroundedCondition(this.tracker);

  final AirborneStateTracker tracker;

  @override
  bool evaluate(PoseFeatureExtractor features) => !tracker.isAirborne;
}

/// A [PoseCondition] that negates another condition.
class NotCondition extends PoseCondition {
  const NotCondition(this.condition);

  final PoseCondition condition;

  @override
  bool evaluate(PoseFeatureExtractor features) => !condition.evaluate(features);
}
