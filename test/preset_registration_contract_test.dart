import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/verifier_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/camera_verification_resolver.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';

/// THE preset-registration invariant. Iterates every production preset in the
/// catalog and asserts every layer of the create-race -> load -> proof route
/// knows about it. This exists so the class of bug where a motion "appears in
/// the UI but race creation says 'choose a supported activity'" cannot recur:
/// add a preset to `motionActivityDefinitions` and this test tells you exactly
/// which downstream layer you forgot.
///
/// See docs/agents/PRESET_MOTION_CREATION.md for the full contract.

/// The count convention for every preset. Every catalog entry MUST have one —
/// cadence motions especially must not have an invisible per-movement choice.
/// (Documented prose form lives in PRESET_MOTION_CREATION.md §Count semantics.)
const _countSemantics = <MotionActivityType, String>{
  MotionActivityType.pushUps: 'one full rep (top -> bottom -> top)',
  MotionActivityType.jumpingJacks: 'one full rep (closed -> open -> closed)',
  MotionActivityType.squats: 'one full rep (stand -> depth -> stand)',
  MotionActivityType.lunges: 'one full rep (stand -> lunge -> stand)',
  MotionActivityType.plankHold: 'one second of valid hold',
  MotionActivityType.highKnees: 'one knee raise (either leg)',
  MotionActivityType.armRaises: 'one full rep (down -> up -> down)',
  MotionActivityType.sumoSquats: 'one full rep (stand -> depth -> stand)',
  MotionActivityType.sideLunges: 'one full rep (stand -> side lunge -> stand)',
  MotionActivityType.deepSquats: 'one full rep (stand -> deep -> stand)',
  MotionActivityType.squatJacks: 'one full rep (closed -> open+squat -> closed)',
  MotionActivityType.jumpSquats: 'one full rep (stand -> squat -> air -> land)',
  MotionActivityType.lungeJumps: 'one full rep (lunge -> jump -> switch)',
  // Cadence family — one count = one confirmed alternation step (matches
  // High Knees' per-raise granularity). A left+right cycle is 2.
  MotionActivityType.runningInPlace: 'one confirmed alternating step',
  MotionActivityType.treadmillRunning: 'one confirmed alternating step',
  MotionActivityType.walkingInPlace: 'one confirmed alternating step',
  MotionActivityType.marchingInPlace: 'one confirmed alternating step',
  MotionActivityType.buttKicks: 'one confirmed alternating heel kick',
  MotionActivityType.mountainClimbers: 'one confirmed alternating knee drive',
  MotionActivityType.stepUps: 'one confirmed alternating step',
  MotionActivityType.lateralSteps: 'one confirmed alternating side step',
  MotionActivityType.burpees: 'one full rep (stand -> down -> stand)',
  MotionActivityType.calfRaises: 'one full rep (neutral -> rise -> return)',
};

Map<String, dynamic> _raceJson(String activityId, {String unit = 'reps'}) => {
      'id': 'race-1',
      'creatorId': 'user-1',
      'title': 'First to 15 Reps',
      'goalType': 'first_to_goal',
      'targetValue': 15,
      'unit': unit,
      'targetUnit': unit,
      'activityId': activityId,
      'aiActivityType': activityId,
      'metric': unit,
      'format': 'first_to_goal',
      'proofRequirement': 'ai_check',
      'proofMode': 'ai_check',
      'verificationMethod': 'camera_pose',
      'verifierType': 'preset_pose',
      'status': 'active',
      'visibility': 'invite_code',
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
    };

void main() {
  const resolver = VerifierRuntimeResolver();

  group('preset registration contract — every catalog preset, every layer', () {
    for (final def in motionActivityDefinitions) {
      final type = def.type;
      final id = type.backendValue;

      test('$id is registered end to end', () {
        // ── identity round-trips ────────────────────────────────────────────
        expect(id, isNotEmpty, reason: '$id: empty backend value');
        expect(MotionActivityType.fromBackendValue(id), type,
            reason: '$id: MotionActivityType.fromBackendValue');
        expect(supportedMotionActivityTypes.contains(type), isTrue,
            reason: '$id: supportedMotionActivityTypes');

        final ai = AiMotionActivity.fromBackendValue(id);
        expect(ai.backendValue, id,
            reason: '$id: AiMotionActivity.fromBackendValue round-trip '
                '(got ${ai.name} / ${ai.backendValue})');

        // ── runtime movement definition + validator factory ─────────────────
        final movementDef = movementDefinitionForType(type);
        expect(movementDef, isNotNull,
            reason: '$id: no MovementDefinition (supportedMovementDefinitions '
                'or _aiMotionActivityForType)');
        expect(movementDef!.activity, ai, reason: '$id: MovementDefinition.activity');

        final validator = createMotionValidator(ai, 10);
        expect(validator.activity, ai,
            reason: '$id: createMotionValidator built the wrong validator');
        expect(validator.targetValue, 10, reason: '$id: target not threaded');

        // ── goal / unit semantics + display metadata ───────────────────────
        expect(def.suggestedTargets, isNotEmpty, reason: '$id: no suggestedTargets');
        expect(def.defaultTarget, greaterThan(0), reason: '$id: defaultTarget <= 0');
        expect(def.unit.trim(), isNotEmpty, reason: '$id: empty unit');
        expect(def.supportedFormats, isNotEmpty, reason: '$id: no supportedFormats');
        expect(def.title.trim(), isNotEmpty, reason: '$id: empty title');
        expect(def.instructions, isNotEmpty, reason: '$id: no instructions');
        expect(_countSemantics.containsKey(type), isTrue,
            reason: '$id: count semantics not documented in _countSemantics / '
                'PRESET_MOTION_CREATION.md');

        // ── create-race payload ────────────────────────────────────────────
        final draft = draftForActivity(def).copyWith(targetValue: 15);
        expect(draft.isValidToCreate, isTrue,
            reason: '$id: draft.isValidToCreate is false — the client would '
                'show "Choose a supported activity"');
        final payload = draft.toCreatePayload();
        expect(payload['activityId'], id, reason: '$id: payload activityId');
        expect(payload['aiActivityType'], id, reason: '$id: payload aiActivityType');
        expect(payload['metric'], def.metric.backendValue,
            reason: '$id: payload metric');

        // ── load back -> proof route -> verifier ───────────────────────────
        final race = Race.fromJson(_raceJson(id, unit: def.metric.backendValue));
        final eligibility = resolveCameraVerification(race);
        expect(eligibility.isCameraVerifiable, isTrue,
            reason: '$id: resolveCameraVerification says not verifiable '
                '(${eligibility.reason})');
        expect(eligibility.movementType, type,
            reason: '$id: eligibility resolved to a different movement');

        final resolution = resolver.resolve(eligibility: eligibility);
        expect(resolution.type, VerifierType.presetPose, reason: '$id: verifier type');
        expect(resolution.canCreateRuntime, isTrue,
            reason: '$id: resolver cannot create a runtime');
        expect(resolution.presetMovement?.activity, ai,
            reason: '$id: resolver picked the wrong movement');

        final runtime = resolution.createRuntime(target: 15);
        expect(runtime.movement.activity, ai, reason: '$id: runtime movement');
      });
    }

    test('the catalog and the AiMotionActivity enum agree on counts', () {
      // Every AiMotionActivity that a preset maps to must have a validator
      // case, and every catalog preset must map to a distinct AiMotionActivity.
      final mapped = <AiMotionActivity>{};
      for (final def in motionActivityDefinitions) {
        final ai = AiMotionActivity.fromBackendValue(def.type.backendValue);
        expect(mapped.add(ai), isTrue,
            reason: '${def.type.backendValue} maps to ${ai.name}, already used '
                '— AiMotionActivity.fromBackendValue is missing a case and '
                'falling through to a default');
      }
      expect(mapped.length, motionActivityDefinitions.length);
    });

    test('verifyValidatorDispatchComplete passes', () {
      // Every supportedMovementDefinitions entry has a createMotionValidator case.
      verifyValidatorDispatchComplete();
    });
  });

  test('PRESET ROUTE AUDIT (printed)', () {
    final buf = StringBuffer('\nPRESET ROUTE AUDIT\n');
    for (final def in motionActivityDefinitions) {
      final id = def.type.backendValue;
      final ai = AiMotionActivity.fromBackendValue(id);
      final race = Race.fromJson(_raceJson(id, unit: def.metric.backendValue));
      final elig = resolveCameraVerification(race);
      final res = const VerifierRuntimeResolver().resolve(eligibility: elig);
      buf.writeln(
        '${id.padRight(20)} '
        'catalog:yes  '
        'supported:${supportedMotionActivityTypes.contains(def.type) ? 'yes' : 'NO '}  '
        'unit:${def.metric.backendValue.padRight(7)} '
        'serialize:${draftForActivity(def).toCreatePayload()['activityId'] == id ? 'yes' : 'NO '}  '
        'deserialize:${MotionActivityType.fromBackendValue(id) == def.type ? 'yes' : 'NO '}  '
        'validator:${createMotionValidator(ai, 1).activity == ai ? 'yes' : 'NO '}  '
        'proof:${res.canCreateRuntime && res.type == VerifierType.presetPose ? 'yes' : 'NO '}',
      );
    }
    // ignore: avoid_print
    print(buf.toString());
    expect(true, isTrue);
  });
}
