import 'dart:async';
import 'dart:math' as math;

import 'custom_pose_sequence_builder.dart';
import 'custom_pose_verifier_spec.dart';
import 'normalized_pose.dart';
import 'pose_calibration_models.dart';
import 'pose_calibration_quality.dart';
import 'pose_demonstration_capture.dart';
import 'pose_similarity.dart';

import 'stable_pose_capture.dart';

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

  final _stableCapture = StablePoseCapture();
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
      _startPose != null &&
      _bodyVisible;
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

  static const _minAccepted = 2;
  static const _maxAccepted = 3;
  static const _buildDelayMs = 600;
  static const _staticSimilarityThreshold = 0.98;
  static const _minVisibleLandmarks = 10;
  static const _minFeatureCoverage = 0.45;
  static const _clipDuration = Duration(seconds: 2);

  bool isBodyVisiblePose(NormalizedPose pose) => _isBodyVisible(pose);

  bool _isBodyVisible(NormalizedPose pose) {
    if (!pose.isValid) return false;
    if (pose.validLandmarkCount < _minVisibleLandmarks) return false;
    if (pose.features.values.isEmpty) return false;
    return pose.validFeatureCount / pose.features.values.length >=
        _minFeatureCoverage;
  }

  bool _isBodyPrompt(String value) {
    return value == _bodyPromptMessage() ||
        value == 'Nuvo lost track. Hold still where Nuvo can see you.' ||
        value == 'Step back so your full body is visible.';
  }

  String _bodyPromptMessage() =>
      'Nuvo needs to see your body. Step into frame.';

  String? setMovementName(String value) {
    final error = validateMovementName(value);
    if (error != null) return error;
    _movementName = value.trim();
    _startPoseCapture();
    return null;
  }

  void _startPoseCapture() {
    _stage = TeachMovementStage.startPose;
    _stableCapture.reset();
    _message = 'Hold still in your starting position.';
    _notify();
  }

  void _beginReadyToRecord() {
    _stage = TeachMovementStage.readyToRecord;
    _message = _exampleInstruction(0);
    _notify();
  }

  void addFrame(NormalizedPose pose, DateTime now) {
    final visible = _isBodyVisible(pose);
    _bodyVisible = visible;

    if (_stage == TeachMovementStage.startPose) {
      _addStartPoseFrame(pose, now);
      return;
    }

    if (_stage == TeachMovementStage.readyToRecord) {
      _updateReadyMessage();
      _notify();
      return;
    }

    if (_stage == TeachMovementStage.recording) {
      if (visible) {
        _current?.addFrame(pose, now);
        if (_startPose != null) {
          final result = _startSimilarity.compare(_startPose!, pose);
          _lastSimilarity = result.isValid ? result.similarity : 0.0;
        }
        if (_message == 'Nuvo lost track. Hold still where Nuvo can see you.') {
          _message = 'Recording…';
        }
      } else {
        _message = 'Nuvo lost track. Hold still where Nuvo can see you.';
      }
      _notify();
      return;
    }
  }

  void _updateReadyMessage() {
    if (_bodyVisible) {
      if (_isBodyPrompt(_message)) {
        _message = _exampleInstruction(_accepted.length);
      }
    } else {
      _message = _bodyPromptMessage();
    }
  }

  void _addStartPoseFrame(NormalizedPose pose, DateTime now) {
    final update = _stableCapture.addFrame(pose, now);
    if (update.captured && update.pose != null) {
      _startPose = update.pose;
      _beginReadyToRecord();
    } else {
      _message = update.message;
      _notify();
    }
  }

  void startRecordingExample() {
    if (_stage != TeachMovementStage.readyToRecord ||
        _startPose == null ||
        !_bodyVisible) {
      return;
    }
    _clipStartedAt = _now();
    final index = _accepted.length + _rejected.length + 1;
    _current = PoseDemonstrationCapture(
      index: index,
      minDuration: const Duration(milliseconds: 250),
      minProcessedFrames: 4,
      maxDuration: const Duration(seconds: 8),
    )..start(_clipStartedAt!);
    _stage = TeachMovementStage.recording;
    _message = 'Recording example $index…';
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
    if (start == null || demo.frames.length < 4) return true;
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
      0 => 'Record example 1',
      1 => 'Record example 2',
      _ => 'Ready to learn',
    };
  }

  String _translatedRejection(String? reason) {
    if (reason == null) return 'That one wasn\'t clear. Record it again.';
    if (reason == 'too_short' || reason.endsWith('too_short_after_trimming')) {
      return 'That one was too short. Record it again.';
    }
    if (reason == 'too_long') return 'That one was too long. Keep it under 8 seconds.';
    if (reason == 'too_few_processed_frames') {
      return 'That one was too short. Record it again.';
    }
    if (reason == 'static_capture') {
      return 'That one didn\'t show a clear movement. Record it again.';
    }
    if (reason == 'low_valid_frame_ratio' ||
        reason.endsWith('low_feature_coverage') ||
        reason == 'low_shared_feature_coverage') {
      return 'Step back so your full body is visible.';
    }
    if (reason == 'capture_interrupted') {
      return 'We didn\'t get a clear example. Try recording again.';
    }
    return 'That one wasn\'t clear. Record it again.';
  }

  String _translatedFailure(String? reason) {
    if (reason != null && reason.contains('static_capture')) {
      return 'That didn\'t show a clear movement. Record it again.';
    }
    return switch (reason) {
      'no_active_features' => 'Make the movement larger and try again.',
      'inconsistent_demonstrations' => 'Repeat the same movement each time.',
      'low_overall_consistency' => 'Repeat the same movement each time.',
      'ambiguous_completion_strategy' =>
          'Do the same movement and end in the same position each time.',
      'low_shared_feature_coverage' || 'low_feature_coverage' =>
          'Step back so your full body is visible.',
      _ => 'We didn\'t get a clear example. Try again.',
    };
  }

  void removeLastAccepted() {
    if (_accepted.isNotEmpty) _accepted.removeLast();
    _buildResult = null;
    _verifierSpec = null;
    _lastBuildFailure = null;
    _lastRejection = null;
    _stage = _startPose == null
        ? TeachMovementStage.startPose
        : TeachMovementStage.readyToRecord;
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
    _stage = _startPose == null
        ? TeachMovementStage.startPose
        : TeachMovementStage.readyToRecord;
    _message = _exampleInstruction(0);
    _notify();
  }

  void resetStartPose() {
    _startPose = null;
    _stableCapture.reset();
    _accepted.clear();
    _rejected.clear();
    _current = null;
    _buildResult = null;
    _verifierSpec = null;
    _lastRejection = null;
    _lastBuildFailure = null;
    _lastSimilarity = null;
    _startPoseCapture();
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
    _stage = _startPose == null
        ? TeachMovementStage.startPose
        : TeachMovementStage.readyToRecord;
    _message = _startPose == null
        ? 'Hold still in your starting position.'
        : _exampleInstruction(0);
    _notify();
  }

  void resetToName() {
    _movementName = '';
    _startPose = null;
    _stableCapture.reset();
    _accepted.clear();
    _rejected.clear();
    _current = null;
    _buildResult = null;
    _verifierSpec = null;
    _lastRejection = null;
    _lastBuildFailure = null;
    _lastSimilarity = null;
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
    _lastSimilarity = null;
    if (_stage == TeachMovementStage.readyToRecord) {
      _message = _bodyPromptMessage();
    } else if (_stage == TeachMovementStage.recording) {
      _message = 'Nuvo lost track. Hold still where Nuvo can see you.';
    }
    _notify();
  }

  void _notify() {
    _onChanged?.call();
  }
}
