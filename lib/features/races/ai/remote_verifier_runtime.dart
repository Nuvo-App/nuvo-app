import 'dart:math' as math;

import '../data/ai_motion_models.dart';
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
  });

  final RemoteRuntimeState state;
  final int count;
  final double progress;
  final double confidence;
  final String guidance;
  final String diagnostic;
  final int elapsedMs;
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
  };
}

bool _all(List<RemotePoseRule> rules, NuvoPoseFrame frame) =>
    rules.isNotEmpty && rules.every((rule) => rule.matches(frame));
