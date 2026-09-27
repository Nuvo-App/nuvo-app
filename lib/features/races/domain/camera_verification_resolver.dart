import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;

import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import '../ai/object_composition_spec.dart';
import '../ai/remote_verifier_spec.dart';
import '../data/race_models.dart';
import 'motion_activity.dart';
import 'motion_activity_catalog.dart';

export 'motion_activity.dart' show PreferredCameraView;

enum CameraVerificationSource {
  explicitField,
  titleInference,
  customVerifier,
  remoteRelease,
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
    this.remoteVerifierSpec,
    this.objectCompositionSpec,
    this.verifierReleaseId,
    this.remoteActivityDefinition,
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
  final RemoteVerifierSpec? remoteVerifierSpec;
  final ObjectCompositionSpec? objectCompositionSpec;
  final String? verifierReleaseId;

  /// Display metadata for a remote-only activity (one with no compiled
  /// [MotionActivityType]). Sourced from the control-plane catalog or the
  /// release spec's activity block — never from another motion's identity.
  final MotionActivityDefinition? remoteActivityDefinition;

  /// The movement's display definition. Compiled movements resolve from the
  /// bundled catalog; remote-only movements resolve from [remoteActivityDefinition].
  MotionActivityDefinition? get movementDefinition =>
      motionActivityForType(movementType) ?? remoteActivityDefinition;

  bool get isCustomVerifier =>
      source == CameraVerificationSource.customVerifier;

  bool get isRemoteVerifier => source == CameraVerificationSource.remoteRelease;

  bool get isObjectComposition => objectCompositionSpec != null;
}

/// Backend `verifier_type` for a non-physical / honor-logged goal.
const manualLogVerifierType = 'manual_log';

/// Resolves camera-verification eligibility for a race.
///
/// [remoteDefinitions] are the control-plane catalog definitions (e.g. from
/// `availableMotionActivities(snapshot, capabilities)`). They provide display
/// metadata for remote-only activities that have no compiled
/// [MotionActivityType]; when absent, the release spec's own `activity` block
/// still carries enough metadata to run the verifier.
CameraVerificationEligibility resolveCameraVerification(
  Race race, {
  List<MotionActivityDefinition>? remoteDefinitions,
}) {
  // A non-physical goal is authoritatively not camera-verifiable — never let a
  // movement-sounding title ("Run 5 miles this week") infer a camera flow.
  if (race.verifierType == manualLogVerifierType ||
      race.proofMode == 'manual') {
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

  final remote = _resolveRemoteRelease(race, remoteDefinitions);
  if (remote != null) return remote;

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

CameraVerificationEligibility? _resolveRemoteRelease(
  Race race,
  List<MotionActivityDefinition>? remoteDefinitions,
) {
  final raw = race.verifierSpec;
  final engine = raw?['engineType'];
  if (raw == null || engine == null || engine == 'native_v1') return null;
  if (engine == 'object_composition_v1') {
    try {
      final spec = ObjectCompositionSpec.fromJson(raw);
      if (spec.activityId != race.effectiveAiActivityType ||
          (race.verifierReleaseId != null &&
              spec.releaseId != race.verifierReleaseId)) {
        return _remoteIneligible(race, 'remote_release_identity_mismatch');
      }
      return CameraVerificationEligibility(
        raceId: race.id,
        raceTitle: race.title,
        isCameraVerifiable: true,
        movementType: null,
        source: CameraVerificationSource.remoteRelease,
        preferredCameraView: PreferredCameraView.frontOrSlightAngle,
        instructions: const [
          'Keep your hands, ball, and hoop visible.',
          'Release the ball toward the hoop.',
          'Hold still until the shot is evaluated.',
        ],
        reason: 'object_composition_release_resolved',
        objectCompositionSpec: spec,
        verifierReleaseId: race.verifierReleaseId,
      );
    } on ObjectCompositionSpecException {
      return _remoteIneligible(race, 'invalid_object_composition_spec');
    }
  }
  try {
    final spec = RemoteVerifierSpec.fromJson(raw);
    if (spec.activityId != race.effectiveAiActivityType ||
        (race.verifierReleaseId != null &&
            spec.releaseId != race.verifierReleaseId)) {
      return _remoteIneligible(race, 'remote_release_identity_mismatch');
    }
    final compiled = MotionActivityType.fromBackendValue(spec.activityId);
    final bool isCompiled = compiled != null &&
        compiled != MotionActivityType.remote &&
        supportedMotionActivityTypes.contains(compiled);
    // Remote-only activity: the stable ID is data, not an enum member. Its
    // rules spec still runs on an engine this build supports; display
    // metadata comes from the catalog definition or the spec's activity block.
    final remoteDefinition = isCompiled
        ? motionActivityForType(compiled)
        : _remoteDefinitionFor(spec, remoteDefinitions);
    if (!isCompiled && remoteDefinition == null && spec.activity == null) {
      return _remoteIneligible(
        race,
        'remote_activity_metadata_missing',
      );
    }
    return CameraVerificationEligibility(
      raceId: race.id,
      raceTitle: race.title,
      isCameraVerifiable: true,
      movementType: isCompiled ? compiled : MotionActivityType.remote,
      source: CameraVerificationSource.remoteRelease,
      preferredCameraView: remoteDefinition?.preferredCameraView ??
          _cameraViewFromSpecActivity(spec) ??
          PreferredCameraView.frontPreferred,
      instructions: remoteDefinition?.instructions ??
          spec.activity?.instructions ??
          const ['Keep the required body regions visible.'],
      reason: isCompiled
          ? 'remote_release_resolved'
          : 'remote_activity_resolved',
      remoteVerifierSpec: spec,
      verifierReleaseId: race.verifierReleaseId,
      remoteActivityDefinition:
          isCompiled ? null : remoteDefinition ?? _definitionFromSpec(spec),
    );
  } on RemoteVerifierSpecException {
    return _remoteIneligible(race, 'invalid_remote_verifier_spec');
  }
}

CameraVerificationEligibility _remoteIneligible(Race race, String reason) =>
    CameraVerificationEligibility(
      raceId: race.id,
      raceTitle: race.title,
      isCameraVerifiable: false,
      movementType: null,
      source: CameraVerificationSource.unresolved,
      preferredCameraView: null,
      instructions: const [],
      reason: reason,
      unsupportedMessage: 'This verifier release is not available in this app.',
      verifierReleaseId: race.verifierReleaseId,
    );

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
    instructions:
        definition?.instructions ?? const ['Keep your body in frame.'],
    reason: reason,
  );
}

MotionActivityType? _supportedActivityFromBackendValue(String? value) {
  final type = MotionActivityType.fromBackendValue(value);
  if (type == null) return null;
  return supportedMotionActivityTypes.contains(type) ? type : null;
}

/// Catalog definition for a remote-only activity ID, if the control plane
/// published one and this build lists it as compatible.
MotionActivityDefinition? _remoteDefinitionFor(
  RemoteVerifierSpec spec,
  List<MotionActivityDefinition>? remoteDefinitions,
) {
  if (remoteDefinitions == null) return null;
  for (final definition in remoteDefinitions) {
    if (definition.activityId == spec.activityId) return definition;
  }
  return null;
}

PreferredCameraView? _cameraViewFromSpecActivity(RemoteVerifierSpec spec) =>
    switch (spec.activity?.preferredCameraView) {
      'side' => PreferredCameraView.sideOrDiagonalRequired,
      'front_or_angle' => PreferredCameraView.frontOrSlightAngle,
      'front' => PreferredCameraView.frontPreferred,
      _ => null,
    };

/// Builds display metadata from the release spec's own `activity` block so a
/// remote-only motion can present itself even with no catalog snapshot
/// (offline, cache miss, or stale catalog). Returns null without a block —
/// callers then mark the race ineligible rather than borrow another
/// motion's identity.
MotionActivityDefinition? _definitionFromSpec(RemoteVerifierSpec spec) {
  final info = spec.activity;
  if (info == null) return null;
  final isDuration =
      info.measurementType == 'duration' ||
      spec.measurementType == 'duration';
  return MotionActivityDefinition(
    type: MotionActivityType.remote,
    backendId: spec.activityId,
    title: info.displayName,
    metric: isDuration ? RaceMetric.seconds : RaceMetric.reps,
    suggestedTargets: [info.defaultTarget],
    supportedFormats: const [RaceFormat.firstToGoal],
    aliases: [info.displayName.toLowerCase()],
    proofLabel: info.displayName,
    cameraInstruction: switch (_cameraViewFromSpecActivity(spec)) {
      PreferredCameraView.sideOrDiagonalRequired =>
        'Stand sideways. Keep your full body in frame.',
      PreferredCameraView.frontOrSlightAngle =>
        'Angle your body to the camera. Keep your full body in frame.',
      _ => 'Stand facing the camera. Keep your full body in frame.',
    },
    instructions: info.instructions.isNotEmpty
        ? info.instructions
        : const ['Keep the required body regions visible.'],
    icon: Icons.fitness_center_rounded,
    framingLabel: 'Follow the release framing guide',
    preferredCameraView:
        _cameraViewFromSpecActivity(spec) ?? PreferredCameraView.frontPreferred,
    category: MovementCategory.fullBody,
    isHold: isDuration,
    measurementType: isDuration
        ? MotionMeasurementType.duration
        : MotionMeasurementType.repetitions,
    displayUnitOverride: info.unit,
    releaseId: spec.releaseId,
  );
}
