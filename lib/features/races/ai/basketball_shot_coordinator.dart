import 'object_motion_models.dart';
import 'motion_session/motion_session_recorder.dart';
import 'object_composition_runtime.dart';

/// Joins the local object-dot stream, the basketball composition graph, and
/// the existing motion-session recorder.
///
/// This seam is intentionally camera-agnostic. The camera screen supplies a
/// pose-plus-dot frame; this coordinator never receives pixels and never
/// decides which model produced the dots.
class BasketballShotCoordinator {
  BasketballShotCoordinator({required this.runtime, this.recorder});

  final BasketballShotRuntime runtime;
  final MotionSessionRecorder? recorder;
  String? _lastEvent;

  ObjectCompositionUpdate process(NuvoObjectMotionFrame frame) {
    recorder?.recordObjectFrame(frame);
    final update = runtime.update(frame);
    if (update.event != _lastEvent) {
      recorder?.recordEvent(
        'object_composition',
        detail: update.event,
        metrics: {
          'confidence': update.confidence,
          'count': update.count.toDouble(),
        },
      );
      _lastEvent = update.event;
    }
    return update;
  }

  ObjectCompositionState get state => runtime.state;
  int get count => runtime.count;
}
