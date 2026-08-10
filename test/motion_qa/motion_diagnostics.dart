import 'package:nuvo/features/races/ai/airborne_state_tracker.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/multi_phase_sequence_tracker.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// Snapshot of internal tracker state at a single frame.
/// Used for diagnostics only — not exposed in production UI.
class TrackerDiagnosticSnapshot {
  const TrackerDiagnosticSnapshot({
    required this.frameIndex,
    required this.detectedReps,
    required this.trackerStates,
    required this.airbornePhase,
    required this.airborneBaselineEstablished,
    required this.airborneBaselineY,
    required this.missingLandmarkFrames,
    required this.invalidFrames,
  });

  final int frameIndex;
  final int detectedReps;
  final List<SingleTrackerSnapshot> trackerStates;
  final String airbornePhase;
  final bool airborneBaselineEstablished;
  final double airborneBaselineY;
  final int missingLandmarkFrames;
  final int invalidFrames;
}

/// Snapshot of a single MultiPhaseSequenceTracker.
class SingleTrackerSnapshot {
  const SingleTrackerSnapshot({
    required this.state,
    required this.currentPhaseIndex,
    required this.currentPhaseId,
    required this.candidatePhaseIndex,
    required this.candidateFrames,
    required this.completionCount,
    required this.cooldownFramesRemaining,
    required this.totalPhases,
  });

  final String state;
  final int currentPhaseIndex;
  final String? currentPhaseId;
  final int candidatePhaseIndex;
  final int candidateFrames;
  final int completionCount;
  final int cooldownFramesRemaining;
  final int totalPhases;
}

/// Extracts diagnostic state from a MultiPhaseSequenceValidator.
/// This is test/internal tooling — not production UI.
class ValidatorDiagnostics {
  ValidatorDiagnostics._();

  /// Captures a diagnostic snapshot from a MultiPhaseSequenceValidator.
  static TrackerDiagnosticSnapshot snapshot(
    MultiPhaseSequenceValidator validator,
    int frameIndex, {
    int missingLandmarkFrames = 0,
    int invalidFrames = 0,
  }) {
    // Access internal trackers via the validator's public interface.
    // We use a reflective approach via known getters.
    // MultiPhaseSequenceValidator exposes _trackers and _airborne privately.
    // Since we can't access private fields from outside the library,
    // we capture what we can from public API + the tracker's own state.
    //
    // TECH DEBT: This uses a workaround — we create a sidecar tracker
    // pair that mirrors the validator's internal state by replaying
    // the same frames. This is not ideal but works for diagnostics.
    //
    // For now, we capture what's available from the validator's public API.
    return TrackerDiagnosticSnapshot(
      frameIndex: frameIndex,
      detectedReps: validator.currentValue,
      trackerStates: const [],
      airbornePhase: 'unknown',
      airborneBaselineEstablished: false,
      airborneBaselineY: 0,
      missingLandmarkFrames: missingLandmarkFrames,
      invalidFrames: invalidFrames,
    );
  }
}

/// A richer diagnostic collector that wraps a MultiPhaseSequenceValidator
/// and records per-frame state by maintaining sidecar trackers that mirror
/// the validator's internal state.
///
/// TECH DEBT: This duplicates tracker state because Dart private fields
/// are library-private. The sidecar trackers receive the same frames as
/// the validator, so their state should match. A future refactor could
/// expose diagnostic getters directly on the validator.
class DiagnosticCollector {
  DiagnosticCollector({
    required AiMotionActivity activity,
    required int target,
  }) : _validator = createMotionValidator(activity, target) {
    if (_validator is MultiPhaseSequenceValidator) {
      final mpv = _validator;
      final airborne = AirborneStateTracker();
      final defs = mpv.definitions(airborne);
      _sidecarTrackers = defs
          .map((def) => MultiPhaseSequenceTracker(definition: def))
          .toList(growable: false);
      _sidecarAirborne = airborne;
      _isMultiPhase = true;
    } else {
      _sidecarTrackers = const [];
      _sidecarAirborne = null;
      _isMultiPhase = false;
    }
  }

  final dynamic _validator;
  late List<MultiPhaseSequenceTracker> _sidecarTrackers;
  late AirborneStateTracker? _sidecarAirborne;
  late bool _isMultiPhase;

  dynamic get validator => _validator;

  final List<TrackerDiagnosticSnapshot> _snapshots = [];
  List<TrackerDiagnosticSnapshot> get snapshots => _snapshots;

  int _missingLandmarkFrames = 0;
  int _invalidFrames = 0;

  /// Feeds a frame through both the production validator and sidecar trackers.
  void update(NuvoPoseFrame frame) {
    _validator.update(frame);

    if (_isMultiPhase) {
      // Also feed sidecar trackers for diagnostics.
      _sidecarAirborne!.update(frame);
      for (final tracker in _sidecarTrackers) {
        tracker.update(frame);
      }

      // Track missing landmarks.
      if (!frame.hasPoints(_sidecarTrackers.first.definition.requiredLandmarks)) {
        _missingLandmarkFrames++;
      }
    }

    _snapshots.add(_captureSnapshot());
  }

  void start() {
    _validator.start();
    if (_isMultiPhase) {
      _sidecarAirborne!.reset();
      for (final t in _sidecarTrackers) {
        t.reset();
      }
    }
    _snapshots.clear();
    _missingLandmarkFrames = 0;
    _invalidFrames = 0;
  }

  TrackerDiagnosticSnapshot _captureSnapshot() {
    final frameIndex = _snapshots.length;
    final trackerStates = _sidecarTrackers.map((t) {
      return SingleTrackerSnapshot(
        state: t.state.name,
        currentPhaseIndex: t.currentPhaseIndex,
        currentPhaseId: t.currentPhaseId,
        candidatePhaseIndex: -1,
        candidateFrames: 0,
        completionCount: t.completionCount,
        cooldownFramesRemaining: 0,
        totalPhases: t.definition.phases.length,
      );
    }).toList();

    return TrackerDiagnosticSnapshot(
      frameIndex: frameIndex,
      detectedReps: _validator.currentValue,
      trackerStates: trackerStates,
      airbornePhase: _isMultiPhase ? _sidecarAirborne!.phase.name : 'n/a',
      airborneBaselineEstablished: _isMultiPhase ? _sidecarAirborne!.baselineEstablished : false,
      airborneBaselineY: _isMultiPhase ? _sidecarAirborne!.baselineAnkleY : 0,
      missingLandmarkFrames: _missingLandmarkFrames,
      invalidFrames: _invalidFrames,
    );
  }

  /// Summary of the last snapshot.
  TrackerDiagnosticSnapshot? get lastSnapshot =>
      _snapshots.isEmpty ? null : _snapshots.last;

  /// Total frames processed.
  int get totalFrames => _snapshots.length;

  /// Frames where required landmarks were missing.
  int get missingLandmarkFrames => _missingLandmarkFrames;

  /// Frames where airborne baseline was not yet established.
  int get awaitingBaselineFrames =>
      _snapshots.where((s) => !s.airborneBaselineEstablished).length;

  /// Frames where airborne phase was 'airborne'.
  int get airborneFrames =>
      _snapshots.where((s) => s.airbornePhase == 'airborne').length;

  /// Frames where airborne phase was 'grounded'.
  int get groundedFrames =>
      _snapshots.where((s) => s.airbornePhase == 'grounded').length;

  /// Frames where any tracker was in 'tracking' state.
  int get trackingFrames => _snapshots
      .where((s) => s.trackerStates.any((t) => t.state == 'tracking'))
      .length;

  /// Frames where any tracker was in 'completed' state.
  int get completedFrames => _snapshots
      .where((s) => s.trackerStates.any((t) => t.state == 'completed'))
      .length;

  /// Frames where any tracker was in 'awaitingReset' state.
  int get awaitingResetFrames => _snapshots
      .where((s) => s.trackerStates.any((t) => t.state == 'awaitingReset'))
      .length;

  /// Frames where any tracker was in 'idle' state (after first frame).
  int get idleFramesAfterStart => _snapshots
      .skip(1)
      .where((s) => s.trackerStates.isNotEmpty && s.trackerStates.every((t) => t.state == 'idle'))
      .length;
}
