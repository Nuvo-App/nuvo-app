import 'dart:async';
import 'dart:math' as math;

import 'custom_pose_sequence_builder.dart';
import 'custom_pose_verifier_spec.dart';
import 'normalized_pose.dart';
import 'pose_calibration_models.dart';
import 'pose_calibration_quality.dart';
import 'pose_demonstration_capture.dart';
import 'pose_similarity.dart';



enum TeachMovementStage {
  name,
  setup,
  countdown,
  startPose,
  readyToRecord,
  recording,
  capturing,
  building,
  learned,
  failed,
}

class SingleSessionTeachingCapture {
  SingleSessionTeachingCapture({
    DateTime Function()? now,
    PoseSimilarity? startSimilarity,
    this._onChanged,
    CustomPoseSequenceBuilder? builder,
    this.buildDelay = const Duration(milliseconds: _buildDelayMs),
  })  : _now = now ?? DateTime.now,
        _startSimilarity = startSimilarity ??
            const PoseSimilarity(minValidFeatureRatio: 0.35),
        _builder = builder ?? const CustomPoseSequenceBuilder();

  final DateTime Function() _now;
  final PoseSimilarity _startSimilarity;
  final void Function()? _onChanged;
  final CustomPoseSequenceBuilder _builder;
  final Duration buildDelay;

  final List<PoseDemonstration> _accepted = [];
  final List<PoseDemonstration> _rejected = [];
  PoseDemonstrationCapture? _current;
  NormalizedPose? _startPose;
  String _movementName = '';
  String _message = '';
  CustomPoseBuildResult? _buildResult;
  CustomPoseVerifierSpec? _verifierSpec;
  TeachMovementStage _stage = TeachMovementStage.name;
  double? _lastSimilarity;
  String? _lastRejection;
  String? _lastBuildFailure;
  bool _bodyVisible = false;
  DateTime? _clipStartedAt;

  TeachMovementStage get stage => _stage;
  String get movementName => _movementName;
  NormalizedPose? get startPose => _startPose;
  List<PoseDemonstration> get acceptedDemonstrations =>
      List.unmodifiable(_accepted);
  List<PoseDemonstration> get rejectedDemonstrations =>
      List.unmodifiable(_rejected);
  CustomPoseBuildResult? get buildResult => _buildResult;
  CustomPoseVerifierSpec? get verifierSpec => _verifierSpec;
  String get message => _message;
  set message(String value) {
    _message = value;
    _notify();
  }

  String get debugBodyInfo => _debugBodyInfo;

  int get acceptedCount => _accepted.length;
  int get savedExampleCount => _accepted.length;
  int get requiredExampleCount => _minAccepted;
  int get maxExampleCount => _maxAccepted;
  bool get isRecording => _stage == TeachMovementStage.recording;
  bool get isReadyToRecord => _stage == TeachMovementStage.readyToRecord;
  bool get isBuilding => _stage == TeachMovementStage.building;
  bool get isLearned => _stage == TeachMovementStage.learned;
  Duration get clipDuration => _clipDuration;
  double get recordingProgress {
    if (_clipStartedAt == null) return 0.0;
    final elapsed =
        _now().difference(_clipStartedAt!).inMilliseconds;
    return (elapsed / _clipDuration.inMilliseconds).clamp(0.0, 1.0);
  }
  bool get bodyVisible => _bodyVisible;
  bool get canLearn =>
      _accepted.length >= _minAccepted && _stage != TeachMovementStage.building;
  bool get canRecordNextExample =>
      _stage == TeachMovementStage.readyToRecord &&
      _accepted.length < _maxAccepted;
  bool get canRecordExtraExample =>
      _accepted.length >= _minAccepted &&
      _accepted.length < _maxAccepted &&
      _stage == TeachMovementStage.readyToRecord;
  bool get lastExampleRejected =>
      _lastRejection != null && _stage == TeachMovementStage.readyToRecord;
  bool get hasBuildFailure =>
      _lastBuildFailure != null && _stage == TeachMovementStage.readyToRecord;
  double? get lastSimilarity => _lastSimilarity;
  String? get lastRejection => _lastRejection;
  String? get lastBuildFailure => _lastBuildFailure;
  String? get lastBuildFailureMessage =>
      _lastBuildFailure == null ? null : _translatedFailure(_lastBuildFailure);

  static const _minAccepted = 3;
  static const _maxAccepted = 3;
  static const _buildDelayMs = 600;
  static const _staticSimilarityThreshold = 0.95;
  static const _bodyHysteresisFrames = 2;
  static const _clipDuration = Duration(seconds: 2);

  bool isBodyVisiblePose(NormalizedPose pose) => _isBodyVisible(pose);

  String _bodyGateReason = '';
  int _consecutiveVisible = 0;
  int _consecutiveInvisible = 0;
  String _debugBodyInfo = '';

  bool _isBodyVisible(NormalizedPose pose, {StringBuffer? reason}) {
    if (!pose.isValid) {
      reason?.write(pose.invalidReason ?? 'pose invalid');
      return false;
    }
    if (pose.validLandmarkCount < 3) {
      reason?.write('need at least 3 landmarks');
      return false;
    }
    return true;
  }

  bool _hasLandmark(NormalizedPose pose, String id) =>
      pose.landmarks[id]?.valid ?? false;

  void _updateBodyVisibility(NormalizedPose pose, bool rawVisible, String reason) {
    _bodyGateReason = reason;

    if (rawVisible) {
      _consecutiveVisible++;
      _consecutiveInvisible = 0;
    } else {
      _consecutiveInvisible++;
      _consecutiveVisible = 0;
    }

    if (_bodyVisible) {
      if (_consecutiveInvisible >= _bodyHysteresisFrames) {
        _bodyVisible = false;
      }
    } else {
      if (_consecutiveVisible >= _bodyHysteresisFrames) {
        _bodyVisible = true;
      }
    }

    final coverage = pose.features.values.isEmpty
        ? 0.0
        : pose.validFeatureCount / pose.features.values.length;
    _debugBodyInfo =
        'valid: ${pose.validLandmarkCount} | '
        'coverage: ${coverage.toStringAsFixed(2)} | '
        'shoulders: ${(_hasLandmark(pose, 'leftShoulder') && _hasLandmark(pose, 'rightShoulder'))} | '
        'elbows: ${(_hasLandmark(pose, 'leftElbow') && _hasLandmark(pose, 'rightElbow'))} | '
        'wrists: ${(_hasLandmark(pose, 'leftWrist') && _hasLandmark(pose, 'rightWrist'))} | '
        'hips: ${(_hasLandmark(pose, 'leftHip') && _hasLandmark(pose, 'rightHip'))} | '
        'knees: ${(_hasLandmark(pose, 'leftKnee') && _hasLandmark(pose, 'rightKnee'))} | '
        'ankles: ${(_hasLandmark(pose, 'leftAnkle') && _hasLandmark(pose, 'rightAnkle'))} | '
        'gate: $_bodyVisible (raw $rawVisible) | '
        'reason: $_bodyGateReason';
  }

  String _recordingLostMessage() => 'Nuvo is watching';

  String? setMovementName(String value) {
    final error = validateMovementName(value);
    if (error != null) return error;
    _movementName = value.trim();
    _beginReadyToRecord();
    return null;
  }

  void _beginReadyToRecord() {
    _stage = TeachMovementStage.readyToRecord;
    _message = _exampleInstruction(0);
    _notify();
  }

  void addFrame(NormalizedPose pose, DateTime now) {
    final reason = StringBuffer();
    final rawVisible = _isBodyVisible(pose, reason: reason);
    _updateBodyVisibility(pose, rawVisible, reason.toString());

    if (_stage == TeachMovementStage.readyToRecord) {
      _message = _exampleInstruction(_accepted.length);
      _notify();
      return;
    }

    if (_stage == TeachMovementStage.recording) {
      _current?.addFrame(pose, now);
      if (pose.isValid) {
        _startPose ??= pose;
      }
      if (pose.isValid && _startPose != null) {
        final result = _startSimilarity.compare(_startPose!, pose);
        _lastSimilarity = result.isValid ? result.similarity : 0.0;
      }
      _notify();
      return;
    }
  }

  void startRecordingExample() {
    if (_stage != TeachMovementStage.readyToRecord) {
      return;
    }
    _clipStartedAt = _now();
    final index = _accepted.length + _rejected.length + 1;
    _current = PoseDemonstrationCapture(
      index: index,
      minDuration: const Duration(milliseconds: 200),
      minProcessedFrames: 4,
      minValidFrameRatio: 0.30,
      maxDuration: const Duration(seconds: 8),
    )..start(_clipStartedAt!);
    _stage = TeachMovementStage.recording;
    _message = 'Nuvo is watching';
    _notify();
  }

  void stopRecordingExample() => stopRecordingExampleAt(_now());

  void cancelRecordingExample() {
    if (_stage != TeachMovementStage.recording) return;
    _clipStartedAt = null;
    _current = null;
    _lastRejection = null;
    _stage = TeachMovementStage.readyToRecord;
    _message = _exampleInstruction(_accepted.length);
    _notify();
  }

  void stopRecordingExampleAt(DateTime at) {
    if (_stage != TeachMovementStage.recording || _current == null) return;
    _clipStartedAt = null;
    final demo = _current!.finish(at);
    _current = null;
    _stage = TeachMovementStage.readyToRecord;

    if (!demo.accepted) {
      _rejected.add(demo);
      _lastRejection = demo.rejectionReason;
      _message = _translatedRejection(demo.rejectionReason);
      _notify();
      return;
    }

    if (_isTooStatic(demo)) {
      _rejected.add(_rejectedDemo(demo, 'static_capture'));
      _lastRejection = 'static_capture';
      _message = _translatedRejection('static_capture');
      _notify();
      return;
    }

    _accepted.add(demo);
    _lastRejection = null;
    _lastBuildFailure = null;
    _message = _exampleInstruction(_accepted.length);
    _notify();
  }

  void buildWhenReady() {
    if (_accepted.length < _minAccepted) return;
    _stage = TeachMovementStage.building;
    _lastRejection = null;
    _lastBuildFailure = null;
    _message = 'Learning your movement…';
    _notify();
    if (buildDelay == Duration.zero) {
      _runBuild();
    } else {
      Timer(buildDelay, _runBuild);
    }
  }

  void _runBuild() {
    _tryBuild();
    if (_buildResult?.succeeded == true) {
      _verifierSpec = _buildResult!.spec;
      _stage = TeachMovementStage.learned;
      _message = 'Movement learned.';
    } else {
      _lastBuildFailure = _buildResult?.failureReason;
      _stage = _accepted.length >= _maxAccepted
          ? TeachMovementStage.failed
          : TeachMovementStage.readyToRecord;
      _message = _translatedFailure(_buildResult?.failureReason);
    }
    _notify();
  }

  void _tryBuild() {
    if (_startPose == null || _accepted.length < _minAccepted) return;
    final calibration = CustomPoseCalibration(
      schemaVersion: poseCalibrationSchemaVersion,
      movementName: _movementName,
      startPose: _startPose!,
      demonstrations: _accepted,
      quality: evaluateCalibrationQuality(
        startPose: _startPose!,
        startPoseStability: 1,
        demonstrations: _accepted,
        requiredDemonstrations: _accepted.length,
      ),
      metadata: CalibrationCaptureMetadata(
        capturedAtIso8601: _now().toUtc().toIso8601String(),
        cameraLensDirection: 'back',
        orientation: 'portraitUp',
        normalizerVersion: 'stage2-v1',
        deviceNote: 'manual_recording',
      ),
    );
    _buildResult = _builder.build(calibration);
  }

  bool _isTooStatic(PoseDemonstration demo) {
    final start = _startPose;
    if (start == null || demo.frames.length < 3) return true;
    final similarity = const PoseSimilarity(minValidFeatureRatio: 0.35);
    var minSimilarity = 1.0;
    for (final frame in demo.frames) {
      final result = similarity.compare(start, frame.pose);
      if (!result.isValid) continue;
      minSimilarity = math.min(minSimilarity, result.similarity);
    }
    return minSimilarity > _staticSimilarityThreshold;
  }

  PoseDemonstration _rejectedDemo(PoseDemonstration demo, String reason) {
    return PoseDemonstration(
      index: demo.index,
      frames: const [],
      durationMs: demo.durationMs,
      processedFrameCount: demo.processedFrameCount,
      validFrameCount: demo.validFrameCount,
      validFrameRatio: demo.validFrameRatio,
      averageVisibility: demo.averageVisibility,
      accepted: false,
      rejectionReason: reason,
    );
  }

  String _exampleInstruction(int savedCount) {
    return switch (savedCount) {
      0 => 'Record the movement',
      1 => 'Do one more',
      2 => 'Do one more',
      _ => 'Learn movement',
    };
  }

  String _translatedRejection(String? reason) {
    if (reason == null) return 'That one was too hard to read. Record it again.';
    if (reason == 'too_short' || reason.endsWith('too_short_after_trimming')) {
      return 'That one was too short. Record it again.';
    }
    if (reason == 'too_long') return 'That one was too long. Keep it under 8 seconds.';
    if (reason == 'too_few_processed_frames') {
      return 'That one was too short. Record it again.';
    }
    if (reason == 'static_capture') {
      return 'That one was too still. Record it again.';
    }
    if (reason == 'low_valid_frame_ratio' ||
        reason.endsWith('low_feature_coverage') ||
        reason == 'low_shared_feature_coverage') {
      return 'That one was too hard to read. Record it again.';
    }
    if (reason == 'capture_interrupted') {
      return 'That one was too hard to read. Record it again.';
    }
    return 'That one was too hard to read. Record it again.';
  }

  String _translatedFailure(String? reason) {
    if (reason != null && reason.contains('static_capture')) {
      return 'That one was too still. Record it again.';
    }
    return switch (reason) {
      'no_active_features' => 'That one was too hard to read. Record it again.',
      'inconsistent_demonstrations' =>
          'Those didn\'t match. Record the same movement each time.',
      'low_overall_consistency' =>
          'Those didn\'t match. Record the same movement each time.',
      'ambiguous_completion_strategy' =>
          'End each example in the same position.',
      'low_shared_feature_coverage' || 'low_feature_coverage' =>
          'That one was too hard to read. Record it again.',
      _ => 'That one was too hard to read. Record it again.',
    };
  }

  void removeLastAccepted() {
    if (_accepted.isNotEmpty) _accepted.removeLast();
    _buildResult = null;
    _verifierSpec = null;
    _lastBuildFailure = null;
    _lastRejection = null;
    _stage = TeachMovementStage.readyToRecord;
    _message = _exampleInstruction(_accepted.length);
    _notify();
  }

  void clearExamples() {
    _accepted.clear();
    _rejected.clear();
    _current = null;
    _buildResult = null;
    _verifierSpec = null;
    _lastRejection = null;
    _lastBuildFailure = null;
    _lastSimilarity = null;
    _stage = TeachMovementStage.readyToRecord;
    _message = _exampleInstruction(0);
    _notify();
  }

  void resetStartPose() {
    _startPose = null;
    _accepted.clear();
    _rejected.clear();
    _current = null;
    _buildResult = null;
    _verifierSpec = null;
    _lastRejection = null;
    _lastBuildFailure = null;
    _lastSimilarity = null;
    _beginReadyToRecord();
  }

  void restart() {
    _accepted.clear();
    _rejected.clear();
    _current = null;
    _buildResult = null;
    _verifierSpec = null;
    _lastRejection = null;
    _lastBuildFailure = null;
    _lastSimilarity = null;
    _bodyVisible = false;
    _consecutiveVisible = 0;
    _consecutiveInvisible = 0;
    _stage = TeachMovementStage.readyToRecord;
    _message = _exampleInstruction(0);
    _notify();
  }

  void resetToName() {
    _movementName = '';
    _startPose = null;
    _accepted.clear();
    _rejected.clear();
    _current = null;
    _buildResult = null;
    _verifierSpec = null;
    _lastRejection = null;
    _lastBuildFailure = null;
    _lastSimilarity = null;
    _bodyVisible = false;
    _consecutiveVisible = 0;
    _consecutiveInvisible = 0;
    _stage = TeachMovementStage.name;
    _message = '';
    _notify();
  }

  void resetToCapture() => restart();

  void markInterrupted() {
    _clipStartedAt = null;
    _current?.interrupt();
    _current = null;
    if (_stage == TeachMovementStage.recording) {
      _stage = TeachMovementStage.readyToRecord;
      _message = 'Recording stopped. Try again.';
      _notify();
    }
  }

  /// Called when no pose frame arrives (camera lost, pose detector returns
  /// null, etc.) so stale body-visible state is not shown to the user.
  void markFrameMissing() {
    _bodyVisible = false;
    _consecutiveVisible = 0;
    _consecutiveInvisible = 0;
    _bodyGateReason = 'no frame';
    _lastSimilarity = null;
    _debugBodyInfo = 'gate: false (no frame)';
    if (_stage == TeachMovementStage.readyToRecord) {
      _message = _exampleInstruction(_accepted.length);
    } else if (_stage == TeachMovementStage.recording) {
      _message = _recordingLostMessage();
    }
    _notify();
  }

  void _notify() {
    _onChanged?.call();
  }
}
