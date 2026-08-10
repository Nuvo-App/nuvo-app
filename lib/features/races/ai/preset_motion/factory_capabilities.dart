/// Inventory of reusable detection primitives available to the movement
/// factory.
///
/// This enum is the **capability registry** for the factory system. Each
/// value represents a detection primitive that can be used by movement
/// validators. Work orders implicitly depend on these primitives via
/// their [MovementFactoryFamily] and signal conditions.
///
/// Adding a new primitive here makes it available to the factory without
/// requiring a new movement to exercise it. This is the integration point
/// for capability tracking — tests can verify that a primitive is
/// registered before any movement uses it.
enum FactoryPrimitive {
  // ── Per-frame numeric signals (PoseSignal) ──────────────────────────────
  hipToKneeRatio,
  ankleWidthToBodyWidth,
  kneeSeparationToHipWidth,
  leftKneeAngle,
  rightKneeAngle,

  // ── Per-frame boolean signals (BooleanPoseSignal) ───────────────────────
  wristsAboveShoulders,
  wristsNearBody,

  // ── Temporal / stateful primitives ──────────────────────────────────────
  /// Air/flight phase detection via [AirborneStateTracker].
  ///
  /// Detects when both feet leave the ground relative to a stable
  /// standing ankle baseline. Body-scale-relative (torsoHeight) and
  /// frame-count-based (no wall-clock dependency).
  ///
  /// Provided by: `lib/features/races/ai/airborne_state_tracker.dart`
  ///
  /// NOT yet attached to any production movement. Available for future
  /// movements such as tuck jumps, skater jumps, lateral bounds, frog
  /// jumps, simulated jump rope, heisman jumps, jump squats, lunge jumps.
  airDetection,

  /// Multi-phase ordered sequence detection via [MultiPhaseSequenceTracker].
  ///
  /// Tracks progress through an ordered sequence of pose phases
  /// (e.g., STANDING → SQUAT → AIRBORNE → LANDING). Each phase uses
  /// existing [PoseCondition]s plus temporal primitives like
  /// [airDetection]. Frame-count-based stability, cooldown, and reset
  /// condition rearming — no wall-clock dependency.
  ///
  /// Provided by:
  /// `lib/features/races/ai/multi_phase_sequence_tracker.dart`
  ///
  /// NOT yet attached to any production movement. Available for future
  /// movements such as jump squats, lunge jumps, and other compound
  /// movements requiring ordered phase sequences.
  multiPhaseSequence,
}

/// All registered factory primitives.
///
/// This list is the canonical inventory. Tests verify that every
/// primitive listed here is backed by a real implementation.
const factoryPrimitives = FactoryPrimitive.values;
