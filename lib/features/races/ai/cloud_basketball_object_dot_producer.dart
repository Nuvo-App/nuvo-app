import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

import '../data/ai_motion_models.dart';
import 'basketball_object_projector.dart';
import 'motion_model_artifact_integrity.dart';
import 'object_dot_producer.dart';
import 'object_motion_models.dart';
import 'yolox_object_detection.dart';

/// An on-device basketball detector backed by the model bytes selected by the
/// immutable Cloudflare release.
///
/// This class is deliberately the only place where camera pixels and ONNX
/// tensors meet. The producer returns normalized dots and never exposes a
/// pixel buffer to the verifier, recorder, or upload queue.
class CloudBasketballObjectDotProducer implements ObjectDotProducer {
  CloudBasketballObjectDotProducer._(
    this._session, {
    required this.modelVersion,
    required this.inputSize,
  }) : _decoder = YoloXBasketballObjectDecoder(inputSize: inputSize);

  final OrtSession _session;
  final BasketballObjectProjector _projector =
      const BasketballObjectProjector();
  final YoloXBasketballObjectDecoder _decoder;
  final String modelVersion;
  final int inputSize;
  bool _disposed = false;

  static Future<CloudBasketballObjectDotProducer> load(
    VettedMotionModelArtifact artifact, {
    required int inputSize,
  }) async {
    if (inputSize < 160 || inputSize > 1280) {
      throw const FormatException('Basketball model input size is invalid.');
    }
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(2)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    try {
      final session = OrtSession.fromBuffer(artifact.bytes, options);
      if (session.inputNames.isEmpty || session.outputNames.isEmpty) {
        session.release();
        throw const FormatException('Basketball model has no IO tensors.');
      }
      return CloudBasketballObjectDotProducer._(
        session,
        modelVersion: artifact.modelVersion,
        inputSize: inputSize,
      );
    } finally {
      options.release();
    }
  }

  @override
  Set<String> get capabilities => const <String>{
    'object_dots_v1',
    'object_composition_v1',
  };

  @override
  Future<NuvoObjectMotionFrame?> process({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
    required NuvoPoseFrame pose,
    required DateTime createdAt,
  }) async {
    if (_disposed) return null;
    final tensorData = _CameraTensor.fromImage(image, inputSize);
    final input = OrtValueTensor.createTensorWithDataList(
      <Float32List>[tensorData.data],
      [1, 3, inputSize, inputSize],
    );
    final options = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await _session.runAsync(
        options,
        {_session.inputNames.first: input},
        [_session.outputNames.first],
      );
    } finally {
      input.release();
      options.release();
    }
    if (outputs == null || outputs.isEmpty || outputs.first == null) {
      return null;
    }
    try {
      final values = _flattenNumbers(outputs.first!.value);
      const attributes = 15;
      if (values.length < attributes || values.length % attributes != 0) {
        throw const FormatException(
          'Basketball model output shape is unsupported.',
        );
      }
      final detections = _decoder.decode(
        output: values,
        candidateCount: values.length ~/ attributes,
        attributesPerCandidate: attributes,
        sourceWidth: image.width.toDouble(),
        sourceHeight: image.height.toDouble(),
      );
      return _projector.project(
        pose: pose,
        createdAt: createdAt,
        detections: detections,
      );
    } finally {
      for (final output in outputs) {
        output?.release();
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _session.release();
  }

  static List<double> _flattenNumbers(Object? value) {
    if (value is num) return [value.toDouble()];
    if (value is List) {
      final result = <double>[];
      for (final item in value) {
        result.addAll(_flattenNumbers(item));
      }
      return result;
    }
    throw const FormatException('Basketball model output is not numeric.');
  }
}

/// Minimal BGR top-left letterbox conversion for the two camera formats used
/// by the basketball model. The published YOLOX release expects raw 0-255
/// values, no normalization, and a pad value of 114. It intentionally
/// produces only a tensor; it does not retain the source image after
/// inference returns.
class _CameraTensor {
  _CameraTensor(this.data);

  final Float32List data;

  factory _CameraTensor.fromImage(CameraImage image, int size) {
    final yPlane = image.planes.firstOrNull;
    if (yPlane == null) {
      throw const FormatException('Camera image has no pixel plane.');
    }
    final output = Float32List(3 * size * size);
    final scale = math.min(size / image.width, size / image.height);
    // The basketball release uses top-left letterboxing. The decoder applies
    // the same scale without subtracting a centered pad, so these must stay
    // aligned with the model contract.
    const double padValue = 114;
    const padX = 0;
    const padY = 0;
    final isBgra = image.format.group == ImageFormatGroup.bgra8888;
    for (var y = 0; y < size; y++) {
      final sourceY = ((y - padY) / scale).floor();
      for (var x = 0; x < size; x++) {
        final sourceX = ((x - padX) / scale).floor();
        var red = padValue;
        var green = padValue;
        var blue = padValue;
        if (sourceX >= 0 &&
            sourceY >= 0 &&
            sourceX < image.width &&
            sourceY < image.height) {
          if (isBgra) {
            final pixel =
                sourceY * yPlane.bytesPerRow +
                sourceX * (yPlane.bytesPerPixel ?? 4);
            if (pixel + 2 < yPlane.bytes.length) {
              blue = yPlane.bytes[pixel].toDouble();
              green = yPlane.bytes[pixel + 1].toDouble();
              red = yPlane.bytes[pixel + 2].toDouble();
            }
          } else {
            final uvPlane = image.planes.length > 1 ? image.planes[1] : yPlane;
            final yIndex =
                sourceY * yPlane.bytesPerRow +
                sourceX * (yPlane.bytesPerPixel ?? 1);
            final uvIndex =
                (sourceY ~/ 2) * uvPlane.bytesPerRow +
                (sourceX ~/ 2) * (uvPlane.bytesPerPixel ?? 2);
            if (yIndex < yPlane.bytes.length &&
                uvIndex + 1 < uvPlane.bytes.length) {
              final luma = yPlane.bytes[yIndex].toDouble();
              // ImageFormatGroup.nv21 stores the chroma pair as V then U.
              final v = uvPlane.bytes[uvIndex].toDouble() - 128;
              final u = uvPlane.bytes[uvIndex + 1].toDouble() - 128;
              red = (luma + 1.402 * v).round().clamp(0, 255).toDouble();
              green = (luma - 0.344136 * u - 0.714136 * v)
                  .round()
                  .clamp(0, 255)
                  .toDouble();
              blue = (luma + 1.772 * u).round().clamp(0, 255).toDouble();
            }
          }
        }
        final index = y * size + x;
        // ONNX input is BGR, not RGB, and the release does not normalize.
        output[index] = blue;
        output[size * size + index] = green;
        output[2 * size * size + index] = red;
      }
    }
    return _CameraTensor(output);
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
