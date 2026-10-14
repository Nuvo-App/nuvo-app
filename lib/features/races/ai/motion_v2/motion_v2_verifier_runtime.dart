import 'dart:async';

import '../../data/ai_motion_models.dart';
import '../custom_pose/custom_pose_sequence_runtime.dart';
import '../motion_validators.dart' show MovementDefinition, supportedMovementDefinitions;
import '../verifier_runtime.dart';
import 'motion_v2_models.dart';
import 'motion_v2_native_runtime.dart';
import 'motion_verifier_v2.dart';

/// The verifier-type identity a `motion_v2` race stores on the backend.
const String motionV2VerifierType = 'motion_v2';
const int motionV2VerifierSpecVersion = 1;
const String motionV2VerifierRuntimeVersion = 'motion_v2-v1';

/// Adapts the async, batch-fed Motion V2 matcher to the synchronous
/// per-frame [VerifierRuntime] contract the proof camera drives.
///
/// V2 is the verifier of record for taught movements: the encoder runs
/// on-device (ONNX), and each sliding window is judged against the 3
/// demonstration references in [TaughtMotionV2Spec] — the same matcher that
/// learned and live-tested the movement in Teach Nuvo, so what taught is what
/// verifies. The interface stays synchronous by buffering frames and pumping
/// the matcher when a batch is full; [update] always answers with the latest
/// known state, exactly like the Teach live-test loop.
///
/// Results arrive in the [CustomPoseRuntimeUpdate] / [CustomPoseRuntimeResult]
/// shapes the proof screen already renders and submits — `verifierType` /
/// `validatorVersion` mark them `motion_v2` so telemetry can tell which engine
/// actually counted.
class MotionV2VerifierRuntime implements VerifierRuntime {
  MotionV2VerifierRuntime({
    required TaughtMotionV2Spec spec,
    required int target,
    MotionVerifierV2? engine,
  }) : _spec = spec,
       _target = target,
       _engine = engine ?? MotionV2NativeRuntime();

  /// Frames per matcher call — same batch size the Teach live test uses.
  static const int batchSize = 4;

  final TaughtMotionV2Spec _spec;
  final MotionVerifierV2 _engine;
  final int _target;

  final List<NuvoPoseFrame> _batch = [];
  MotionV2RuntimeResult _last = MotionV2RuntimeResult.empty;
  bool _started = false;
  bool _loading = false;
  bool _ready = false;
  bool _busy = false;
  String _failureReason = '';
  int _framesAnalyzed = 0;
  int _validFrames = 0;
  int _failedAttempts = 0;
  int _completions = 0;
  DateTime? _startedAt;
  DateTime? _lastFrameAt;

  @override
  VerifierType get type => VerifierType.motionV2;

  @override
  MovementDefinition get movement => supportedMovementDefinitions.first;

  @override
  int get targetValue => _target;

  @override
  int get currentValue => _last.count;

  @override
  bool get fullBodyVisible =>
      _ready && _last.poseReadiness == 'ready';

  @override
  String get failedRuleReason => _failureReason;

  @override
  void start() {
    _started = true;
    _startedAt ??= DateTime.now();
    _ensureLoaded();
  }

  void _ensureLoaded() {
    if (_loading || _ready || _failureReason.isNotEmpty) return;
    _loading = true;
    unawaited(
      _engine
          .load(_spec)
          .then((_) {
            _ready = true;
            _pump(); // drain frames buffered while the engine warmed up
          })
          .catchError((Object e) {
            _failureReason = e is MotionV2Exception ? e.message : e.toString();
          })
          .whenComplete(() => _loading = false),
    );
  }

  @override
  VerifierUpdate update(NuvoPoseFrame frame) {
    if (!_started) start();
    _framesAnalyzed++;
    _lastFrameAt = frame.createdAt;
    if (frame.points.isNotEmpty) _validFrames++;
    // Buffer frames while the engine loads — early motion is preserved, not
    // dropped — then drained through the matcher once ready.
    _batch.add(frame);
    _pump();
    return _snapshot();
  }

  void _pump() {
    if (!_ready || _busy || _batch.length < batchSize) return;
    _busy = true;
    final frames = _batch.sublist(0, batchSize);
    _batch.removeRange(0, batchSize);
    _engine
        .update(frames)
        .then((r) {
          if (r.newRep) _completions++;
          if (r.attempt.outcome == MotionAttemptOutcome.failed) {
            _failedAttempts++;
            if (r.attempt.userFeedback.isNotEmpty) {
              _failureReason = r.attempt.userFeedback;
            }
          }
          _last = r;
        })
        .catchError((Object e) {
          _failureReason = e is MotionV2Exception ? e.message : e.toString();
        })
        .whenComplete(() {
          _busy = false;
          if (_batch.length >= batchSize) _pump();
        });
  }

  CustomPoseRuntimeState get _mappedState => switch (_last.state) {
    MotionV2RuntimeState.warmingUp => CustomPoseRuntimeState.waitingForSetup,
    MotionV2RuntimeState.neutral => CustomPoseRuntimeState.waitingForStart,
    MotionV2RuntimeState.matching => CustomPoseRuntimeState.matchingSequence,
    MotionV2RuntimeState.returning => CustomPoseRuntimeState.completionCandidate,
    MotionV2RuntimeState.error => CustomPoseRuntimeState.invalid,
  };

  CustomPoseRuntimeUpdate _customUpdate() => CustomPoseRuntimeUpdate(
    state: _ready ? _mappedState : CustomPoseRuntimeState.waitingForSetup,
    count: _last.count,
    target: _target,
    completed: _last.count >= _target,
    sequenceProgress: _last.motionProgress,
    currentTemplateIndex: 0,
    bestCanonicalIndex: 0,
    currentSimilarity: _last.trajSim ?? _last.confidence,
    completionSimilarity: _last.confidence,
    resetSimilarity: 0,
    validFeatureRatio: _last.poseReadiness == 'ready' ? 1 : 0,
    requiredFeatureRatio: _last.poseReadiness == 'ready' ? 1 : 0,
    visibility: _last.poseReadiness == 'ready' ? 1 : 0,
    missingRequiredFeatures: const [],
    mirroredComparisonUsed: false,
    frameAdvancedVerification: _last.newRep,
    frameNoAdvanceReason: _failureReason.isNotEmpty
        ? 'engine_error'
        : _last.state.name,
    framesAnalyzed: _framesAnalyzed,
    validFrames: _validFrames,
    missingFeatureGraceCount: 0,
    framesSinceProgress: 0,
    guidance: _last.poseGuidance.isNotEmpty ? _last.poseGuidance : 'Ready',
    failureReason: _failureReason.isEmpty ? null : _failureReason,
    confidence: _last.confidence,
  );

  VerifierUpdate _snapshot() => VerifierUpdate(
    type: VerifierType.motionV2,
    selectedMovement: movement,
    count: _last.count,
    holdSeconds: 0,
    target: _target,
    confidence: _last.confidence,
    completed: _last.count >= _target,
    debugValues: {
      'votes': _last.votes.toDouble(),
      'matched': _last.matched ? 1 : 0,
      'bufferFrames': _last.bufferFrames.toDouble(),
      if (_last.protoMargin != null) 'protoMargin': _last.protoMargin!,
      if (_last.trajSim != null) 'trajSim': _last.trajSim!,
      if (_last.separation != null) 'separation': _last.separation!,
      'engineReady': _ready ? 1 : 0,
    },
    validatorState:
        _ready ? _last.state.name : (_failureReason.isEmpty ? 'loading' : 'error'),
    failedRuleReason: _failureReason,
    customPoseUpdate: _customUpdate(),
  );

  @override
  VerifierResult finish() => VerifierResult(
    type: VerifierType.motionV2,
    customPoseResult: customResult(),
  );

  /// The custom-verifier-shaped result the proof submit + session telemetry
  /// already consume. `validatorVersion` is `motion_v2-…` so stored sessions
  /// attribute counts to this engine, not V1.
  CustomPoseRuntimeResult customResult() {
    final duration = _startedAt == null || _lastFrameAt == null
        ? Duration.zero
        : _lastFrameAt!.difference(_startedAt!);
    final complete = _ready && _last.count >= _target;
    final failure = complete
        ? null
        : _failureReason.isNotEmpty
        ? _failureReason
        : 'target_not_met';
    return CustomPoseRuntimeResult(
      verifierType: motionV2VerifierType,
      verifierVersion: _spec.version,
      movementName: _spec.movementName,
      measurementType: 'count',
      count: _last.count,
      target: _target,
      verificationStatus: complete ? 'custom_verified' : 'custom_failed',
      confidence: _last.confidence,
      framesAnalyzed: _framesAnalyzed,
      validFrames: _validFrames,
      durationMs: duration.inMilliseconds.clamp(0, 1 << 31),
      completionEvents: _completions,
      invalidAttemptCount: _failedAttempts,
      finalFailureReason: failure,
    );
  }

  @override
  void dispose() {
    unawaited(_engine.dispose());
  }
}
