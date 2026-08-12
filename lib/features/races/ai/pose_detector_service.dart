import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../data/ai_motion_models.dart';
import 'camera_image_converter.dart';
import 'pose_landmark_smoother.dart';

class PoseDetectorService {
  PoseDetectorService({
    // ML Kit runs in stream mode. Keep a 30 FPS target while the in-flight
    // guard drops frames when inference or image conversion is slower.
    Duration minFrameInterval = const Duration(milliseconds: 33),
  }) : this._(minFrameInterval);

  PoseDetectorService._(this._minFrameInterval)
    : _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          model: PoseDetectionModel.base,
          mode: PoseDetectionMode.stream,
        ),
      );

  final PoseDetector _poseDetector;
  final Duration _minFrameInterval;
  final PoseLandmarkSmoother _smoother = PoseLandmarkSmoother();

  bool _isProcessingFrame = false;
  bool _disposed = false;
  DateTime? _lastProcessedAt;

  bool get isProcessingFrame => _isProcessingFrame;

  Future<NuvoPoseFrame?> processCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) async {
    if (_disposed || _isProcessingFrame) return null;

    final now = DateTime.now();
    final lastProcessedAt = _lastProcessedAt;
    if (lastProcessedAt != null &&
        now.difference(lastProcessedAt) < _minFrameInterval) {
      return null;
    }

    _isProcessingFrame = true;
    _lastProcessedAt = now;
    try {
      final inputImage = inputImageFromCameraImage(
        image: image,
        camera: camera,
        deviceOrientation: deviceOrientation,
      );
      final poses = await _poseDetector.processImage(inputImage);
      if (_disposed) return null;
      if (poses.isEmpty) {
        return NuvoPoseFrame(
          points: const {},
          imageWidth: image.width.toDouble(),
          imageHeight: image.height.toDouble(),
          createdAt: now,
        );
      }

      final pose = poses.first;
      final points = <String, NuvoPosePoint>{};
      for (final entry in pose.landmarks.entries) {
        points[entry.key.name] = NuvoPosePoint(
          x: (entry.value.x / image.width).clamp(0.0, 1.0),
          y: (entry.value.y / image.height).clamp(0.0, 1.0),
          z: entry.value.z,
          likelihood: entry.value.likelihood.clamp(0.0, 1.0),
        );
      }

      final frame = NuvoPoseFrame(
        points: points,
        imageWidth: image.width.toDouble(),
        imageHeight: image.height.toDouble(),
        createdAt: now,
      );
      return _smoother.smooth(frame);
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _smoother.reset();
    await _poseDetector.close();
  }
}
