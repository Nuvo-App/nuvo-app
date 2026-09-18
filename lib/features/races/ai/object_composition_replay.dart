import 'object_composition_runtime.dart';
import 'object_composition_spec.dart';
import 'object_motion_models.dart';

/// Result of replaying a dot-only object-composition trace.
class ObjectCompositionReplayResult {
  const ObjectCompositionReplayResult({
    required this.updates,
    required this.finalState,
    required this.detectedCount,
  });

  final List<ObjectCompositionUpdate> updates;
  final ObjectCompositionState finalState;
  final int detectedCount;

  bool get made => finalState == ObjectCompositionState.made;
  bool get missed => finalState == ObjectCompositionState.missed;
  bool get reachedTerminalState => made || missed;
}

/// Replays the exact dot stream that the local verifier would receive.
///
/// This is deliberately independent of camera, model, and network code. It is
/// used by acceptance tooling to compare held-out made shots with airballs,
/// rim-outs, fake releases, and incomplete traces without ever needing raw
/// video.
class ObjectCompositionReplayEvaluator {
  const ObjectCompositionReplayEvaluator();

  ObjectCompositionReplayResult evaluate({
    required ObjectCompositionSpec spec,
    required Iterable<NuvoObjectMotionFrame> frames,
  }) {
    final runtime = BasketballShotRuntime(spec: spec);
    final updates = <ObjectCompositionUpdate>[];
    for (final frame in frames) {
      updates.add(runtime.update(frame));
      if (runtime.state == ObjectCompositionState.made ||
          runtime.state == ObjectCompositionState.missed) {
        break;
      }
    }
    return ObjectCompositionReplayResult(
      updates: List.unmodifiable(updates),
      finalState: runtime.state,
      detectedCount: runtime.count,
    );
  }
}
