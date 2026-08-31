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
  int _nextFrameSequence = 0;
  bool _interrupted = false;

  bool get isRecording => _startedAt != null && !_interrupted;
  int get processedFrameCount => _processedFrameCount;
  int get minProcessedFrameCount => minProcessedFrames;
  int get storedFrameCount => _frames.length;

  void start(DateTime now) {
    _startedAt = now;
    _processedFrameCount = 0;
    _validFrameCount = 0;
    _nextFrameSequence = 0;
    _interrupted = false;
    _frames.clear();
  }

  void addFrame(NormalizedPose pose, DateTime now) {
    final started = _startedAt;
    if (started == null || _interrupted) return;
    _processedFrameCount++;
    if (pose.isValid) {
      final elapsed = now.difference(started);
      if (elapsed.isNegative) return;
      _validFrameCount++;
      _frames.add(_CapturedPose(pose, elapsed, _nextFrameSequence++));
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
    if (_processedFrameCount < minProcessedFrames) {
      return _rejected('too_few_processed_frames', duration);
    }
    if (_validFrameCount == 0) {
      return _rejected('no_pose', duration);
    }
    final validRatio = _validFrameCount / math.max(1, _processedFrameCount);
    if (validRatio < minValidFrameRatio) {
      return _rejected('low_valid_frame_ratio', duration);
    }
    final sequence = _sequenceFrames(duration);
    if (!_isStructurallyValid(sequence, duration)) {
      return _rejected('non_monotonic_frames', duration);
    }
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
    final frames = _sampleFrames(_orderedFrames(_frames, duration));
    return frames
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

  List<_CapturedPose> _orderedFrames(
    List<_CapturedPose> frames,
    Duration duration,
  ) {
    final bounded = frames
        .where(
          (frame) => !frame.elapsed.isNegative && frame.elapsed <= duration,
        )
        .toList(growable: false);
    bounded.sort((a, b) {
      final elapsed = a.elapsed.compareTo(b.elapsed);
      return elapsed == 0 ? a.sequence.compareTo(b.sequence) : elapsed;
    });
    return List.unmodifiable(bounded);
  }

  List<_CapturedPose> _sampleFrames(List<_CapturedPose> frames) {
    if (frames.length <= maxFrameCount) return List.unmodifiable(frames);
    if (maxFrameCount <= 1) return List.unmodifiable([frames.last]);

    final sampled = <_CapturedPose>[];
    final lastIndex = frames.length - 1;
    final outputLastIndex = maxFrameCount - 1;
    var previousSourceIndex = -1;
    for (var i = 0; i < maxFrameCount; i++) {
      final sourceIndex = ((i * lastIndex) / outputLastIndex).round();
      if (sourceIndex != previousSourceIndex) {
        sampled.add(frames[sourceIndex]);
        previousSourceIndex = sourceIndex;
      }
    }
    return List.unmodifiable(sampled);
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

  bool _isStructurallyValid(List<PoseSequenceFrame> frames, Duration duration) {
    if (frames.isEmpty) return false;
    if (duration.inMilliseconds < frames.last.elapsedMs) return false;
    var previousElapsed = -1;
    var previousPosition = -1.0;
    for (final frame in frames) {
      if (!frame.pose.isValid || frame.pose.validFeatureCount == 0) {
        return false;
      }
      if (frame.elapsedMs < previousElapsed ||
          frame.position < previousPosition) {
        return false;
      }
      previousElapsed = frame.elapsedMs;
      previousPosition = frame.position;
    }
    return true;
  }
}

class _CapturedPose {
  const _CapturedPose(this.pose, this.elapsed, this.sequence);

  final NormalizedPose pose;
  final Duration elapsed;
  final int sequence;
}
