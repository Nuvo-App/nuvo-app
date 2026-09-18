import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import '../data/ai_motion_models.dart';
import 'basketball_object_projector.dart';
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
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
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
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
    required NuvoPoseFrame pose,
    required DateTime createdAt,
  }) async => null;
}

typedef LocalObjectDetection =
    Future<Iterable<NuvoObjectDetection>> Function({
      required CameraImage image,
      required CameraDescription camera,
      required DeviceOrientation deviceOrientation,
    });

/// Connects a vetted local detector model to the stable Nuvo dot contract.
///
/// The callback is the only model-specific piece. It may run ONNX Runtime or
/// another on-device engine, but its output is immediately reduced to
/// normalized ball/hoop dots before it can reach the verifier or telemetry.
class ModelBackedBasketballObjectDotProducer implements ObjectDotProducer {
  ModelBackedBasketballObjectDotProducer({required this.detect});

  final LocalObjectDetection detect;
  final BasketballObjectProjector _projector =
      const BasketballObjectProjector();

  @override
  Set<String> get capabilities => const <String>{
    'object_dots_v1',
    'object_composition_v1',
  };

  @override
  Future<NuvoObjectMotionFrame> process({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
    required NuvoPoseFrame pose,
    required DateTime createdAt,
  }) async {
    final detections = await detect(
      image: image,
      camera: camera,
      deviceOrientation: deviceOrientation,
    );
    return _projector.project(
      pose: pose,
      createdAt: createdAt,
      detections: detections,
    );
  }
}
