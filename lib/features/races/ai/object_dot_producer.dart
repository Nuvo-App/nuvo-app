import '../data/ai_motion_models.dart';
import 'object_motion_models.dart';

/// Local boundary for an object detector.
///
/// Implementations may use camera pixels internally, but the verifier and
/// telemetry layers only receive [NuvoObjectMotionFrame]. A producer must
/// never return or upload a camera frame.
abstract interface class ObjectDotProducer {
  const ObjectDotProducer();

  /// Capabilities are negotiated only when a real producer is installed.
  Set<String> get capabilities;

  Future<NuvoObjectMotionFrame?> process({
    required NuvoPoseFrame pose,
    required DateTime createdAt,
  });
}

/// Explicitly represents a build that has no object detector yet. Keeping this
/// as a first-class boundary prevents the app from claiming basketball support
/// merely because the control plane knows about a basketball release.
class UnsupportedObjectDotProducer implements ObjectDotProducer {
  const UnsupportedObjectDotProducer();

  @override
  Set<String> get capabilities => const <String>{};

  @override
  Future<NuvoObjectMotionFrame?> process({
    required NuvoPoseFrame pose,
    required DateTime createdAt,
  }) async => null;
}
