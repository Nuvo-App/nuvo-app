import 'normalized_pose.dart';
import 'pose_calibration_quality.dart';
import 'pose_similarity.dart';

enum StablePoseCaptureStatus { collecting, captured, failed }

class StablePoseCaptureUpdate {
  const StablePoseCaptureUpdate({
    required this.status,
    required this.stableFrameCount,
    required this.elapsed,
    required this.message,
    this.pose,
    this.stability = 0,
  });

  final StablePoseCaptureStatus status;
  final int stableFrameCount;
  final Duration elapsed;
  final String message;
  final NormalizedPose? pose;
  final double stability;

  bool get captured => status == StablePoseCaptureStatus.captured;
}

class StablePoseCapture {
  StablePoseCapture({
    this.requiredStableFrames = 8,
    this.timeout = const Duration(milliseconds: 2500),
    this.minFeatureCoverage = 0.55,
    this.stabilityThreshold = 0.92,
    this._similarity = const PoseSimilarity(minValidFeatureRatio: 0.55),
    this._averager = const PoseAverager(minPoseCount: 4),
  });

  final int requiredStableFrames;
  final Duration timeout;
  final double minFeatureCoverage;
  final double stabilityThreshold;
  final PoseSimilarity _similarity;
  final PoseAverager _averager;
  final List<NormalizedPose> _stableWindow = [];
  DateTime? _startedAt;

  StablePoseCaptureUpdate addFrame(NormalizedPose pose, DateTime now) {
    _startedAt ??= now;
    final elapsed = now.difference(_startedAt!);
    if (elapsed > timeout) {
      return StablePoseCaptureUpdate(
        status: StablePoseCaptureStatus.failed,
        stableFrameCount: _stableWindow.length,
        elapsed: elapsed,
        message: 'Hold still and try again.',
      );
    }
    if (!pose.isValid || _coverage(pose) < minFeatureCoverage) {
      _stableWindow.clear();
      return StablePoseCaptureUpdate(
        status: StablePoseCaptureStatus.collecting,
        stableFrameCount: 0,
        elapsed: elapsed,
        message: 'Step back so your full body is visible.',
      );
    }
    if (_stableWindow.isNotEmpty) {
      final result = _similarity.compare(_stableWindow.last, pose);
      if (!result.isValid || result.similarity < stabilityThreshold) {
        _stableWindow
          ..clear()
          ..add(pose);
        return StablePoseCaptureUpdate(
          status: StablePoseCaptureStatus.collecting,
          stableFrameCount: _stableWindow.length,
          elapsed: elapsed,
          message: 'Hold still.',
          stability: result.similarity,
        );
      }
    } else {
      _stableWindow.add(pose);
      return StablePoseCaptureUpdate(
        status: StablePoseCaptureStatus.collecting,
        stableFrameCount: _stableWindow.length,
        elapsed: elapsed,
        message: 'Hold still.',
      );
    }
    _stableWindow.add(pose);
    if (_stableWindow.length >= requiredStableFrames) {
      final averaged = _averager.average(_stableWindow);
      return StablePoseCaptureUpdate(
        status: StablePoseCaptureStatus.captured,
        stableFrameCount: _stableWindow.length,
        elapsed: elapsed,
        message: 'Start pose captured.',
        pose: averaged,
        stability: 1,
      );
    }
    return StablePoseCaptureUpdate(
      status: StablePoseCaptureStatus.collecting,
      stableFrameCount: _stableWindow.length,
      elapsed: elapsed,
      message: 'Hold still.',
      stability: 1,
    );
  }

  void reset() {
    _startedAt = null;
    _stableWindow.clear();
  }

  double _coverage(NormalizedPose pose) {
    if (pose.features.values.isEmpty) return 0;
    return pose.validFeatureCount / pose.features.values.length;
  }
}
