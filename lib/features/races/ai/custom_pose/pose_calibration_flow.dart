import 'normalized_pose.dart';
import 'pose_calibration_models.dart';
import 'pose_calibration_quality.dart';

enum TeachMovementStage { name, setup, startPose, demonstration, summary }

class PoseCalibrationFlow {
  PoseCalibrationFlow({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  String _movementName = '';
  NormalizedPose? _startPose;
  double _startPoseStability = 0;
  final Map<int, PoseDemonstration> _demonstrations = {};
  bool _interrupted = false;

  TeachMovementStage stage = TeachMovementStage.name;

  String get movementName => _movementName;
  NormalizedPose? get startPose => _startPose;
  List<PoseDemonstration> get demonstrations => List.unmodifiable([
    for (var i = 1; i <= 3; i++)
      if (_demonstrations[i] != null) _demonstrations[i]!,
  ]);
  int get nextDemonstrationIndex {
    for (var i = 1; i <= 3; i++) {
      if (_demonstrations[i]?.accepted != true) return i;
    }
    return 3;
  }

  String? setMovementName(String value) {
    final error = validateMovementName(value);
    if (error != null) return error;
    _movementName = value.trim();
    stage = TeachMovementStage.setup;
    return null;
  }

  void beginStartPose() {
    stage = TeachMovementStage.startPose;
  }

  void setStartPose(NormalizedPose pose, {required double stability}) {
    if (!pose.isValid) {
      throw const PoseDataFormatException('Start pose must be valid.');
    }
    _startPose = pose;
    _startPoseStability = stability.clamp(0.0, 1.0);
    stage = TeachMovementStage.demonstration;
  }

  void setDemonstration(PoseDemonstration demonstration) {
    if (demonstration.index < 1 || demonstration.index > 3) {
      throw const PoseDataFormatException('Demonstration index must be 1-3.');
    }
    _demonstrations[demonstration.index] = demonstration;
    stage = _demonstrations.values.where((demo) => demo.accepted).length == 3
        ? TeachMovementStage.summary
        : TeachMovementStage.demonstration;
  }

  void retryDemonstration(int index) {
    _demonstrations.remove(index);
    stage = TeachMovementStage.demonstration;
  }

  void markInterrupted() {
    _interrupted = true;
  }

  void restart() {
    _movementName = '';
    _startPose = null;
    _startPoseStability = 0;
    _demonstrations.clear();
    _interrupted = false;
    stage = TeachMovementStage.name;
  }

  CalibrationQuality quality() => evaluateCalibrationQuality(
    startPose: _startPose,
    startPoseStability: _startPoseStability,
    demonstrations: demonstrations,
    interrupted: _interrupted,
  );

  CustomPoseCalibration? buildCalibration({
    String cameraLensDirection = 'back',
    String orientation = 'portraitUp',
    String deviceNote = 'internal_mvp',
  }) {
    final start = _startPose;
    if (start == null) return null;
    final q = quality();
    return CustomPoseCalibration(
      schemaVersion: poseCalibrationSchemaVersion,
      movementName: _movementName,
      startPose: start,
      demonstrations: demonstrations,
      quality: q,
      metadata: CalibrationCaptureMetadata(
        capturedAtIso8601: _now().toUtc().toIso8601String(),
        cameraLensDirection: cameraLensDirection,
        orientation: orientation,
        normalizerVersion: 'stage2-v1',
        deviceNote: deviceNote,
      ),
    );
  }
}
