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
  }) : _now = now ?? DateTime.now,
       _startSimilarity =
           startSimilarity ?? const PoseSimilarity(minValidFeatureRatio: 0.35),
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
  final List<NormalizedPose> _startPoseSamples = [];
  bool _startPoseLocked = false;
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
    return {
      'movementName': _movementName,
      'stage': _stage.name,
      'cameraLensDirection': _cameraLensDirection,
      'exampleCount': _accepted.length,
      'examples': _accepted.map(_demonstrationReport).toList(),
      'rejectedExamples': _rejected.map(_demonstrationReport).toList(),
      'startPoseFeatureCount': _startPose?.validFeatureCount ?? 0,
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
      if (spec != null) ...{
        'completionStrategy': spec.completionStrategy.name,
        'sequenceSimilarityThreshold': spec.sequenceSimilarityThreshold,
        'completionSimilarityThreshold': spec.completionSimilarityThreshold,
        'resetSimilarityThreshold': spec.resetSimilarityThreshold,
        'minimumValidFeatureRatio': spec.minimumValidFeatureRatio,
        'minimumVisibility': spec.minimumVisibility,
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

  String _recordingMessage() => 'Recording example ${_accepted.length + 1}';

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
    _clipStartedAt = _now();
    if (_startPose == null) {
      _startPoseSamples.clear();
      _startPoseLocked = false;
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
        cameraLensDirection: _cameraLensDirection,
        orientation: _captureOrientation,
        normalizerVersion: 'stage2-v1',
        deviceNote: _captureDeviceNote,
      ),
    );
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
      0 => 'Record example 1',
      1 => 'Record example 2',
      2 => 'Record example 3',
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
      _message = _recordingMessage();
    }
    _notify();
  }

  void _notify() {
    _onChanged?.call();
  }
}

Map<String, dynamic> _demonstrationReport(PoseDemonstration demo) => {
  'index': demo.index,
  'accepted': demo.accepted,
  'frameCount': demo.frames.length,
  'processedFrameCount': demo.processedFrameCount,
  'validFrameCount': demo.validFrameCount,
  'validFrameRatio': _debugDouble(demo.validFrameRatio),
  'durationMs': demo.durationMs,
  'averageVisibility': _debugDouble(demo.averageVisibility),
  if (demo.rejectionReason != null) 'rejectionReason': demo.rejectionReason,
};

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
