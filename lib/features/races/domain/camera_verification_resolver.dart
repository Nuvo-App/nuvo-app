import 'package:flutter/foundation.dart';

import '../data/race_models.dart';
import 'motion_activity.dart';
import 'motion_activity_catalog.dart';

enum CameraVerificationSource { explicitField, titleInference, unresolved }

enum PreferredCameraView {
  frontPreferred,
  frontOrSlightAngle,
  sideOrDiagonalRequired,
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

  MotionActivityDefinition? get movementDefinition =>
      motionActivityForType(movementType);
}

CameraVerificationEligibility resolveCameraVerification(Race race) {
  final explicit = _supportedActivityFromBackendValue(race.aiActivityType);
  if (explicit != null) {
    return _eligible(
      race,
      explicit,
      CameraVerificationSource.explicitField,
      'explicit_supported_activity',
    );
  }

  final inferred = _inferSupportedActivity([
    race.title,
    race.unit,
    race.targetUnit,
  ]);
  if (inferred != null) {
    return _eligible(
      race,
      inferred,
      CameraVerificationSource.titleInference,
      'safe_title_or_unit_inference',
    );
  }

  final explicitUnsupported = race.aiActivityType?.isNotEmpty == true
      ? 'unsupported_explicit_activity'
      : 'no_supported_movement';
  return CameraVerificationEligibility(
    raceId: race.id,
    raceTitle: race.title,
    isCameraVerifiable: false,
    movementType: null,
    source: CameraVerificationSource.unresolved,
    preferredCameraView: null,
    instructions: const [],
    reason: explicitUnsupported,
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

CameraVerificationEligibility _eligible(
  Race race,
  MotionActivityType movement,
  CameraVerificationSource source,
  String reason,
) {
  return CameraVerificationEligibility(
    raceId: race.id,
    raceTitle: race.title,
    isCameraVerifiable: true,
    movementType: movement,
    source: source,
    preferredCameraView: _preferredCameraView(movement),
    instructions: _instructions(movement),
    reason: reason,
  );
}

MotionActivityType? _supportedActivityFromBackendValue(String? value) {
  final type = MotionActivityType.fromBackendValue(value);
  if (type == null) return null;
  return supportedMotionActivityTypes.contains(type) ? type : null;
}

MotionActivityType? _inferSupportedActivity(Iterable<String?> values) {
  final normalized = values
      .whereType<String>()
      .join(' ')
      .toLowerCase()
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.isEmpty) return null;

  if (RegExp(r'(^|[^a-z])push\s*ups?([^a-z]|$)').hasMatch(normalized) ||
      RegExp(r'(^|[^a-z])pushups?([^a-z]|$)').hasMatch(normalized)) {
    return MotionActivityType.pushUps;
  }
  if (RegExp(r'(^|[^a-z])squats?([^a-z]|$)').hasMatch(normalized)) {
    return MotionActivityType.squats;
  }
  if (RegExp(r'(^|[^a-z])jumping\s+jacks?([^a-z]|$)').hasMatch(normalized)) {
    return MotionActivityType.jumpingJacks;
  }
  if (RegExp(r'(^|[^a-z])lunges?([^a-z]|$)').hasMatch(normalized)) {
    return MotionActivityType.lunges;
  }
  if (RegExp(r'(^|[^a-z])planks?([^a-z]|$)').hasMatch(normalized)) {
    return MotionActivityType.plankHold;
  }
  return null;
}

PreferredCameraView _preferredCameraView(MotionActivityType movement) {
  return switch (movement) {
    MotionActivityType.pushUps ||
    MotionActivityType.squats ||
    MotionActivityType.jumpingJacks => PreferredCameraView.frontPreferred,
    MotionActivityType.lunges => PreferredCameraView.frontOrSlightAngle,
    MotionActivityType.plankHold => PreferredCameraView.sideOrDiagonalRequired,
    _ => PreferredCameraView.frontPreferred,
  };
}

List<String> _instructions(MotionActivityType movement) {
  return switch (movement) {
    MotionActivityType.pushUps => const [
      'Stand 6\u20138 feet from the camera.',
      'Keep your hands and shoulders visible.',
      'Wait for the Ready signal.',
    ],
    MotionActivityType.squats => const [
      'Stand 6\u20138 feet away, facing the camera.',
      'Keep your full body in frame, head to feet.',
      'Wait for the Ready signal.',
    ],
    MotionActivityType.jumpingJacks => const [
      'Stand 6\u20138 feet away, facing the camera.',
      'Leave room above your head for arms.',
      'Wait for the Ready signal.',
    ],
    MotionActivityType.lunges => const [
      'Stand 6\u20138 feet away, facing or slightly angled.',
      'Keep your full body in frame, head to feet.',
      'Wait for the Ready signal.',
    ],
    MotionActivityType.plankHold => const [
      'Place the camera to your side, 5\u20136 feet away.',
      'Get into position so your whole body is visible.',
      'Wait for the Ready signal.',
    ],
    _ => const ['Stand 6\u20138 feet from the camera.'],
  };
}
