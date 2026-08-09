import '../../domain/motion_activity.dart';
import '../motion_validators.dart';

/// Factory family that determines which validator implementation
/// a movement uses.
///
/// - [configurableRep]: data-driven via [ConfigurableRepValidator] +
///   [RepMovementDefinition]. Currently squats, jumping jacks, lunges.
/// - [customRep]: hand-written validator with logic that exceeds the
///   generic engine's capabilities. Currently pushups.
/// - [alternatingSideRep]: counts alternating left/right events with
///   independent readiness flags. Currently high knees.
/// - [hold]: time-based hold with body alignment checking via
///   [HoldTimerStateMachine]. Currently plank.
/// - [simpleStateRep]: open/closed state machine without debounce.
///   Currently arm raises.
enum MovementFactoryFamily {
  configurableRep,
  customRep,
  alternatingSideRep,
  hold,
  simpleStateRep,
}

/// Describes the verification behavior for a [MovementWorkOrder].
/// Each factory family has a dedicated subtype.
abstract class WorkOrderBehavior {
  const WorkOrderBehavior();
}

/// Behavior for [MovementFactoryFamily.configurableRep] movements.
/// References the production [RepMovementDefinition] so tests can
/// verify the work order matches the actual runtime definition.
class ConfigurableRepBehavior extends WorkOrderBehavior {
  const ConfigurableRepBehavior(this.definition);

  final RepMovementDefinition definition;
}

/// Behavior for [MovementFactoryFamily.customRep] movements.
/// Lists the custom capabilities the validator needs that the generic
/// engine cannot express.
class CustomRepBehavior extends WorkOrderBehavior {
  const CustomRepBehavior({required this.capabilityNotes});

  /// Human-readable labels for each custom capability, e.g.
  /// "dynamic baseline tracking", "cooldown frames", "symmetry check".
  final List<String> capabilityNotes;
}

/// Behavior for [MovementFactoryFamily.hold] movements.
class HoldBehavior extends WorkOrderBehavior {
  const HoldBehavior({
    required this.maxHipLineError,
    required this.maxKneeLineError,
    required this.minKneeAngle,
    required this.stableAlignmentFrames,
  });

  /// Maximum allowed hip-line deviation (normalized to body length).
  final double maxHipLineError;

  /// Maximum allowed knee-line deviation (normalized to body length).
  final double maxKneeLineError;

  /// Minimum average knee angle for legs to be considered extended.
  final double minKneeAngle;

  /// Consecutive alignment-valid frames before the hold timer advances.
  final int stableAlignmentFrames;
}

/// Behavior for [MovementFactoryFamily.alternatingSideRep] movements.
class AlternatingSideBehavior extends WorkOrderBehavior {
  const AlternatingSideBehavior({
    required this.raiseThreshold,
    required this.lowerThreshold,
  });

  /// Knee Y must be below (hipY + [raiseThreshold]) to count as raised.
  final double raiseThreshold;

  /// Knee Y must be above (hipY + [lowerThreshold]) to re-arm the
  /// readiness flag for that side.
  final double lowerThreshold;
}

/// Behavior for [MovementFactoryFamily.simpleStateRep] movements.
class SimpleStateBehavior extends WorkOrderBehavior {
  const SimpleStateBehavior({
    required this.openThreshold,
    required this.closedThreshold,
    this.requiresDirectionalCycle = false,
  });

  /// Threshold for the "open" state (e.g. wrists above shoulders by
  /// this many normalized Y units).
  final double openThreshold;

  /// Threshold for the "closed" state (e.g. wrists below shoulders by
  /// this many normalized Y units, bounded by hip line).
  final double closedThreshold;

  /// If true, a rep only counts after an open→closed cycle following
  /// a prior open state (raise-then-lower requirement).
  final bool requiresDirectionalCycle;
}

/// Immutable work order describing an existing preset movement for
/// factory processing and testing.
///
/// This is NOT the runtime validator — it describes what needs to be
/// manufactured and tested. It does NOT duplicate:
/// - display metadata (title, icon, framingLabel) — in
///   [MotionActivityDefinition]
/// - full animation coordinates — in [MovementDemo]
/// - backend metadata — in [MotionActivityType.backendValue]
/// - validator code — in [MotionValidator] subclasses
class MovementWorkOrder {
  const MovementWorkOrder({
    required this.type,
    required this.family,
    required this.requiredLandmarks,
    required this.preferredCameraView,
    required this.isHold,
    required this.stableFrames,
    required this.demoPhaseNames,
    required this.confusionLabels,
    required this.behavior,
  });

  /// Canonical movement identity (matches [MotionActivityType]).
  final MotionActivityType type;

  /// Which factory family / validator implementation this movement uses.
  final MovementFactoryFamily family;

  /// Pose landmarks the validator requires to process a frame.
  final List<String> requiredLandmarks;

  /// Camera orientation the movement expects.
  final PreferredCameraView preferredCameraView;

  /// Whether this is a timed hold (true) or a rep-counting movement.
  final bool isHold;

  /// Consecutive frames a phase must persist before the state machine
  /// accepts it. For hold movements, this is the alignment-stability
  /// frame count before the timer advances.
  final int stableFrames;

  /// Names of the key poses in the movement's demo animation.
  /// Used to verify demo data exists and matches the movement's phases.
  final List<String> demoPhaseNames;

  /// Labels for negative / confusion test cases that should NOT count
  /// as a valid rep.
  final List<String> confusionLabels;

  /// Family-specific behavior description.
  final WorkOrderBehavior behavior;
}
