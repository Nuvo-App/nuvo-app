import '../../domain/motion_activity.dart';
import '../motion_validators.dart';
import 'movement_work_order.dart';
import 'multi_phase_definitions.dart';

/// The complete set of factory work orders for the 13 current preset
/// movements. This is the single source of truth for what each
/// movement's verification behavior looks like from a manufacturing
/// and testing perspective.
///
/// Every movement in [motionActivityDefinitions] must have exactly one
/// work order here. [validatePresetWorkOrders] verifies this invariant.
final presetMovementWorkOrders = [
  // ── Pushups ────────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.pushUps,
    family: MovementFactoryFamily.customRep,
    requiredLandmarks: [
      'leftShoulder',
      'rightShoulder',
      'leftElbow',
      'rightElbow',
      'leftWrist',
      'rightWrist',
      'leftHip',
      'rightHip',
    ],
    preferredCameraView: PreferredCameraView.frontPreferred,
    isHold: false,
    stableFrames: 3,
    demoPhaseNames: ['top', 'bottom'],
    confusionLabels: ['asymmetry', 'hands_not_visible', 'not_low_enough'],
    behavior: CustomRepBehavior(
      capabilityNotes: [
        'dynamic_baseline_tracking',
        'shoulder_drop_fallback',
        'symmetry_check',
        'cooldown_frames',
      ],
    ),
  ),

  // ── Squats ─────────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.squats,
    family: MovementFactoryFamily.configurableRep,
    requiredLandmarks: [
      'leftShoulder',
      'rightShoulder',
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle',
      'rightAnkle',
    ],
    preferredCameraView: PreferredCameraView.frontPreferred,
    isHold: false,
    stableFrames: 3,
    demoPhaseNames: ['standing', 'squatting'],
    confusionLabels: ['not_standing_tall', 'not_deep_enough'],
    behavior: ConfigurableRepBehavior(squatRepDefinition),
  ),

  // ── Jumping Jacks ──────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.jumpingJacks,
    family: MovementFactoryFamily.configurableRep,
    requiredLandmarks: [
      'leftWrist',
      'rightWrist',
      'leftShoulder',
      'rightShoulder',
      'leftHip',
      'rightHip',
      'leftAnkle',
      'rightAnkle',
    ],
    preferredCameraView: PreferredCameraView.frontPreferred,
    isHold: false,
    stableFrames: 3,
    demoPhaseNames: ['start', 'active'],
    confusionLabels: ['arms_only', 'legs_only'],
    behavior: ConfigurableRepBehavior(jumpingJackRepDefinition),
  ),

  // ── Lunges ─────────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.lunges,
    family: MovementFactoryFamily.configurableRep,
    requiredLandmarks: [
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle',
      'rightAnkle',
    ],
    preferredCameraView: PreferredCameraView.frontOrSlightAngle,
    isHold: false,
    stableFrames: 3,
    demoPhaseNames: ['standing', 'lungeRight', 'lungeLeft'],
    confusionLabels: [
      'not_standing_between_reps',
      'not_deep_enough',
      'insufficient_knee_separation',
    ],
    behavior: ConfigurableRepBehavior(lungeRepDefinition),
  ),

  // ── Plank Hold ─────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.plankHold,
    family: MovementFactoryFamily.hold,
    requiredLandmarks: [
      'leftShoulder',
      'rightShoulder',
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle',
      'rightAnkle',
    ],
    preferredCameraView: PreferredCameraView.sideOrDiagonalRequired,
    isHold: true,
    stableFrames: 4,
    demoPhaseNames: ['plank', 'plankDip'],
    confusionLabels: ['knees_dropped', 'legs_not_extended', 'hips_out_of_line'],
    behavior: HoldBehavior(
      maxHipLineError: 0.16,
      maxKneeLineError: 0.18,
      minKneeAngle: 148,
      stableAlignmentFrames: 4,
    ),
  ),

  // ── High Knees ─────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.highKnees,
    family: MovementFactoryFamily.alternatingSideRep,
    requiredLandmarks: ['leftHip', 'rightHip', 'leftKnee', 'rightKnee'],
    preferredCameraView: PreferredCameraView.frontPreferred,
    isHold: false,
    stableFrames: 0,
    demoPhaseNames: ['standing', 'rightKneeUp', 'leftKneeUp'],
    confusionLabels: ['not_alternating', 'not_raising_high_enough'],
    behavior: AlternatingSideBehavior(
      raiseThreshold: 0.02,
      lowerThreshold: 0.12,
    ),
  ),

  // ── Arm Raises ─────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.armRaises,
    family: MovementFactoryFamily.simpleStateRep,
    requiredLandmarks: [
      'leftWrist',
      'rightWrist',
      'leftShoulder',
      'rightShoulder',
      'leftHip',
      'rightHip',
    ],
    preferredCameraView: PreferredCameraView.frontPreferred,
    isHold: false,
    stableFrames: 0,
    demoPhaseNames: [
      'down',
      'raising',
      'shoulderLevel',
      'aboveShoulders',
      'overhead',
    ],
    confusionLabels: ['one_arm_only', 'not_raising_high_enough'],
    behavior: SimpleStateBehavior(
      openThreshold: 0.04,
      closedThreshold: 0.03,
      requiresDirectionalCycle: true,
    ),
  ),

  // ── Sumo Squats ────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.sumoSquats,
    family: MovementFactoryFamily.configurableRep,
    requiredLandmarks: [
      'leftShoulder',
      'rightShoulder',
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle',
      'rightAnkle',
    ],
    preferredCameraView: PreferredCameraView.frontPreferred,
    isHold: false,
    stableFrames: 3,
    demoPhaseNames: ['standing', 'sumoSquat'],
    confusionLabels: ['narrow_stance', 'not_deep_enough', 'looks_like_regular_squat'],
    behavior: ConfigurableRepBehavior(sumoSquatRepDefinition),
  ),

  // ── Side Lunges ────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.sideLunges,
    family: MovementFactoryFamily.configurableRep,
    requiredLandmarks: [
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle',
      'rightAnkle',
    ],
    preferredCameraView: PreferredCameraView.frontPreferred,
    isHold: false,
    stableFrames: 3,
    demoPhaseNames: ['standing', 'sideLungeRight', 'sideLungeLeft'],
    confusionLabels: [
      'looks_like_forward_lunge',
      'insufficient_lateral_separation',
      'not_deep_enough',
    ],
    behavior: ConfigurableRepBehavior(sideLungeRepDefinition),
  ),

  // ── Deep Squats ────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.deepSquats,
    family: MovementFactoryFamily.configurableRep,
    requiredLandmarks: [
      'leftShoulder',
      'rightShoulder',
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle',
      'rightAnkle',
    ],
    preferredCameraView: PreferredCameraView.frontPreferred,
    isHold: false,
    stableFrames: 3,
    demoPhaseNames: ['standing', 'normalSquatDepth', 'deepSquatDepth'],
    confusionLabels: [
      'normal_squat_not_deep_enough',
      'shallow_squat',
      'incomplete_descent',
    ],
    behavior: ConfigurableRepBehavior(deepSquatRepDefinition),
  ),

  // ── Squat Jacks ────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.squatJacks,
    family: MovementFactoryFamily.configurableRep,
    requiredLandmarks: [
      'leftWrist',
      'rightWrist',
      'leftShoulder',
      'rightShoulder',
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle',
      'rightAnkle',
    ],
    preferredCameraView: PreferredCameraView.frontPreferred,
    isHold: false,
    stableFrames: 3,
    demoPhaseNames: ['closed', 'openSquat', 'closed'],
    confusionLabels: [
      'looks_like_jumping_jacks_no_squat',
      'looks_like_squats_no_arm_spread',
      'incomplete_jump',
    ],
    behavior: ConfigurableRepBehavior(squatJackRepDefinition),
  ),

  // ── Jump Squats ─────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.jumpSquats,
    family: MovementFactoryFamily.multiPhaseSequence,
    requiredLandmarks: [
      'leftShoulder',
      'rightShoulder',
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle',
      'rightAnkle',
    ],
    preferredCameraView: PreferredCameraView.frontPreferred,
    isHold: false,
    stableFrames: 3,
    demoPhaseNames: ['standing', 'squat', 'airborne', 'landing'],
    confusionLabels: [
      'looks_like_squats_no_jump',
      'looks_like_jump_no_squat',
      'looks_like_jumping_jacks',
      'incomplete_squat',
    ],
    behavior: MultiPhaseSequenceBehavior(
      definitionBuilder: (airborne) => [buildJumpSquatDefinition(airborne)],
      phaseNames: ['STANDING', 'SQUAT', 'AIRBORNE', 'LANDING'],
    ),
  ),

  // ── Lunge Jumps ─────────────────────────────────────────────────────────────
  MovementWorkOrder(
    type: MotionActivityType.lungeJumps,
    family: MovementFactoryFamily.multiPhaseSequence,
    requiredLandmarks: [
      'leftShoulder',
      'rightShoulder',
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle',
      'rightAnkle',
    ],
    preferredCameraView: PreferredCameraView.frontOrSlightAngle,
    isHold: false,
    stableFrames: 3,
    demoPhaseNames: ['lungeRight', 'airborne', 'lungeLeft'],
    confusionLabels: [
      'looks_like_lunges_no_jump',
      'looks_like_jump_no_lunge',
      'same_side_return',
      'partial_sequence',
    ],
    behavior: MultiPhaseSequenceBehavior(
      definitionBuilder: buildLungeJumpDefinitions,
      phaseNames: ['RIGHT_LUNGE', 'AIRBORNE', 'LEFT_LUNGE'],
    ),
  ),
];

/// Looks up the work order for a [MotionActivityType].
/// Returns null if no work order exists for the type.
MovementWorkOrder? workOrderForType(MotionActivityType type) {
  for (final order in presetMovementWorkOrders) {
    if (order.type == type) return order;
  }
  return null;
}
