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

enum ObjectCompositionExpectedOutcome { made, missed }

class ObjectCompositionEvaluationExample {
  const ObjectCompositionEvaluationExample({
    required this.id,
    required this.expected,
    required this.frames,
  });

  final String id;
  final ObjectCompositionExpectedOutcome expected;
  final List<NuvoObjectMotionFrame> frames;
}

/// Promotion gate for held-out dot traces.
class ObjectCompositionEvaluationGateReport {
  const ObjectCompositionEvaluationGateReport({
    required this.total,
    required this.correct,
    required this.madeExamples,
    required this.madeCorrect,
    required this.missedExamples,
    required this.falsePositives,
    required this.passes,
  });

  final int total;
  final int correct;
  final int madeExamples;
  final int madeCorrect;
  final int missedExamples;
  final int falsePositives;
  final bool passes;

  double get madeRecall => madeExamples == 0 ? 0 : madeCorrect / madeExamples;
  double get falsePositiveRate =>
      missedExamples == 0 ? 0 : falsePositives / missedExamples;
}

class ObjectCompositionEvaluationGate {
  const ObjectCompositionEvaluationGate({
    this.minimumMadeRecall = 1,
    this.maximumFalsePositiveRate = 0,
  });

  final double minimumMadeRecall;
  final double maximumFalsePositiveRate;

  ObjectCompositionEvaluationGateReport evaluate({
    required ObjectCompositionSpec spec,
    required Iterable<ObjectCompositionEvaluationExample> examples,
  }) {
    var total = 0;
    var correct = 0;
    var madeExamples = 0;
    var madeCorrect = 0;
    var missedExamples = 0;
    var falsePositives = 0;
    for (final example in examples) {
      total++;
      final result = const ObjectCompositionReplayEvaluator().evaluate(
        spec: spec,
        frames: example.frames,
      );
      final predicted = result.made
          ? ObjectCompositionExpectedOutcome.made
          : ObjectCompositionExpectedOutcome.missed;
      if (predicted == example.expected) correct++;
      if (example.expected == ObjectCompositionExpectedOutcome.made) {
        madeExamples++;
        if (predicted == example.expected) madeCorrect++;
      } else {
        missedExamples++;
        if (predicted == ObjectCompositionExpectedOutcome.made) {
          falsePositives++;
        }
      }
    }
    final madeRecall = madeExamples == 0 ? 0.0 : madeCorrect / madeExamples;
    final falsePositiveRate = missedExamples == 0
        ? 0.0
        : falsePositives / missedExamples;
    return ObjectCompositionEvaluationGateReport(
      total: total,
      correct: correct,
      madeExamples: madeExamples,
      madeCorrect: madeCorrect,
      missedExamples: missedExamples,
      falsePositives: falsePositives,
      passes:
          total > 0 &&
          madeRecall >= minimumMadeRecall &&
          falsePositiveRate <= maximumFalsePositiveRate,
    );
  }
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
