import 'package:flutter/foundation.dart';

import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import '../data/race_models.dart';
import 'motion_activity.dart';
import 'motion_activity_catalog.dart';

export 'motion_activity.dart' show PreferredCameraView;

enum CameraVerificationSource {
  explicitField,
  titleInference,
  customVerifier,
  unresolved,
}

class CameraVerificationEligibility {
  const CameraVerificationEligibility({
    required this.raceId,
    required this.raceTitle,
    required this.isCameraVerifiable,
    required this.movementType,
    required this.source,
    required this.preferredCameraView,
    required this.instructions,
    required this.reason,
    this.unsupportedMessage = 'This movement cannot be camera verified yet.',
    this.customVerifierSpec,
  });

  final String raceId;
  final String raceTitle;
  final bool isCameraVerifiable;
  final MotionActivityType? movementType;
  final CameraVerificationSource source;
  final PreferredCameraView? preferredCameraView;
  final List<String> instructions;
  final String reason;
  final String unsupportedMessage;
  final CustomPoseVerifierSpec? customVerifierSpec;

  MotionActivityDefinition? get movementDefinition =>
      motionActivityForType(movementType);

  bool get isCustomVerifier =>
      source == CameraVerificationSource.customVerifier;
}

/// Backend `verifier_type` for a non-physical / honor-logged goal.
const manualLogVerifierType = 'manual_log';

CameraVerificationEligibility resolveCameraVerification(Race race) {
  // A non-physical goal is authoritatively not camera-verifiable — never let a
  // movement-sounding title ("Run 5 miles this week") infer a camera flow.
  if (race.verifierType == manualLogVerifierType || race.proofMode == 'manual') {
    return CameraVerificationEligibility(
      raceId: race.id,
      raceTitle: race.title,
      isCameraVerifiable: false,
      movementType: null,
      source: CameraVerificationSource.unresolved,
      preferredCameraView: null,
      instructions: const [],
      reason: 'manual_goal',
    );
  }
  if (race.isCustomVerifierRace) {
    return _resolveCustomVerification(race);
  }

  final explicitValue = race.activityId ?? race.aiActivityType;
  final explicit = _supportedActivityFromBackendValue(explicitValue);
  if (explicit != null) {
    return _eligible(
      race,
      explicit,
      CameraVerificationSource.explicitField,
      'explicit_supported_activity',
    );
  }

  if (explicitValue?.isNotEmpty == true) {
    return CameraVerificationEligibility(
      raceId: race.id,
      raceTitle: race.title,
      isCameraVerifiable: false,
      movementType: null,
      source: CameraVerificationSource.unresolved,
      preferredCameraView: null,
      instructions: const [],
      reason: 'unsupported_explicit_activity',
    );
  }

  final inferred = inferSupportedMotionActivity([
    race.title,
    race.unit,
    race.targetUnit,
  ]);
  if (inferred != null) {
    return _eligible(
      race,
      inferred.type,
      CameraVerificationSource.titleInference,
      'safe_title_or_unit_inference',
    );
  }

  return CameraVerificationEligibility(
    raceId: race.id,
    raceTitle: race.title,
    isCameraVerifiable: false,
    movementType: null,
    source: CameraVerificationSource.unresolved,
    preferredCameraView: null,
    instructions: const [],
    reason: 'no_supported_movement',
  );
}

void debugLogCameraVerificationDecision(
  Race race,
  CameraVerificationEligibility eligibility, {
  required String routeAction,
}) {
  assert(() {
    debugPrint(
      '[NuvoVerify] raceId=${race.id} '
      'raceName="${race.title}" '
      'cameraVerifiable=${eligibility.isCameraVerifiable} '
      'movement=${eligibility.movementType?.name ?? 'unsupported'} '
      'source=${eligibility.source.name} '
      'preferredCameraView=${eligibility.preferredCameraView?.name ?? 'none'} '
      'routeAction=$routeAction '
      'reason=${eligibility.reason}',
    );
    return true;
  }());
}

CameraVerificationEligibility _resolveCustomVerification(Race race) {
  if (race.status != 'active') {
    return _customIneligible(
      race,
      'race_not_active',
      'This race is not active.',
    );
  }
  if (race.verifierType != customPoseVerifierType) {
    return _customIneligible(
      race,
      'unsupported_custom_verifier_type',
      'This custom verifier type is not supported.',
    );
  }
  if (race.verifierVersion != customPoseVerifierSpecSchemaVersion) {
    return _customIneligible(
      race,
      'unsupported_custom_verifier_version',
      'This custom verifier version is not supported.',
    );
  }
  if (race.verifierInvalidReason != null) {
    return _customIneligible(
      race,
      'invalid_custom_verifier_spec',
      'The stored verifier spec could not be decoded.',
    );
  }
  final spec = race.customVerifierSpec;
  if (spec == null) {
    return _customIneligible(
      race,
      'missing_custom_verifier_spec',
      'This race is missing its verifier spec.',
    );
  }
  try {
    spec.validate();
  } catch (_) {
    return _customIneligible(
      race,
      'invalid_custom_verifier_spec',
      'The stored verifier spec is invalid.',
    );
  }
  final metric = race.metric ?? race.targetUnit ?? race.unit;
  if (metric != 'reps' && metric != 'count') {
    return _customIneligible(
      race,
      'unsupported_custom_measurement_type',
      'This custom race uses an unsupported measurement type.',
    );
  }
  return _customEligible(race, spec);
}

CameraVerificationEligibility _customEligible(
  Race race,
  CustomPoseVerifierSpec spec,
) {
  return CameraVerificationEligibility(
    raceId: race.id,
    raceTitle: race.title,
    isCameraVerifiable: true,
    movementType: null,
    source: CameraVerificationSource.customVerifier,
    preferredCameraView: PreferredCameraView.frontPreferred,
    instructions: const ['Place your whole body in frame.'],
    reason: 'custom_verifier_resolved',
    customVerifierSpec: spec,
  );
}

CameraVerificationEligibility _customIneligible(
  Race race,
  String reason,
  String unsupportedMessage,
) {
  return CameraVerificationEligibility(
    raceId: race.id,
    raceTitle: race.title,
    isCameraVerifiable: false,
    movementType: null,
    source: CameraVerificationSource.unresolved,
    preferredCameraView: null,
    instructions: const [],
    reason: reason,
    unsupportedMessage: unsupportedMessage,
  );
}

CameraVerificationEligibility _eligible(
  Race race,
  MotionActivityType movement,
  CameraVerificationSource source,
  String reason,
) {
  final definition = motionActivityForType(movement);
  return CameraVerificationEligibility(
    raceId: race.id,
    raceTitle: race.title,
    isCameraVerifiable: true,
    movementType: movement,
    source: source,
    preferredCameraView: definition?.preferredCameraView,
    instructions: definition?.instructions ?? const ['Keep your body in frame.'],
    reason: reason,
  );
}

MotionActivityType? _supportedActivityFromBackendValue(String? value) {
  final type = MotionActivityType.fromBackendValue(value);
  if (type == null) return null;
  return supportedMotionActivityTypes.contains(type) ? type : null;
}
