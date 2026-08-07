import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import '../../data/ai_motion_models.dart';
import '../pose_detector_service.dart';
import 'normalized_pose.dart';
import 'pose_normalizer.dart';

class PoseStreamState {
  const PoseStreamState({
    this.latestFrame,
    this.latestPose,
    this.lastGoodFrame,
    this.lastGoodPose,
    this.lastGoodPoseAt,
    this.framesReceived = 0,
    this.framesProcessed = 0,
    this.framesDropped = 0,
    this.emptyPoseCount = 0,
    this.detectorBusy = false,
  });

  final NuvoPoseFrame? latestFrame;
  final NormalizedPose? latestPose;
  final NuvoPoseFrame? lastGoodFrame;
  final NormalizedPose? lastGoodPose;
  final DateTime? lastGoodPoseAt;
  final int framesReceived;
  final int framesProcessed;
  final int framesDropped;
  final int emptyPoseCount;
  final bool detectorBusy;

  int? poseAgeMs(DateTime now) {
    final last = lastGoodPoseAt;
    if (last == null) return null;
    return now.difference(last).inMilliseconds;
  }

  PoseStreamState copyWith({
    NuvoPoseFrame? latestFrame,
    NormalizedPose? latestPose,
    NuvoPoseFrame? lastGoodFrame,
    NormalizedPose? lastGoodPose,
    DateTime? lastGoodPoseAt,
    int? framesReceived,
    int? framesProcessed,
    int? framesDropped,
    int? emptyPoseCount,
    bool? detectorBusy,
  }) {
    return PoseStreamState(
      latestFrame: latestFrame ?? this.latestFrame,
      latestPose: latestPose ?? this.latestPose,
      lastGoodFrame: lastGoodFrame ?? this.lastGoodFrame,
      lastGoodPose: lastGoodPose ?? this.lastGoodPose,
      lastGoodPoseAt: lastGoodPoseAt ?? this.lastGoodPoseAt,
      framesReceived: framesReceived ?? this.framesReceived,
      framesProcessed: framesProcessed ?? this.framesProcessed,
      framesDropped: framesDropped ?? this.framesDropped,
      emptyPoseCount: emptyPoseCount ?? this.emptyPoseCount,
      detectorBusy: detectorBusy ?? this.detectorBusy,
    );
  }
}

class PoseStreamUpdate {
  const PoseStreamUpdate({
    required this.state,
    this.frame,
    this.pose,
    this.skipped = false,
  });

  final PoseStreamState state;
  final NuvoPoseFrame? frame;
  final NormalizedPose? pose;
  final bool skipped;
}

class PoseStreamController {
  PoseStreamController({
    PoseDetectorService? poseDetector,
    PoseNormalizer? normalizer,
  }) : _poseDetector =
           poseDetector ?? PoseDetectorService(minFrameInterval: Duration.zero),
       _normalizer = normalizer ?? const PoseNormalizer();

  final PoseDetectorService _poseDetector;
  final PoseNormalizer _normalizer;

  PoseStreamState _state = const PoseStreamState();
  bool _processing = false;
  bool _disposed = false;

  PoseStreamState get state => _state;

  Future<PoseStreamUpdate> processCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) async {
    if (_disposed) return PoseStreamUpdate(state: _state, skipped: true);
    _state = _state.copyWith(framesReceived: _state.framesReceived + 1);
    if (_processing) {
      _state = _state.copyWith(framesDropped: _state.framesDropped + 1);
      return PoseStreamUpdate(state: _state, skipped: true);
    }

    _processing = true;
    _state = _state.copyWith(detectorBusy: true);
    try {
      final frame = await _poseDetector.processCameraImage(
        image: image,
        camera: camera,
        deviceOrientation: deviceOrientation,
      );
      if (frame == null) {
        _state = _state.copyWith(framesDropped: _state.framesDropped + 1);
        return PoseStreamUpdate(state: _state, skipped: true);
      }

      final pose = _normalizer.normalize(frame);
      final hasBody = pose.isValid && pose.validLandmarkCount >= 3;
      _state = _state.copyWith(
        latestFrame: frame,
        latestPose: pose,
        lastGoodFrame: hasBody ? frame : _state.lastGoodFrame,
        lastGoodPose: hasBody ? pose : _state.lastGoodPose,
        lastGoodPoseAt: hasBody ? DateTime.now() : _state.lastGoodPoseAt,
        framesProcessed: _state.framesProcessed + 1,
        emptyPoseCount: hasBody
            ? _state.emptyPoseCount
            : _state.emptyPoseCount + 1,
      );
      return PoseStreamUpdate(state: _state, frame: frame, pose: pose);
    } finally {
      _processing = false;
      _state = _state.copyWith(detectorBusy: false);
    }
  }

  void reset() {
    _state = const PoseStreamState();
  }

  Future<void> dispose() async {
    _disposed = true;
    await _poseDetector.dispose();
  }
}
