import 'dart:math' as math;

import 'normalized_pose.dart';
import 'pose_calibration_models.dart';
import 'pose_sequence_frame.dart';

class PoseDemonstrationCapture {
  PoseDemonstrationCapture({
    required this.index,
    this.minDuration = const Duration(milliseconds: 600),
    this.maxDuration = const Duration(seconds: 8),
    this.minProcessedFrames = 6,
    this.minValidFrameRatio = 0.60,
    this.maxFrameCount = 90,
  });

  final int index;
  final Duration minDuration;
  final Duration maxDuration;
  final int minProcessedFrames;
  final double minValidFrameRatio;
  final int maxFrameCount;

  final List<_CapturedPose> _frames = [];
  DateTime? _startedAt;
  int _processedFrameCount = 0;
  int _validFrameCount = 0;
  bool _interrupted = false;

  bool get isRecording => _startedAt != null && !_interrupted;
  int get processedFrameCount => _processedFrameCount;
  int get storedFrameCount => _frames.length;

  void start(DateTime now) {
    _startedAt = now;
    _processedFrameCount = 0;
    _validFrameCount = 0;
    _interrupted = false;
    _frames.clear();
  }

  void addFrame(NormalizedPose pose, DateTime now) {
    final started = _startedAt;
    if (started == null || _interrupted) return;
    _processedFrameCount++;
    if (pose.isValid) {
      _validFrameCount++;
      if (_frames.length < maxFrameCount) {
        _frames.add(_CapturedPose(pose, now.difference(started)));
      }
    }
  }

  void interrupt() {
    _interrupted = true;
  }

  PoseDemonstration finish(DateTime now) {
    final started = _startedAt;
    if (started == null) {
      return _rejected('not_recording', Duration.zero);
    }
    final duration = now.difference(started);
    if (_interrupted) return _rejected('capture_interrupted', duration);
    if (duration < minDuration) return _rejected('too_short', duration);
    if (duration > maxDuration) return _rejected('too_long', duration);
    if (_processedFrameCount < minProcessedFrames) {
      return _rejected('too_few_processed_frames', duration);
    }
    final validRatio = _validFrameCount / math.max(1, _processedFrameCount);
    if (validRatio < minValidFrameRatio) {
      return _rejected('low_valid_frame_ratio', duration);
    }
    final sequence = _sequenceFrames(duration);
    return PoseDemonstration(
      index: index,
      frames: sequence,
      durationMs: duration.inMilliseconds,
      processedFrameCount: _processedFrameCount,
      validFrameCount: _validFrameCount,
      validFrameRatio: validRatio.clamp(0.0, 1.0),
      averageVisibility: _averageCoverage(_frames.map((frame) => frame.pose)),
      accepted: true,
    );
  }

  PoseDemonstration _rejected(String reason, Duration duration) {
    return PoseDemonstration(
      index: index,
      frames: const [],
      durationMs: duration.inMilliseconds,
      processedFrameCount: _processedFrameCount,
      validFrameCount: _validFrameCount,
      validFrameRatio: _validFrameCount / math.max(1, _processedFrameCount),
      averageVisibility: _averageCoverage(_frames.map((frame) => frame.pose)),
      accepted: false,
      rejectionReason: reason,
    );
  }

  List<PoseSequenceFrame> _sequenceFrames(Duration duration) {
    final totalMs = math.max(1, duration.inMilliseconds);
    return _frames
        .map(
          (frame) => PoseSequenceFrame(
            schemaVersion: normalizedPoseSchemaVersion,
            position: (frame.elapsed.inMilliseconds / totalMs).clamp(0.0, 1.0),
            elapsedMs: frame.elapsed.inMilliseconds,
            pose: frame.pose,
          ),
        )
        .toList(growable: false);
  }

  double _averageCoverage(Iterable<NormalizedPose> poses) {
    final values = poses
        .map(
          (pose) => pose.features.values.isEmpty
              ? 0.0
              : pose.validFeatureCount / pose.features.values.length,
        )
        .toList(growable: false);
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

class _CapturedPose {
  const _CapturedPose(this.pose, this.elapsed);

  final NormalizedPose pose;
  final Duration elapsed;
}
