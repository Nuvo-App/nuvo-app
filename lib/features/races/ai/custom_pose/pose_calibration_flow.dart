import 'dart:async';
import 'dart:math' as math;

import 'custom_pose_sequence_builder.dart';
import 'custom_pose_verifier_spec.dart';
import 'normalized_pose.dart';
import 'pose_calibration_models.dart';
import 'pose_calibration_quality.dart';
import 'pose_demonstration_capture.dart';
import 'pose_repetition_splitter.dart';
import 'pose_sequence_frame.dart';
import 'pose_similarity.dart';
import 'stable_pose_capture.dart';

enum TeachMovementStage {
  name,
  setup,
  countdown,
  startPose,
  readyToRecord,
  holdStill,
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
  }) : _now = now ?? DateTime.now,
       _startSimilarity =
           startSimilarity ?? const PoseSimilarity(minValidFeatureRatio: 0.35),
       _builder = builder ?? const CustomPoseSequenceBuilder();

  final DateTime Function() _now;
  final PoseSimilarity _startSimilarity;
  final void Function()? _onChanged;
  final CustomPoseSequenceBuilder _builder;
  final Duration buildDelay;
  final PoseRepetitionSplitter _repetitionSplitter =
      const PoseRepetitionSplitter();

  final List<PoseDemonstration> _accepted = [];
  final List<PoseDemonstration> _rejected = [];
  PoseDemonstrationCapture? _current;
  NormalizedPose? _startPose;
  final List<NormalizedPose> _startPoseSamples = [];
  bool _startPoseLocked = false;

  /// Runs in parallel with the start of example 1's recording: if the opening
  /// frames hold still, that clean pose becomes the reset/arm pose. Without it
  /// the "start pose" was the average of the first frames of recording 1 —
  /// i.e. mid-motion if the person moved immediately — and the live runtime
  /// could then never arm. (`holdStill` stage is reserved, not currently used.)
  StablePoseCapture? _startPoseCapture;
  int _holdStillFrames = 0;
  static const int _holdStillFallbackFrames = 45; // ~1.5s at ~30fps
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
  String _cameraLensDirection = 'unknown';
  String _captureOrientation = 'portraitUp';
  String _captureDeviceNote = 'manual_recording';
  bool _continuousRecording = false;
  int _detectedRepetitionCount = 0;

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
  DateTime? get clipStartedAt => _clipStartedAt;
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

  void setCaptureDeviceInfo({
    String? cameraLensDirection,
    String? orientation,
    String? deviceNote,
  }) {
    if (cameraLensDirection != null && cameraLensDirection.isNotEmpty) {
      _cameraLensDirection = cameraLensDirection;
    }
    if (orientation != null && orientation.isNotEmpty) {
      _captureOrientation = orientation;
    }
    if (deviceNote != null && deviceNote.isNotEmpty) {
      _captureDeviceNote = deviceNote;
    }
  }

  Map<String, dynamic> debugReport() {
    final buildResult = _buildResult;
    final spec = _verifierSpec ?? buildResult?.spec;
    final selected =
        buildResult?.selectedFeatureDiagnostics ??
        const <PoseFeatureSelectionDiagnostic>[];
    final requiredIds = spec?.requiredFeatureIds ?? const <String>[];
    final activeIds = spec?.activeFeatureIds ?? const <String>[];
    final startPose = _startPose;
    return {
      'movementName': _movementName,
      'stage': _stage.name,
      'cameraLensDirection': _cameraLensDirection,
      'continuousRecording': _continuousRecording,
      'detectedRepetitionCount': _detectedRepetitionCount,
      'exampleCount': _accepted.length,
      'examples': _accepted
          .map((demo) => _demonstrationReport(demo, startPose))
          .toList(),
      'rejectedExamples': _rejected
          .map((demo) => _demonstrationReport(demo, startPose))
          .toList(),
      'startPoseFeatureCount': startPose?.validFeatureCount ?? 0,
      if (startPose != null) 'startPose': _startPoseReport(startPose),
      'startPoseTopFeatures': _startPoseTopFeatures(startPose),
      'activeFeatureIds': activeIds,
      'requiredFeatureIds': requiredIds,
      'activeFeaturesByBodyPart': _groupFeatureIdsByBodyPart(activeIds),
      'topMovingFeaturesByAmplitude': selected
          .map((diagnostic) => diagnostic.toJson())
          .toList(),
      'featureCoverageAcrossExamples': {
        for (final diagnostic
            in buildResult?.featureDiagnostics ??
                const <PoseFeatureSelectionDiagnostic>[])
          diagnostic.featureId: diagnostic.coverage,
      },
      'featureConsistencyAcrossExamples': {
        for (final diagnostic
            in buildResult?.featureDiagnostics ??
                const <PoseFeatureSelectionDiagnostic>[])
          diagnostic.featureId: diagnostic.consistency,
      },
      'waveBodyPartCoverage': _waveBodyPartCoverage(activeIds, requiredIds),
      if (_accepted.length >= 2)
        'crossDemonstration': _crossDemonstrationReport(buildResult),
      if (spec != null) ...{
        'completionStrategy': spec.completionStrategy.name,
        'sequenceSimilarityThreshold': spec.sequenceSimilarityThreshold,
        'completionSimilarityThreshold': spec.completionSimilarityThreshold,
        'resetSimilarityThreshold': spec.resetSimilarityThreshold,
        'minimumValidFeatureRatio': spec.minimumValidFeatureRatio,
        'minimumVisibility': spec.minimumVisibility,
        'expectedSequenceFrameCount': spec.expectedSequenceFrameCount,
        'canonicalSequenceFrameCount': spec.canonicalSequence.length,
      },
      if (buildResult != null) 'builder': buildResult.toDiagnosticsJson(),
      if (_lastBuildFailure != null) 'lastBuildFailure': _lastBuildFailure,
      if (_lastRejection != null) 'lastRejection': _lastRejection,
    };
  }

  static const _minAccepted = 3;
  static const _maxAccepted = 3;
  static const _buildDelayMs = 600;
  static const _staticSimilarityThreshold = 0.95;
  static const _bodyHysteresisFrames = 2;
  static const _startPoseSampleCount = 4;

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

  void _updateBodyVisibility(
    NormalizedPose pose,
    bool rawVisible,
    String reason,
  ) {
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

  String _recordingMessage() => 'Recording…';

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

      // Parallel start-pose settle (example 1 only): if the opening frames of
      // the recording hold still, take that clean pose as the reset/arm pose.
      final settle = _startPoseCapture;
      if (settle != null && !_startPoseLocked) {
        _holdStillFrames++;
        if (pose.isValid) {
          final s = settle.addFrame(pose, now);
          if (s.captured && s.pose != null) {
            _startPose = s.pose;
            _startPoseSamples.clear();
            _startPoseLocked = true;
            _startPoseCapture = null;
          }
        }
        // Give up looking for a still pose after the fallback window — fall
        // through to the legacy first-frames average below.
        if (_startPoseCapture != null &&
            _holdStillFrames >= _holdStillFallbackFrames) {
          _startPoseCapture = null;
        }
      }

      if (pose.isValid && !_startPoseLocked) {
        _startPoseSamples.add(pose);
        if (_startPoseSamples.length == 1) {
          _startPose = _startPoseSamples.first;
        }
        if (_startPoseSamples.length >= _startPoseSampleCount) {
          _lockStartPoseFromSamples();
        }
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
    _continuousRecording = false;
    _clipStartedAt = _now();
    if (_startPose == null) {
      _startPoseSamples.clear();
      _startPoseLocked = false;
      _holdStillFrames = 0;
      // Recording rolls immediately (nothing is gated), but in parallel we look
      // for a *still* starting pose in the opening frames of example 1. If the
      // person held their start position even briefly, that clean pose becomes
      // the reset/arm pose the live runtime needs — instead of a mid-motion
      // frame. Leading still frames are trimmed by the builder later.
      _startPoseCapture = StablePoseCapture(
        requiredStableFrames: 4,
        timeout: const Duration(seconds: 3),
        stabilityThreshold: 0.9,
      );
    }
    final index = _accepted.length + _rejected.length + 1;
    _current = PoseDemonstrationCapture(
      index: index,
      minDuration: Duration.zero,
      minProcessedFrames: 4,
      minValidFrameRatio: 0.30,
      maxDuration: const Duration(minutes: 5),
    )..start(_clipStartedAt!);
    _stage = TeachMovementStage.recording;
    _message = _recordingMessage();
    _notify();
  }

  void stopRecordingExample() => stopRecordingExampleAt(_now());

  void cancelRecordingExample() {
    if (_stage != TeachMovementStage.recording &&
        _stage != TeachMovementStage.holdStill) {
      return;
    }
    _clipStartedAt = null;
    _current = null;
    _startPoseCapture = null;
    _holdStillFrames = 0;
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
    if (!_startPoseLocked && _startPoseSamples.isNotEmpty) {
      _lockStartPoseFromSamples();
    }

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
    _message = 'Example ${_accepted.length} saved';
    _notify();
  }

  void startContinuousRecording() {
    if (_stage != TeachMovementStage.readyToRecord) return;
    _accepted.clear();
    _rejected.clear();
    _buildResult = null;
    _verifierSpec = null;
    _lastRejection = null;
    _lastBuildFailure = null;
    _startPose = null;
    _startPoseSamples.clear();
    _startPoseLocked = false;
    _continuousRecording = true;
    _detectedRepetitionCount = 0;
    _clipStartedAt = _now();
    _current = PoseDemonstrationCapture(
      index: 1,
      minDuration: Duration.zero,
      minProcessedFrames: 4,
      minValidFrameRatio: 0.30,
      maxDuration: const Duration(minutes: 5),
    )..start(_clipStartedAt!);
    _stage = TeachMovementStage.recording;
    _message = 'Do the movement a few times.';
    _notify();
  }

  void stopContinuousRecording() => stopContinuousRecordingAt(_now());

  void stopContinuousRecordingAt(DateTime at) {
    if (_stage != TeachMovementStage.recording || _current == null) return;
    _clipStartedAt = null;
    final demo = _current!.finish(at);
    _current = null;

    if (!_startPoseLocked && _startPoseSamples.isNotEmpty) {
      _lockStartPoseFromSamples();
    }

    if (!demo.accepted) {
      _rejected.add(demo);
      _lastRejection = demo.rejectionReason;
      _stage = TeachMovementStage.readyToRecord;
      _message = 'Show me that once more.';
      _notify();
      return;
    }

    if (_startPose == null) {
      _stage = TeachMovementStage.readyToRecord;
      _message = 'Show me that once more.';
      _notify();
      return;
    }

    final repetitions = _repetitionSplitter.split(
      frames: demo.frames,
      startPose: _startPose!,
    );
    _detectedRepetitionCount = repetitions.length;
    _accepted
      ..clear()
      ..addAll(repetitions);

    _lastRejection = null;
    _lastBuildFailure = null;
    _buildResult = null;
    _verifierSpec = null;

    if (repetitions.length < 2) {
      _stage = TeachMovementStage.readyToRecord;
      _message = 'Show me that once more.';
      _notify();
      return;
    }

    _stage = TeachMovementStage.building;
    _message = 'Learning your movement…';
    _notify();
    if (buildDelay == Duration.zero) {
      _runBuild();
    } else {
      Timer(buildDelay, _runBuild);
    }
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

  /// Reconstructs the [CustomPoseCalibration] from the current start pose +
  /// accepted demonstrations. Returns null until at least 2 demos exist.
  CustomPoseCalibration? currentCalibration() {
    if (_startPose == null || _accepted.length < 2) return null;
    return CustomPoseCalibration(
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
        cameraLensDirection: _cameraLensDirection,
        orientation: _captureOrientation,
        normalizerVersion: 'stage2-v1',
        deviceNote: _captureDeviceNote,
      ),
    );
  }

  void _tryBuild() {
    final calibration = currentCalibration();
    if (calibration == null) return;
    _buildResult = _builder.build(calibration);
  }

  void _lockStartPoseFromSamples() {
    if (_startPoseSamples.isEmpty) return;
    try {
      _startPose = const PoseAverager().average(_startPoseSamples);
    } on PoseDataFormatException {
      _startPose = _startPoseSamples.first;
    }
    _startPoseLocked = true;
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
      0 => 'Show Nuvo the movement.',
      1 => 'Do that again.',
      2 => 'One more time.',
      _ => 'Learn movement',
    };
  }

  String _translatedRejection(String? reason) {
    if (reason == null) {
      return 'Nuvo had trouble reading that one. Record it again.';
    }
    if (reason == 'too_short' || reason.endsWith('too_short_after_trimming')) {
      return 'That one was too short. Record it again.';
    }
    if (reason == 'too_few_processed_frames') {
      return 'Nuvo had trouble reading that one. Record it again.';
    }
    if (reason == 'no_pose') {
      return 'Nuvo couldn\'t read that one. Record it again.';
    }
    if (reason == 'static_capture') {
      return 'That one did not move enough. Record it again.';
    }
    if (reason == 'low_valid_frame_ratio' ||
        reason == 'low_feature_coverage' ||
        reason == 'low_shared_feature_coverage') {
      return 'Nuvo couldn\'t read that one. Record it again.';
    }
    if (reason == 'non_monotonic_frames') {
      return 'Nuvo had trouble reading that recording. Try again.';
    }
    if (reason == 'capture_interrupted') {
      return 'Nuvo lost track. Record that one again.';
    }
    return 'Nuvo had trouble reading that one. Record it again.';
  }

  String _translatedFailure(String? reason) {
    if (reason != null && reason.contains('static_capture')) {
      return 'That one did not move enough. Record it again.';
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
    if (_accepted.isNotEmpty) {
      _startPose = _accepted.first.frames.firstOrNull?.pose;
      _startPoseLocked = true;
    } else {
      _startPose = null;
      _startPoseSamples.clear();
      _startPoseLocked = false;
    }
    _buildResult = null;
    _verifierSpec = null;
    _lastBuildFailure = null;
    _lastRejection = null;
    _stage = TeachMovementStage.readyToRecord;
    _message = _exampleInstruction(_accepted.length);
    _notify();
  }

  void clearExamples() {
    _startPose = null;
    _startPoseSamples.clear();
    _startPoseLocked = false;
    _accepted.clear();
    _rejected.clear();
    _current = null;
    _buildResult = null;
    _verifierSpec = null;
    _lastRejection = null;
    _lastBuildFailure = null;
    _lastSimilarity = null;
    _continuousRecording = false;
    _detectedRepetitionCount = 0;
    _stage = TeachMovementStage.readyToRecord;
    _message = _exampleInstruction(0);
    _notify();
  }

  void resetStartPose() {
    _startPose = null;
    _startPoseSamples.clear();
    _startPoseLocked = false;
    _accepted.clear();
    _rejected.clear();
    _current = null;
    _buildResult = null;
    _verifierSpec = null;
    _lastRejection = null;
    _lastBuildFailure = null;
    _lastSimilarity = null;
    _continuousRecording = false;
    _detectedRepetitionCount = 0;
    _beginReadyToRecord();
  }

  void restart() {
    _startPose = null;
    _startPoseSamples.clear();
    _startPoseLocked = false;
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
    _continuousRecording = false;
    _detectedRepetitionCount = 0;
    _stage = TeachMovementStage.readyToRecord;
    _message = _exampleInstruction(0);
    _notify();
  }

  void resetToName() {
    _movementName = '';
    _startPose = null;
    _startPoseSamples.clear();
    _startPoseLocked = false;
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
    _continuousRecording = false;
    _detectedRepetitionCount = 0;
    _stage = TeachMovementStage.name;
    _message = '';
    _notify();
  }

  void resetToCapture() => restart();

  void markInterrupted() {
    _clipStartedAt = null;
    _current?.interrupt();
    _current = null;
    _startPoseCapture = null;
    _holdStillFrames = 0;
    if (_stage == TeachMovementStage.recording ||
        _stage == TeachMovementStage.holdStill) {
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
      _message = _recordingMessage();
    } else if (_stage == TeachMovementStage.holdStill) {
      _message = 'Hold your starting position still…';
    }
    _notify();
  }

  void _notify() {
    _onChanged?.call();
  }
}

Map<String, dynamic> _demonstrationReport(
  PoseDemonstration demo,
  NormalizedPose? startPose,
) {
  final frames = demo.frames;
  final firstFrame = frames.firstOrNull?.pose;
  final lastFrame = frames.lastOrNull?.pose;
  final similarity = const PoseSimilarity(minValidFeatureRatio: 0.30);
  double? minSimilarity;
  double? maxSimilarity;
  if (startPose != null) {
    for (final frame in frames) {
      final pose = frame.pose;
      if (!pose.isValid) continue;
      final result = similarity.compare(startPose, pose);
      if (!result.isValid) continue;
      final value = result.similarity;
      if (minSimilarity == null || value < minSimilarity) minSimilarity = value;
      if (maxSimilarity == null || value > maxSimilarity) maxSimilarity = value;
    }
  }
  return {
    'index': demo.index,
    'accepted': demo.accepted,
    'frameCount': frames.length,
    'processedFrameCount': demo.processedFrameCount,
    'validFrameCount': demo.validFrameCount,
    'validFrameRatio': _debugDouble(demo.validFrameRatio),
    'durationMs': demo.durationMs,
    'averageVisibility': _debugDouble(demo.averageVisibility),
    'firstFrameFeatureCount': firstFrame?.validFeatureCount,
    'lastFrameFeatureCount': lastFrame?.validFeatureCount,
    'minimumSimilarityToStart': minSimilarity == null
        ? null
        : _debugDouble(minSimilarity),
    'maximumSimilarityToStart': maxSimilarity == null
        ? null
        : _debugDouble(maxSimilarity),
    'frames': frames.map(_frameReport).toList(growable: false),
    'topFeatureRanges': _topFeatureRanges(frames),
    if (demo.rejectionReason != null) 'rejectionReason': demo.rejectionReason,
  };
}

Map<String, dynamic> _frameReport(PoseSequenceFrame frame) => {
  'position': _debugDouble(frame.position),
  'elapsedMs': frame.elapsedMs,
  'validLandmarkCount': frame.pose.validLandmarkCount,
  'validFeatureCount': frame.pose.validFeatureCount,
};

List<Map<String, dynamic>> _topFeatureRanges(List<PoseSequenceFrame> frames) {
  final stats = <String, _FeatureRange>{};
  final total = frames.length;
  for (final frame in frames) {
    final pose = frame.pose;
    if (!pose.isValid) continue;
    for (final entry in pose.features.values.entries) {
      final id = entry.key;
      final value = entry.value;
      if (!value.valid) continue;
      final stat = stats.putIfAbsent(id, () => _FeatureRange(id, value.kind));
      stat
        ..validFrameCount += 1
        ..minValue = stat.minValue == null
            ? value.value
            : math.min(stat.minValue!, value.value)
        ..maxValue = stat.maxValue == null
            ? value.value
            : math.max(stat.maxValue!, value.value);
    }
  }
  final list = stats.values.where((stat) => stat.validFrameCount > 0).toList();
  list.sort((a, b) {
    final rangeA = (a.maxValue! - a.minValue!).abs();
    final rangeB = (b.maxValue! - b.minValue!).abs();
    return rangeB.compareTo(rangeA);
  });
  return list
      .take(20)
      .map((stat) {
        final range = (stat.maxValue! - stat.minValue!).abs();
        return {
          'featureId': stat.featureId,
          'kind': stat.kind,
          'validFrameCount': stat.validFrameCount,
          'coverageRatio': _debugDouble(stat.validFrameCount / total),
          'minValue': _debugDouble(stat.minValue!),
          'maxValue': _debugDouble(stat.maxValue!),
          'range': _debugDouble(range),
        };
      })
      .toList(growable: false);
}

Map<String, dynamic> _startPoseReport(NormalizedPose pose) => {
  'valid': pose.isValid,
  'validLandmarkCount': pose.validLandmarkCount,
  'validFeatureCount': pose.validFeatureCount,
  'originReference': pose.originReference,
  'scaleReference': pose.scaleReference,
  'scale': _debugDouble(pose.scale),
};

List<Map<String, dynamic>> _startPoseTopFeatures(NormalizedPose? pose) {
  if (pose == null || !pose.isValid) return const [];
  final features = pose.features.values.entries
      .where((entry) => entry.value.valid)
      .toList();
  features.sort((a, b) => b.value.confidence.compareTo(a.value.confidence));
  return features
      .take(20)
      .map((entry) {
        final value = entry.value;
        return {
          'featureId': entry.key,
          'kind': value.kind,
          'value': _debugDouble(value.value),
          'confidence': _debugDouble(value.confidence),
        };
      })
      .toList(growable: false);
}

Map<String, dynamic> _crossDemonstrationReport(
  CustomPoseBuildResult? buildResult,
) {
  final consistency = buildResult?.consistency;
  final pairs = consistency?.pairwiseScores ?? const <String, double>{};
  return {
    'acceptedCount': buildResult?.succeeded == true
        ? buildResult!.featureDiagnostics.where((d) => d.selected).length
        : 0,
    if (pairs.isNotEmpty)
      'pairScores': pairs.map(
        (key, value) => MapEntry(key, _debugDouble(value)),
      ),
    'overallConsistencyScore': consistency == null
        ? null
        : _debugDouble(consistency.overallScore),
    'lowestPairScore': consistency == null
        ? null
        : _debugDouble(consistency.lowestPairScore),
    'builderAccepted': buildResult?.succeeded ?? false,
    'builderFailureReason': buildResult?.failureReason,
  };
}

class _FeatureRange {
  _FeatureRange(this.featureId, this.kind);

  final String featureId;
  final String kind;
  int validFrameCount = 0;
  double? minValue;
  double? maxValue;
}

Map<String, List<String>> _groupFeatureIdsByBodyPart(List<String> ids) {
  final groups = <String, List<String>>{
    'face/head': [],
    'left wrist': [],
    'right wrist': [],
    'left elbow': [],
    'right elbow': [],
    'shoulders': [],
    'hips': [],
    'knees': [],
    'ankles': [],
    'other': [],
  };
  for (final id in ids) {
    groups.putIfAbsent(poseFeatureBodyPart(id), () => []).add(id);
  }
  return groups.map(
    (key, value) => MapEntry(key, List.unmodifiable(value..sort())),
  );
}

Map<String, dynamic> _waveBodyPartCoverage(
  List<String> activeIds,
  List<String> requiredIds,
) {
  bool hasAny(List<String> ids, String bodyPart) =>
      ids.any((id) => poseFeatureBodyPart(id) == bodyPart);
  final requiredLower = requiredIds.join('|').toLowerCase();
  return {
    'activeLeftWrist': hasAny(activeIds, 'left wrist'),
    'activeRightWrist': hasAny(activeIds, 'right wrist'),
    'activeLeftElbow': hasAny(activeIds, 'left elbow'),
    'activeRightElbow': hasAny(activeIds, 'right elbow'),
    'activeShoulders': hasAny(activeIds, 'shoulders'),
    'requiresKnees': requiredLower.contains('knee'),
    'requiresHips': requiredLower.contains('hip'),
    'requiresAnkles': requiredLower.contains('ankle'),
  };
}

double _debugDouble(double value) {
  if (!value.isFinite) return 0;
  return double.parse(value.toStringAsFixed(4));
}
