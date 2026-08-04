import '../data/ai_motion_models.dart';
import '../domain/camera_verification_resolver.dart';
import 'custom_pose/custom_pose_sequence_runtime.dart';
import 'custom_pose/custom_pose_verifier_spec.dart';
import 'custom_pose/normalized_pose.dart';
import 'motion_validators.dart';

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

class VerifierRuntimeResolution {
  const VerifierRuntimeResolution({
    required this.type,
    required this.eligibility,
    required this.presetMovement,
    required this.reason,
  });

  final VerifierType type;
  final CameraVerificationEligibility? eligibility;
  final MovementDefinition? presetMovement;
  final String reason;

  bool get canCreateRuntime =>
      type == VerifierType.presetPose && presetMovement != null;

  VerifierRuntime createRuntime({
    required int target,
    CustomPoseVerifierSpec? customSpec,
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
    final activity = eligibility.movementDefinition;
    if (!eligibility.isCameraVerifiable || activity == null) return null;
    for (final definition in supportedMovementDefinitions) {
      if (definition.activity.backendValue == activity.type.backendValue) {
        return definition;
      }
    }
    return null;
  }
}
