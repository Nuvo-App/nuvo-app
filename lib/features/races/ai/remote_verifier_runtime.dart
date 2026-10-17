import 'dart:math' as math;

import '../data/ai_motion_models.dart';
import 'motion_validators.dart';
import 'remote_verifier_spec.dart';

enum RemoteRuntimeState {
  notReady,
  ready,
  tracking,
  repAccepted,
  holdProgress,
  completed,
  runtimeError,
}

class RemoteVerifierUpdate {
  const RemoteVerifierUpdate({
    required this.state,
    required this.count,
    required this.progress,
    required this.confidence,
    required this.guidance,
    required this.diagnostic,
    this.elapsedMs = 0,
    this.metrics = const {},
  });

  final RemoteRuntimeState state;
  final int count;
  final double progress;
  final double confidence;
  final String guidance;
  final String diagnostic;
  final int elapsedMs;

  /// Live numbers the compiled validator exposes (pace, distance, cadence…).
  /// Only `native_tuned_v1` fills this, so a tuned release keeps the same
  /// on-screen metrics as the compiled motion it re-tunes.
  final Map<String, double> metrics;
}

abstract class RemoteVerifierRuntime {
  RemoteVerifierRuntime({required this.spec, required this.target});

  final RemoteVerifierSpec spec;
  final int target;
  int count = 0;
  bool _started = false;

  void start() => _started = true;

  RemoteVerifierUpdate update(NuvoPoseFrame frame);

  RemoteVerifierUpdate notReady(String diagnostic) => RemoteVerifierUpdate(
    state: RemoteRuntimeState.notReady,
    count: count,
    progress: target == 0 ? 0 : count / target,
    confidence: 0,
    guidance: _friendlyDiagnostic(diagnostic),
    diagnostic: diagnostic,
  );

  String _friendlyDiagnostic(String diagnostic) => switch (diagnostic) {
    'missing_required_regions' =>
      'Step back until the required body regions are visible.',
    'hold_form_lost' => 'Hold the position steadily to keep the count moving.',
    'waiting_for_start' => 'Start from the ready position.',
    'sequence_pose_lost' =>
      'Stay in frame — the sequence restarts when pose is lost.',
    'sequence_rep_timeout' => 'Too slow — restart the motion from the start.',
    'sequence_phase_timeout' =>
      'Move through each part of the motion a little faster.',
    'sequence_phase_lost' => 'Restart the motion from the beginning.',
    _ => 'Keep your movement in frame and try again.',
  };
}

class StateMachineV1Runtime extends RemoteVerifierRuntime {
  StateMachineV1Runtime({required super.spec, required super.target});

  bool _active = false;
  int _candidateFrames = 0;

  @override
  RemoteVerifierUpdate update(NuvoPoseFrame frame) {
    if (!_started) start();
    if (!frame.hasPoints(spec.requiredLandmarks))
      return notReady('missing_required_regions');
    final isStart = _all(spec.startRules, frame);
    final isActive = _all(spec.activeRules, frame);
    if (!_active && isActive) {
      _candidateFrames++;
      if (_candidateFrames >= spec.stableFrames) {
        _active = true;
        _candidateFrames = 0;
      }
    } else if (_active && isStart) {
      _candidateFrames++;
      if (_candidateFrames >= spec.stableFrames) {
        _active = false;
        _candidateFrames = 0;
        count++;
        return _result(RemoteRuntimeState.repAccepted, 0.9, 'rep_accepted');
      }
    } else if ((_active && !isActive) || (!_active && !isStart)) {
      _candidateFrames = 0;
    }
    return _result(
      _active ? RemoteRuntimeState.tracking : RemoteRuntimeState.ready,
      _active ? 0.8 : 0.7,
      'tracking',
    );
  }

  RemoteVerifierUpdate _result(
    RemoteRuntimeState state,
    double confidence,
    String diagnostic,
  ) => RemoteVerifierUpdate(
    state: count >= target ? RemoteRuntimeState.completed : state,
    count: count,
    progress: math.min(1, target == 0 ? 0 : count / target),
    confidence: confidence,
    guidance: count >= target ? 'Target complete.' : 'Keep going.',
    diagnostic: diagnostic,
  );
}

class AlternatingRepV1Runtime extends RemoteVerifierRuntime {
  AlternatingRepV1Runtime({required super.spec, required super.target});

  bool _leftNext = true;
  int _stableFrames = 0;

  @override
  RemoteVerifierUpdate update(NuvoPoseFrame frame) {
    if (!_started) start();
    if (!frame.hasPoints(spec.requiredLandmarks))
      return notReady('missing_required_regions');
    final rules = _leftNext ? spec.leftRules : spec.rightRules;
    if (_all(rules, frame)) {
      _stableFrames++;
      if (_stableFrames >= spec.stableFrames) {
        _stableFrames = 0;
        _leftNext = !_leftNext;
        count++;
        return _result(
          RemoteRuntimeState.repAccepted,
          0.88,
          'alternating_rep_accepted',
        );
      }
    } else {
      _stableFrames = 0;
    }
    return _result(RemoteRuntimeState.tracking, 0.75, 'alternating_tracking');
  }

  RemoteVerifierUpdate _result(
    RemoteRuntimeState state,
    double confidence,
    String diagnostic,
  ) => RemoteVerifierUpdate(
    state: count >= target ? RemoteRuntimeState.completed : state,
    count: count,
    progress: math.min(1, target == 0 ? 0 : count / target),
    confidence: confidence,
    guidance: count >= target
        ? 'Target complete.'
        : 'Alternate sides with control.',
    diagnostic: diagnostic,
  );
}

class HoldV1Runtime extends RemoteVerifierRuntime {
  HoldV1Runtime({required super.spec, required super.target});

  DateTime? _startedAt;
  DateTime? _lastFrame;
  int _heldMs = 0;

  @override
  RemoteVerifierUpdate update(NuvoPoseFrame frame) {
    if (!_started) start();
    if (!_all(spec.holdRules, frame)) {
      _startedAt = null;
      _lastFrame = null;
      return notReady('hold_form_lost');
    }
    final previous = _lastFrame;
    _lastFrame = frame.createdAt;
    _startedAt ??= frame.createdAt;
    if (previous != null) {
      final delta = frame.createdAt.difference(previous).inMilliseconds;
      if (delta >= 0 && delta <= 1000)
        _heldMs = math.min(spec.maxHoldMs, _heldMs + delta);
    }
    final progress = math
        .min(1, _heldMs / math.max(1, target * 1000))
        .toDouble();
    final complete = _heldMs >= target * 1000;
    return RemoteVerifierUpdate(
      state: complete
          ? RemoteRuntimeState.completed
          : RemoteRuntimeState.holdProgress,
      count: (_heldMs / 1000).floor(),
      progress: progress,
      confidence: 0.86,
      guidance: complete ? 'Target complete.' : 'Hold steady.',
      diagnostic: 'hold_progress',
      elapsedMs: _heldMs,
    );
  }
}

/// Executes a strict linear `sequence_match_v1` phase chain.
///
/// Reset semantics — the state machine only counts a rep when a full valid
/// sequence actually happened:
///
/// * The sequence "begins" only when phase 0's predicates (plus the optional
///   [RemoteVerifierSpec.startRules] readiness gate) hold for
///   `minDwellFrames` consecutive frames. A frame that satisfies a later
///   phase can never count on its own — the index only moves 0→1→…→complete.
/// * Once begun, exceeding `repTimeoutMs`, a phase's `maxDwellMs`, or more
///   than `breakToleranceFrames` consecutive predicate misses resets to
///   phase 0 with a reason diagnostic.
/// * Missing required landmarks PAUSE the machine (dwell/miss counters do
///   not move) up to `lostPoseMs`; beyond that the sequence resets.
/// * Within break tolerance a miss resets the dwell counter but not the
///   sequence — the phase still needs its full run of consecutive holds.
///   Hysteresis: hovering around a threshold stalls progress instead of
///   chattering the machine, and only a sustained break resets it.
class SequenceMatchV1Runtime extends RemoteVerifierRuntime {
  SequenceMatchV1Runtime({required super.spec, required super.target});

  int _phaseIndex = 0;
  int _dwellFrames = 0;
  int _missFrames = 0;
  DateTime? _sequenceStartedAt;
  DateTime? _phaseEnteredAt;
  DateTime? _lostSince;

  bool get _began => _phaseIndex > 0;

  void _resetSequence() {
    _phaseIndex = 0;
    _dwellFrames = 0;
    _missFrames = 0;
    _sequenceStartedAt = null;
    _phaseEnteredAt = null;
  }

  @override
  RemoteVerifierUpdate update(NuvoPoseFrame frame) {
    if (!_started) start();
    if (!frame.hasPoints(spec.requiredLandmarks)) {
      // Lost pose: idle (pre-sequence) stays notReady; mid-sequence pauses
      // until lostPoseMs, then resets — a rep must be seen end-to-end.
      if (!_began) return notReady('missing_required_regions');
      _lostSince ??= frame.createdAt;
      if (frame.createdAt.difference(_lostSince!).inMilliseconds >
          spec.lostPoseMs) {
        _resetSequence();
        return notReady('sequence_pose_lost');
      }
      return _result(RemoteRuntimeState.tracking, 'sequence_pose_pause');
    }
    _lostSince = null;

    final phase = spec.phases[_phaseIndex];

    // Whole-sequence timeout — applies only after a sequence has begun;
    // waiting indefinitely at phase 0 is allowed.
    if (_began &&
        _sequenceStartedAt != null &&
        frame.createdAt.difference(_sequenceStartedAt!).inMilliseconds >
            spec.repTimeoutMs) {
      _resetSequence();
      return _result(RemoteRuntimeState.ready, 'sequence_rep_timeout');
    }

    // Per-phase time cap — same rule: only mid-sequence.
    if (_began &&
        phase.maxDwellMs != null &&
        _phaseEnteredAt != null &&
        frame.createdAt.difference(_phaseEnteredAt!).inMilliseconds >
            phase.maxDwellMs!) {
      _resetSequence();
      return _result(RemoteRuntimeState.ready, 'sequence_phase_timeout');
    }

    final satisfied =
        _satisfied(phase, frame) &&
        (_began || spec.startRules.isEmpty || _all(spec.startRules, frame));
    if (satisfied) {
      _missFrames = 0;
      _dwellFrames++;
      if (_dwellFrames >= phase.minDwellFrames) {
        _dwellFrames = 0;
        if (phase.completesRep) {
          count++;
          _resetSequence();
          return _result(RemoteRuntimeState.repAccepted, 'rep_accepted');
        }
        _phaseIndex++;
        _phaseEnteredAt = frame.createdAt;
        _sequenceStartedAt ??= frame.createdAt;
        return _result(RemoteRuntimeState.tracking, 'sequence_phase_advance');
      }
    } else {
      _dwellFrames = 0;
      _missFrames++;
      if (_missFrames > phase.breakToleranceFrames) {
        _resetSequence();
        return _result(RemoteRuntimeState.ready, 'sequence_phase_lost');
      }
    }
    return _result(
      _began ? RemoteRuntimeState.tracking : RemoteRuntimeState.ready,
      'sequence_phase_$_phaseIndex',
    );
  }

  bool _satisfied(SequencePhase phase, NuvoPoseFrame frame) =>
      phase.predicates.every((predicate) => predicate.matches(frame));

  RemoteVerifierUpdate _result(RemoteRuntimeState state, String diagnostic) =>
      RemoteVerifierUpdate(
        state: count >= target ? RemoteRuntimeState.completed : state,
        count: count,
        progress: math.min(1, target == 0 ? 0 : count / target),
        confidence: state == RemoteRuntimeState.repAccepted ? 0.9 : 0.78,
        guidance: count >= target
            ? 'Target complete.'
            : 'Move through the full motion with control.',
        diagnostic: diagnostic,
      );
}

/// `rep_tree_v1`: START/ACTIVE condition trees feeding the same
/// [RepCounterStateMachine] the compiled rep validators use, so a published
/// release counts reps exactly as the equivalent compiled validator does.
class RepTreeV1Runtime extends RemoteVerifierRuntime {
  RepTreeV1Runtime({required super.spec, required super.target});

  final RepCounterStateMachine _counter = RepCounterStateMachine();

  @override
  RemoteVerifierUpdate update(NuvoPoseFrame frame) {
    if (!_started) start();
    if (!frame.hasPoints(spec.requiredLandmarks)) {
      return notReady('missing_required_regions');
    }
    final before = _counter.count;
    _counter.update(
      spec.repTree!.measure(frame),
      stableFrames: spec.stableFrames,
    );
    count = _counter.count;
    final accepted = count > before;
    return RemoteVerifierUpdate(
      state: count >= target
          ? RemoteRuntimeState.completed
          : accepted
          ? RemoteRuntimeState.repAccepted
          : RemoteRuntimeState.tracking,
      count: count,
      progress: math.min(1, target == 0 ? 0 : count / target),
      confidence: accepted ? 0.9 : 0.78,
      guidance: count >= target
          ? 'Target complete.'
          : 'Move through the full motion with control.',
      diagnostic: accepted ? 'rep_accepted' : 'rep_tree_tracking',
    );
  }
}

/// `native_tuned_v1` — the compiled validator for the spec's activity, run
/// with the release's threshold overrides. Behavior is exactly the compiled
/// motion's unless a parameter is set, so a release can only re-tune.
class NativeTunedV1Runtime extends RemoteVerifierRuntime {
  NativeTunedV1Runtime({required super.spec, required super.target})
    : _validator = createMotionValidator(
        AiMotionActivity.fromBackendValue(spec.activityId),
        target,
        tuning: spec.tuning,
      );

  final MotionValidator _validator;

  @override
  void start() {
    super.start();
    _validator.start();
  }

  @override
  RemoteVerifierUpdate update(NuvoPoseFrame frame) {
    if (!_started) start();
    final before = _validator.currentValue;
    final result = _validator.update(frame);
    count = result.currentValue;
    final isHold = spec.measurementType == 'duration';
    final accepted = !isHold && count > before;
    final complete = result.isVerified;
    return RemoteVerifierUpdate(
      state: complete
          ? RemoteRuntimeState.completed
          : accepted
          ? RemoteRuntimeState.repAccepted
          : isHold
          ? RemoteRuntimeState.holdProgress
          : RemoteRuntimeState.tracking,
      count: count,
      progress: math.min(1, target == 0 ? 0 : count / target),
      confidence: _validator.confidence,
      guidance: complete ? 'Target complete.' : result.coachingText,
      diagnostic: accepted ? 'rep_accepted' : _validator.failedRuleReason,
      elapsedMs: isHold ? count * 1000 : 0,
      metrics: _validator.debugValues,
    );
  }
}

RemoteVerifierRuntime createRemoteVerifierRuntime({
  required RemoteVerifierSpec spec,
  required int target,
}) {
  if (target < 1 || target > 100000)
    throw const RemoteVerifierSpecException(
      'Target is outside the supported range.',
    );
  return switch (spec.engine) {
    RemoteEngineType.stateMachineV1 => StateMachineV1Runtime(
      spec: spec,
      target: target,
    ),
    RemoteEngineType.alternatingRepV1 => AlternatingRepV1Runtime(
      spec: spec,
      target: target,
    ),
    RemoteEngineType.holdV1 => HoldV1Runtime(spec: spec, target: target),
    RemoteEngineType.sequenceMatchV1 => SequenceMatchV1Runtime(
      spec: spec,
      target: target,
    ),
    RemoteEngineType.repTreeV1 => RepTreeV1Runtime(spec: spec, target: target),
    RemoteEngineType.nativeTunedV1 => NativeTunedV1Runtime(
      spec: spec,
      target: target,
    ),
  };
}

bool _all(List<RemotePoseRule> rules, NuvoPoseFrame frame) =>
    rules.isNotEmpty && rules.every((rule) => rule.matches(frame));
