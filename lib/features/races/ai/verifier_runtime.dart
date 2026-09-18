import '../data/ai_motion_models.dart';
import '../domain/camera_verification_resolver.dart';
import 'custom_pose/custom_pose_sequence_runtime.dart';
import 'custom_pose/custom_pose_verifier_spec.dart';
import 'custom_pose/normalized_pose.dart';
import 'motion_validators.dart';
import 'remote_verifier_runtime.dart';
import 'remote_verifier_spec.dart';

enum VerifierType {
  presetPose('preset_pose'),
  customPoseSequence('custom_pose_sequence');

  const VerifierType(this.id);

  final String id;

  static VerifierType? fromId(String? id) {
    return switch (id) {
      'preset_pose' => VerifierType.presetPose,
      'custom_pose_sequence' => VerifierType.customPoseSequence,
      _ => null,
    };
  }
}

class VerifierRuntimeException implements Exception {
  const VerifierRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VerifierUpdate {
  const VerifierUpdate({
    required this.type,
    required this.selectedMovement,
    required this.count,
    required this.holdSeconds,
    required this.target,
    required this.confidence,
    required this.completed,
    required this.debugValues,
    required this.validatorState,
    required this.failedRuleReason,
    this.customPoseUpdate,
  });

  factory VerifierUpdate.fromPreset(NuvoVerifyOutput output) => VerifierUpdate(
    type: VerifierType.presetPose,
    selectedMovement: output.selectedMovement,
    count: output.count,
    holdSeconds: output.holdSeconds,
    target: output.target,
    confidence: output.confidence,
    completed: output.completed,
    debugValues: output.debugValues,
    validatorState: output.validatorState,
    failedRuleReason: output.failedRuleReason,
  );

  final VerifierType type;
  final MovementDefinition selectedMovement;
  final int count;
  final int holdSeconds;
  final int target;
  final double confidence;
  final bool completed;
  final Map<String, double> debugValues;
  final String validatorState;
  final String failedRuleReason;
  final CustomPoseRuntimeUpdate? customPoseUpdate;
}

class VerifierResult {
  const VerifierResult({
    required this.type,
    this.aiMotionResult,
    this.customPoseResult,
  });

  final VerifierType type;
  final AiMotionResult? aiMotionResult;
  final CustomPoseRuntimeResult? customPoseResult;
}

abstract class VerifierRuntime {
  VerifierType get type;
  MovementDefinition get movement;
  int get targetValue;
  int get currentValue;
  bool get fullBodyVisible;
  String get failedRuleReason;

  void start();
  VerifierUpdate update(NuvoPoseFrame frame);
  VerifierResult finish();
  void dispose() {}
}

class PresetPoseVerifierRuntime implements VerifierRuntime {
  PresetPoseVerifierRuntime({
    required MovementDefinition movement,
    required int target,
  }) : _engine = NuvoVerifyEngine(movement: movement, target: target);

  factory PresetPoseVerifierRuntime.defaultRuntime() =>
      PresetPoseVerifierRuntime(
        movement: supportedMovementDefinitions.first,
        target: 1,
      );

  final NuvoVerifyEngine _engine;

  @override
  VerifierType get type => VerifierType.presetPose;

  @override
  MovementDefinition get movement => _engine.movement;

  @override
  int get targetValue => _engine.targetValue;

  @override
  int get currentValue => _engine.currentValue;

  @override
  bool get fullBodyVisible => _engine.fullBodyVisible;

  @override
  String get failedRuleReason => _engine.failedRuleReason;

  @override
  void start() => _engine.start();

  @override
  VerifierUpdate update(NuvoPoseFrame frame) =>
      VerifierUpdate.fromPreset(_engine.update(frame));

  @override
  VerifierResult finish() => VerifierResult(
    type: VerifierType.presetPose,
    aiMotionResult: _engine.finish(),
  );

  @override
  void dispose() {}
}

/// Adapts a validated control-plane runtime to the existing camera proof
/// contract. The adapter deliberately requires a compiled movement definition
/// for the proof payload so a remote release can never silently fall back to a
/// different activity identity.
class RemotePoseVerifierRuntime implements VerifierRuntime {
  RemotePoseVerifierRuntime({
    required RemoteVerifierSpec spec,
    required MovementDefinition movement,
    required int target,
  }) : _spec = spec,
       _movement = movement,
       _runtime = createRemoteVerifierRuntime(spec: spec, target: target);

  final RemoteVerifierSpec _spec;
  final MovementDefinition _movement;
  final RemoteVerifierRuntime _runtime;
  RemoteVerifierUpdate? _lastUpdate;
  int _framesAnalyzed = 0;
  int _validPoseFrames = 0;

  @override
  VerifierType get type => VerifierType.presetPose;

  @override
  MovementDefinition get movement => _movement;

  @override
  int get targetValue => _runtime.target;

  @override
  int get currentValue => _runtime.count;

  @override
  bool get fullBodyVisible => _lastUpdate?.state != RemoteRuntimeState.notReady;

  @override
  String get failedRuleReason => _lastUpdate?.diagnostic ?? '';

  @override
  void start() => _runtime.start();

  @override
  VerifierUpdate update(NuvoPoseFrame frame) {
    _framesAnalyzed++;
    if (frame.hasPoints(_spec.requiredLandmarks)) _validPoseFrames++;
    final update = _runtime.update(frame);
    _lastUpdate = update;
    return VerifierUpdate(
      type: VerifierType.presetPose,
      selectedMovement: _movement,
      count: _movement.isHold ? 0 : update.count,
      holdSeconds: _movement.isHold ? update.count : 0,
      target: targetValue,
      confidence: update.confidence,
      completed: update.state == RemoteRuntimeState.completed,
      debugValues: {
        'progress': update.progress,
        'elapsedMs': update.elapsedMs.toDouble(),
      },
      validatorState: update.state.name,
      failedRuleReason: update.state == RemoteRuntimeState.notReady
          ? update.diagnostic
          : '',
    );
  }

  @override
  VerifierResult finish() {
    final update = _lastUpdate;
    final completed = _runtime.count >= targetValue;
    return VerifierResult(
      type: VerifierType.presetPose,
      aiMotionResult: AiMotionResult(
        activity: _movement.activity,
        targetReps: targetValue,
        detectedReps: _runtime.count,
        confidence: update?.confidence ?? 0,
        verificationStatus: completed ? 'ai_verified' : 'ai_failed',
        verificationSummary: completed
            ? 'Target complete.'
            : (update?.guidance ??
                  'Keep your movement in frame and try again.'),
        framesAnalyzed: _framesAnalyzed,
        validPoseFrames: _validPoseFrames,
        durationMs: update?.elapsedMs ?? 0,
        validatorVersion: '${_spec.releaseId}:${_spec.schemaVersion}',
      ),
    );
  }

  @override
  void dispose() {}
}

class VerifierRuntimeResolution {
  const VerifierRuntimeResolution({
    required this.type,
    required this.eligibility,
    required this.presetMovement,
    this.remoteVerifierSpec,
    required this.reason,
  });

  final VerifierType type;
  final CameraVerificationEligibility? eligibility;
  final MovementDefinition? presetMovement;
  final RemoteVerifierSpec? remoteVerifierSpec;
  final String reason;

  bool get canCreateRuntime =>
      (type == VerifierType.presetPose &&
          (presetMovement != null || remoteVerifierSpec != null)) ||
      (type == VerifierType.customPoseSequence &&
          eligibility?.customVerifierSpec != null);

  VerifierRuntime createRuntime({
    required int target,
    CustomPoseVerifierSpec? customSpec,
    RemoteVerifierSpec? remoteSpecOverride,
  }) {
    final movement = presetMovement;
    if (type == VerifierType.customPoseSequence) {
      if (customSpec == null) {
        throw const VerifierRuntimeException(
          'custom_pose_sequence runtime requires a verifier spec.',
        );
      }
      try {
        customSpec.validate();
      } on PoseDataFormatException catch (e) {
        throw VerifierRuntimeException(
          'Invalid custom_pose_sequence verifier spec: ${e.message}',
        );
      }
      return CustomPoseSequenceRuntime(spec: customSpec, target: target);
    }
    final executableRemoteSpec = remoteSpecOverride ?? remoteVerifierSpec;
    if (executableRemoteSpec != null) {
      final remoteMovement = presetMovement;
      if (remoteMovement == null) {
        throw const VerifierRuntimeException(
          'Remote verifier requires a matching local proof activity.',
        );
      }
      return RemotePoseVerifierRuntime(
        spec: executableRemoteSpec,
        movement: remoteMovement,
        target: target,
      );
    }
    if (movement == null) {
      throw VerifierRuntimeException(
        'No executable preset runtime for verifier type ${type.id}.',
      );
    }
    return PresetPoseVerifierRuntime(movement: movement, target: target);
  }
}

class VerifierRuntimeResolver {
  const VerifierRuntimeResolver();

  VerifierRuntimeResolution resolve({
    required CameraVerificationEligibility eligibility,
    String? explicitVerifierType,
  }) {
    final explicitType = _explicitType(explicitVerifierType);
    if (explicitType == VerifierType.customPoseSequence) {
      return VerifierRuntimeResolution(
        type: explicitType,
        eligibility: eligibility,
        presetMovement: null,
        reason: 'custom_runtime_requires_spec',
      );
    }
    if (explicitType == VerifierType.presetPose &&
        !eligibility.isCameraVerifiable) {
      return VerifierRuntimeResolution(
        type: explicitType,
        eligibility: eligibility,
        presetMovement: null,
        reason: eligibility.reason,
      );
    }

    if (!eligibility.isCameraVerifiable) {
      throw VerifierRuntimeException(
        'No verifier runtime for unsupported race: ${eligibility.reason}.',
      );
    }

    if (eligibility.remoteVerifierSpec != null) {
      final movement = _movementDefinitionForEligibility(eligibility);
      return VerifierRuntimeResolution(
        type: VerifierType.presetPose,
        eligibility: eligibility,
        presetMovement: movement,
        remoteVerifierSpec: eligibility.remoteVerifierSpec,
        reason: movement == null
            ? 'remote_release_activity_not_supported'
            : 'remote_release_runtime_resolved',
      );
    }

    final movement = _movementDefinitionForEligibility(eligibility);
    return VerifierRuntimeResolution(
      type: VerifierType.presetPose,
      eligibility: eligibility,
      presetMovement: movement,
      reason: movement == null
          ? 'preset_runtime_not_found'
          : 'preset_runtime_resolved',
    );
  }

  VerifierType _explicitType(String? value) {
    if (value == null || value.isEmpty) return VerifierType.presetPose;
    final type = VerifierType.fromId(value);
    if (type == null) {
      throw VerifierRuntimeException('Unknown verifier type: $value.');
    }
    return type;
  }

  MovementDefinition? _movementDefinitionForEligibility(
    CameraVerificationEligibility eligibility,
  ) {
    final movementType = eligibility.movementType;
    if (!eligibility.isCameraVerifiable || movementType == null) return null;
    return movementDefinitionForType(movementType);
  }
}
