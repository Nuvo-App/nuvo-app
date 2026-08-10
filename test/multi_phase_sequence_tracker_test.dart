import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/multi_phase_sequence_tracker.dart';
import 'package:nuvo/features/races/ai/preset_motion/factory_capabilities.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

// ── Synthetic test conditions ───────────────────────────────────────────────
//
// These conditions do NOT depend on pose data. They use a mutable flag that
// tests set directly, allowing deterministic control over which phase
// "matches" on each frame. This isolates the sequence engine logic from
// pose feature extraction.

/// A synthetic condition whose result is controlled by a mutable flag.
class _FlagCondition extends PoseCondition {
  _FlagCondition(this.flag);
  final _Flag flag;

  @override
  bool evaluate(PoseFeatureExtractor features) => flag.value;
}

/// A mutable boolean flag wrapped in a class so conditions can reference
/// it by reference and tests can toggle it between frames.
class _Flag {
  _Flag(this.value);
  bool value;
}

/// A pose frame with all required landmarks present at high likelihood.
/// The actual coordinates don't matter for synthetic condition tests —
/// the _FlagCondition ignores the features entirely.
NuvoPoseFrame _validFrame() {
  final points = <String, NuvoPosePoint>{};
  for (final name in [
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
    'leftAnkle',
    'rightAnkle',
  ]) {
    points[name] = const NuvoPosePoint(x: 0.5, y: 0.5, z: 0, likelihood: 0.95);
  }
  return NuvoPoseFrame(
    points: points,
    imageWidth: 1080,
    imageHeight: 1920,
    createdAt: DateTime.now(),
  );
}

/// A frame missing required landmarks (triggers fail-safe).
NuvoPoseFrame _missingLandmarkFrame() => NuvoPoseFrame(
  points: {
    'leftShoulder': const NuvoPosePoint(x: 0.5, y: 0.5, z: 0, likelihood: 0.95),
  },
  imageWidth: 1080,
  imageHeight: 1920,
  createdAt: DateTime.now(),
);

/// Builds a 3-phase sequence (A → B → C) with synthetic flag conditions.
({
  MultiPhaseSequenceTracker tracker,
  _Flag flagA,
  _Flag flagB,
  _Flag flagC,
  _Flag flagReset,
})
_buildABCSequence({int stableFrames = 3, int cooldownFrames = 3}) {
  final flagA = _Flag(false);
  final flagB = _Flag(false);
  final flagC = _Flag(false);
  final flagReset = _Flag(false);

  final definition = MultiPhaseSequenceDefinition(
    phases: [
      SequencePhaseDefinition(
        id: 'A',
        condition: _FlagCondition(flagA),
        stableFrames: stableFrames,
      ),
      SequencePhaseDefinition(
        id: 'B',
        condition: _FlagCondition(flagB),
        stableFrames: stableFrames,
      ),
      SequencePhaseDefinition(
        id: 'C',
        condition: _FlagCondition(flagC),
        stableFrames: stableFrames,
      ),
    ],
    resetCondition: _FlagCondition(flagReset),
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
    cooldownFrames: cooldownFrames,
  );

  return (
    tracker: MultiPhaseSequenceTracker(definition: definition),
    flagA: flagA,
    flagB: flagB,
    flagC: flagC,
    flagReset: flagReset,
  );
}

/// Feeds N frames with only the specified flag active.
void _feedFrames(
  MultiPhaseSequenceTracker tracker,
  _Flag activeFlag,
  List<_Flag> allFlags,
  int count,
) {
  for (final f in allFlags) {
    f.value = false;
  }
  activeFlag.value = true;
  for (var i = 0; i < count; i++) {
    tracker.update(_validFrame());
  }
}

/// Feeds one frame with only the specified flag active.
bool _feedOne(
  MultiPhaseSequenceTracker tracker,
  _Flag activeFlag,
  List<_Flag> allFlags,
) {
  for (final f in allFlags) {
    f.value = false;
  }
  activeFlag.value = true;
  return tracker.update(_validFrame());
}

/// Feeds one frame with NO flags active (UNKNOWN/noise).
bool _feedUnknown(MultiPhaseSequenceTracker tracker, List<_Flag> allFlags) {
  for (final f in allFlags) {
    f.value = false;
  }
  return tracker.update(_validFrame());
}

void main() {
  group('MultiPhaseSequenceTracker — generic engine', () {
    // ── BASIC COMPLETION ────────────────────────────────────────────────────

    test('A → B → C → RESET = 1 completion', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;
      final flags = [ctx.flagA, ctx.flagB, ctx.flagC];

      // Phase A: 3 stable frames
      _feedFrames(tracker, ctx.flagA, flags, 3);
      expect(tracker.currentPhaseId, 'A');

      // Phase B: 3 stable frames
      _feedFrames(tracker, ctx.flagB, flags, 3);
      expect(tracker.currentPhaseId, 'B');

      // Phase C: 3 stable frames → completion
      _feedFrames(tracker, ctx.flagC, flags, 3);
      expect(tracker.completionCount, 1);
      expect(tracker.state, SequenceState.completed);
    });

    test('A → B → C → RESET, A → B → C → RESET = 2 completions', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;
      final flags = [ctx.flagA, ctx.flagB, ctx.flagC];

      // First cycle
      _feedFrames(tracker, ctx.flagA, flags, 3);
      _feedFrames(tracker, ctx.flagB, flags, 3);
      _feedFrames(tracker, ctx.flagC, flags, 3);
      expect(tracker.completionCount, 1);

      // Cooldown (3 frames, no flags)
      _feedUnknown(tracker, flags);
      _feedUnknown(tracker, flags);
      _feedUnknown(tracker, flags);
      expect(tracker.state, SequenceState.awaitingReset);

      // Reset condition
      _feedOne(tracker, ctx.flagReset, [...flags, ctx.flagReset]);
      expect(tracker.state, SequenceState.idle);

      // Second cycle
      _feedFrames(tracker, ctx.flagA, flags, 3);
      _feedFrames(tracker, ctx.flagB, flags, 3);
      _feedFrames(tracker, ctx.flagC, flags, 3);
      expect(tracker.completionCount, 2);
    });

    // ── SKIPPED / MISSING PHASES ────────────────────────────────────────────

    test('A → C = 0 (skipped phase B)', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;
      final flags = [ctx.flagA, ctx.flagB, ctx.flagC];

      // Phase A: 3 stable frames
      _feedFrames(tracker, ctx.flagA, flags, 3);
      expect(tracker.currentPhaseId, 'A');

      // Jump to C (skip B) → wrong-phase reset
      _feedFrames(tracker, ctx.flagC, flags, 3);
      expect(tracker.completionCount, 0);
      expect(tracker.state, SequenceState.idle);
      expect(tracker.currentPhaseIndex, -1);
    });

    test('B → C = 0 (missing first phase)', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;
      final flags = [ctx.flagA, ctx.flagB, ctx.flagC];

      // Start with B (expected A) → wrong-phase reset
      _feedFrames(tracker, ctx.flagB, flags, 3);
      expect(tracker.completionCount, 0);
      expect(tracker.state, SequenceState.idle);
    });

    // ── REPEATED PHASE ──────────────────────────────────────────────────────

    test('A → B → B → B → C = 1 (holding B longer)', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;
      final flags = [ctx.flagA, ctx.flagB, ctx.flagC];

      // Phase A
      _feedFrames(tracker, ctx.flagA, flags, 3);
      expect(tracker.currentPhaseId, 'A');

      // Phase B for 6 frames (double the stable requirement)
      _feedFrames(tracker, ctx.flagB, flags, 6);
      expect(tracker.currentPhaseId, 'B');

      // Phase C → completion
      _feedFrames(tracker, ctx.flagC, flags, 3);
      expect(tracker.completionCount, 1);
    });

    // ── NOISE POLICY ────────────────────────────────────────────────────────

    test('A → B → UNKNOWN → B → C = 1 (noise resets candidate, not phase)', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;
      final flags = [ctx.flagA, ctx.flagB, ctx.flagC];

      // Phase A
      _feedFrames(tracker, ctx.flagA, flags, 3);
      expect(tracker.currentPhaseId, 'A');

      // Phase B: 2 frames (not yet stable)
      _feedFrames(tracker, ctx.flagB, flags, 2);

      // UNKNOWN frame — resets candidate frames but not current phase
      _feedUnknown(tracker, flags);
      expect(tracker.currentPhaseId, 'A');

      // Phase B again: 3 stable frames
      _feedFrames(tracker, ctx.flagB, flags, 3);
      expect(tracker.currentPhaseId, 'B');

      // Phase C → completion
      _feedFrames(tracker, ctx.flagC, flags, 3);
      expect(tracker.completionCount, 1);
    });

    // ── WRONG-PHASE POLICY ──────────────────────────────────────────────────

    test('A → B → A = 0 (wrong-phase resets to idle)', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;
      final flags = [ctx.flagA, ctx.flagB, ctx.flagC];

      // Phase A
      _feedFrames(tracker, ctx.flagA, flags, 3);
      expect(tracker.currentPhaseId, 'A');

      // Phase B
      _feedFrames(tracker, ctx.flagB, flags, 3);
      expect(tracker.currentPhaseId, 'B');

      // Back to A (wrong phase — expected C) → reset
      _feedFrames(tracker, ctx.flagA, flags, 3);
      expect(tracker.completionCount, 0);
      expect(tracker.state, SequenceState.idle);
      expect(tracker.currentPhaseIndex, -1);
    });

    // ── RESET ───────────────────────────────────────────────────────────────

    test('A → B, then reset() = 0 and initial state', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;
      final flags = [ctx.flagA, ctx.flagB, ctx.flagC];

      _feedFrames(tracker, ctx.flagA, flags, 3);
      _feedFrames(tracker, ctx.flagB, flags, 2);
      expect(tracker.currentPhaseId, 'A');

      tracker.reset();
      expect(tracker.completionCount, 0);
      expect(tracker.state, SequenceState.idle);
      expect(tracker.currentPhaseIndex, -1);
      expect(tracker.currentPhaseId, isNull);
    });

    // ── COMPLETION + REARM ──────────────────────────────────────────────────

    test('final phase held many frames = still exactly 1 completion', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;
      final flags = [ctx.flagA, ctx.flagB, ctx.flagC];

      _feedFrames(tracker, ctx.flagA, flags, 3);
      _feedFrames(tracker, ctx.flagB, flags, 3);

      // Phase C: 3 stable → completion
      _feedFrames(tracker, ctx.flagC, flags, 3);
      expect(tracker.completionCount, 1);

      // Hold C for 20 more frames — no additional completions
      _feedFrames(tracker, ctx.flagC, flags, 20);
      expect(tracker.completionCount, 1);
    });

    test('completion requires reset condition before next cycle', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;
      final flags = [ctx.flagA, ctx.flagB, ctx.flagC];

      // Complete first cycle
      _feedFrames(tracker, ctx.flagA, flags, 3);
      _feedFrames(tracker, ctx.flagB, flags, 3);
      _feedFrames(tracker, ctx.flagC, flags, 3);
      expect(tracker.completionCount, 1);

      // Cooldown frames (no flags)
      _feedUnknown(tracker, flags);
      _feedUnknown(tracker, flags);
      _feedUnknown(tracker, flags);
      expect(tracker.state, SequenceState.awaitingReset);

      // Try to start A without reset condition — should not progress
      // because we're in awaitingReset state.
      _feedFrames(tracker, ctx.flagA, flags, 3);
      expect(
        tracker.completionCount,
        1,
        reason: 'Should not start new cycle without reset condition',
      );
      expect(tracker.state, SequenceState.awaitingReset);

      // Now satisfy reset condition
      ctx.flagReset.value = true;
      ctx.flagA.value = false;
      ctx.flagB.value = false;
      ctx.flagC.value = false;
      tracker.update(_validFrame());
      expect(tracker.state, SequenceState.idle);

      // Now can start new cycle
      _feedFrames(tracker, ctx.flagA, flags, 3);
      _feedFrames(tracker, ctx.flagB, flags, 3);
      _feedFrames(tracker, ctx.flagC, flags, 3);
      expect(tracker.completionCount, 2);
    });

    // ── MISSING LANDMARKS ───────────────────────────────────────────────────

    test('missing landmarks = no false completion', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;

      // Feed frames with missing landmarks — no progress
      for (var i = 0; i < 20; i++) {
        tracker.update(_missingLandmarkFrame());
      }
      expect(tracker.completionCount, 0);
      expect(tracker.state, SequenceState.idle);
    });

    // ── PARTIAL SEQUENCE ────────────────────────────────────────────────────

    test('A → B (incomplete) = 0 completions', () {
      final ctx = _buildABCSequence();
      final tracker = ctx.tracker;
      final flags = [ctx.flagA, ctx.flagB, ctx.flagC];

      _feedFrames(tracker, ctx.flagA, flags, 3);
      _feedFrames(tracker, ctx.flagB, flags, 3);
      expect(tracker.completionCount, 0);
      expect(tracker.currentPhaseId, 'B');
    });

    // ── PER-PHASE STABLE FRAMES ─────────────────────────────────────────────

    test('per-phase stableFrames — phase not advanced before threshold', () {
      final flagA = _Flag(false);
      final flagB = _Flag(false);
      final flagC = _Flag(false);
      final flagReset = _Flag(false);

      final definition = MultiPhaseSequenceDefinition(
        phases: [
          SequencePhaseDefinition(
            id: 'A',
            condition: _FlagCondition(flagA),
            stableFrames: 5, // A needs 5 frames
          ),
          SequencePhaseDefinition(
            id: 'B',
            condition: _FlagCondition(flagB),
            stableFrames: 2, // B needs only 2 frames
          ),
          SequencePhaseDefinition(
            id: 'C',
            condition: _FlagCondition(flagC),
            stableFrames: 3,
          ),
        ],
        resetCondition: _FlagCondition(flagReset),
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
        cooldownFrames: 3,
      );

      final tracker = MultiPhaseSequenceTracker(definition: definition);
      final flags = [flagA, flagB, flagC];

      // A: 4 frames — not enough (needs 5)
      _feedFrames(tracker, flagA, flags, 4);
      expect(
        tracker.currentPhaseId,
        isNull,
        reason: 'Phase A not yet stable (needs 5, got 4)',
      );

      // A: 1 more frame — now stable
      _feedOne(tracker, flagA, flags);
      expect(tracker.currentPhaseId, 'A');

      // B: 1 frame — not enough (needs 2)
      _feedOne(tracker, flagB, flags);
      expect(tracker.currentPhaseId, 'A');

      // B: 1 more frame — now stable
      _feedOne(tracker, flagB, flags);
      expect(tracker.currentPhaseId, 'B');
    });
  });

  // ── FACTORY CAPABILITY INVENTORY ───────────────────────────────────────────

  group('FactoryPrimitive inventory — multiPhaseSequence', () {
    test('multiPhaseSequence is registered as a factory primitive', () {
      expect(
        FactoryPrimitive.values,
        contains(FactoryPrimitive.multiPhaseSequence),
      );
    });

    test('factoryPrimitives includes multiPhaseSequence', () {
      expect(factoryPrimitives, contains(FactoryPrimitive.multiPhaseSequence));
    });

    test('airDetection still registered (no regression)', () {
      expect(factoryPrimitives, contains(FactoryPrimitive.airDetection));
    });

    test('all per-frame primitives still present (no regression)', () {
      expect(factoryPrimitives, contains(FactoryPrimitive.hipToKneeRatio));
      expect(
        factoryPrimitives,
        contains(FactoryPrimitive.ankleWidthToBodyWidth),
      );
      expect(
        factoryPrimitives,
        contains(FactoryPrimitive.kneeSeparationToHipWidth),
      );
      expect(factoryPrimitives, contains(FactoryPrimitive.leftKneeAngle));
      expect(factoryPrimitives, contains(FactoryPrimitive.rightKneeAngle));
      expect(
        factoryPrimitives,
        contains(FactoryPrimitive.wristsAboveShoulders),
      );
      expect(factoryPrimitives, contains(FactoryPrimitive.wristsNearBody));
    });
  });
}
