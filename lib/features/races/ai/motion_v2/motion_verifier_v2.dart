import '../../data/ai_motion_models.dart';
import 'motion_v2_models.dart';

/// Live Motion V2 recognition. The single thing Flutter talks to for V2 —
/// implementations (dev HTTP service now, on-device later) hide MotionBERT.
abstract interface class MotionVerifierV2 {
  /// Load a learned movement. Starts a runtime session.
  Future<void> load(TaughtMotionV2Spec spec);

  /// Feed one (or a small batch of) pose frame(s). Returns the latest
  /// recognition state; `result.newRep` is the signal to fire `+1`.
  Future<MotionV2RuntimeResult> update(List<NuvoPoseFrame> frames);

  /// Clear the rolling buffer + rep count (new test attempt).
  Future<void> reset();

  Future<void> dispose();
}

/// Learns a [TaughtMotionV2Spec] from the 3 raw demo pose streams.
abstract interface class MotionLearnerV2 {
  Future<TaughtMotionV2Spec> learn({
    required String movementName,
    required List<List<NuvoPoseFrame>> demos,
  });
}
