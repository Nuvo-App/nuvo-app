import 'dart:math' as math;

import '../../data/ai_motion_models.dart';
import '../motion_validators.dart';
import '../verifier_runtime.dart';
import 'custom_pose_verifier_spec.dart';
import 'normalized_pose.dart';
import 'pose_normalizer.dart';

const int customPoseRuntimeVersion = 1;
const int customPoseStableStartFrameCount = 3;
const int customPoseStableCompletionFrameCount = 2;
const int customPoseStableResetFrameCount = 2;
const int customPoseMissingFeatureGraceFrames = 3;
const int customPoseProgressTimeoutFrames = 18;
const int customPoseBackwardToleranceFrames = 1;
const int customPoseForwardLookaheadFrames = 4;
const double customPoseMinimumSequenceCoverage = 0.82;

enum CustomPoseRuntimeState {
  waitingForSetup,
  waitingForStart,
  armed,
  matchingSequence,
  completionCandidate,
  waitingForReset,
  cooldown,
  invalid,
}

class CustomPoseSequenceRuntime implements VerifierRuntime {
  CustomPoseSequenceRuntime({
    required CustomPoseVerifierSpec spec,
    this.target = 5,
    this._normalizer = const PoseNormalizer(),
  }) : _spec = spec {
    try {
      spec.validate();
      _indexedSequence = spec.canonicalSequence;
      _state = CustomPoseRuntimeState.waitingForSetup;
    } on PoseDataFormatException catch (e) {
      _state = CustomPoseRuntimeState.invalid;
      _failureReason = e.message;
      _indexedSequence = const [];
    }
  }

  final CustomPoseVerifierSpec _spec;
  final PoseNormalizer _normalizer;
  final int target;
  late final List<PoseTemplateFrame> _indexedSequence;
  CustomPoseRuntimeState _state = CustomPoseRuntimeState.waitingForSetup;
  int _count = 0;
  int _framesAnalyzed = 0;
  int _validFrames = 0;
  int _invalidAttemptCount = 0;
  int _completionEvents = 0;
  int _stableStartFrames = 0;
  int _stableCompletionFrames = 0;
  int _stableResetFrames = 0;
  int _missingFeatureGraceCount = 0;
  int _framesSinceProgress = 0;
  int _cooldownFramesRemaining = 0;
  int _currentTemplateIndex = 0;
  int _highestTemplateIndex = 0;
  double _sequenceProgress = 0;
  double _currentSimilarity = 0;
  double _completionSimilarity = 0;
  double _resetSimilarity = 0;
  double _validFeatureRatio = 0;
  double _visibility = 0;
  bool _started = false;
  bool _departedAfterReturnCount = true;
  DateTime? _startedAt;
  DateTime? _lastFrameAt;
  String _guidance = 'Ready';
  String _failureReason = '';

  @override
  VerifierType get type => VerifierType.customPoseSequence;

  @override
  MovementDefinition get movement => supportedMovementDefinitions.first;

  @override
  int get targetValue => target;

  @override
  int get currentValue => _count;

  @override
  bool get fullBodyVisible => _visibility >= _spec.minimumVisibility;

  @override
  String get failedRuleReason => _failureReason;

  CustomPoseRuntimeState get state => _state;

  CustomPoseRuntimeUpdate get lastUpdate =>
      _customUpdate(completed: _count >= target);

  @override
  void start() {
    _count = 0;
    _framesAnalyzed = 0;
    _validFrames = 0;
    _invalidAttemptCount = 0;
    _completionEvents = 0;
    _stableStartFrames = 0;
    _stableCompletionFrames = 0;
    _stableResetFrames = 0;
    _missingFeatureGraceCount = 0;
    _framesSinceProgress = 0;
    _cooldownFramesRemaining = 0;
    _currentTemplateIndex = 0;
    _highestTemplateIndex = 0;
    _sequenceProgress = 0;
    _currentSimilarity = 0;
    _completionSimilarity = 0;
    _resetSimilarity = 0;
    _validFeatureRatio = 0;
    _visibility = 0;
    _started = true;
    _departedAfterReturnCount = true;
    _startedAt = null;
    _lastFrameAt = null;
    _guidance = 'Step into frame';
    _failureReason = '';
    _state = _indexedSequence.isEmpty
        ? CustomPoseRuntimeState.invalid
        : CustomPoseRuntimeState.waitingForSetup;
  }

  @override
  VerifierUpdate update(NuvoPoseFrame frame) {
    if (!_started) start();
    if (_state == CustomPoseRuntimeState.invalid) {
      _framesAnalyzed++;
      _lastFrameAt = frame.createdAt;
      return _compatUpdate();
    }
    _startedAt ??= frame.createdAt;
    _lastFrameAt = frame.createdAt;
    _framesAnalyzed++;
    if (_cooldownFramesRemaining > 0) _cooldownFramesRemaining--;

    final pose = _normalizer.normalize(frame);
    final frameQuality = _qualityFor(pose);
    _visibility = frameQuality.visibility;
    _validFeatureRatio = frameQuality.activeCoverage;
    if (!pose.isValid || !frameQuality.hasRequiredSetup) {
      _handleMissingOrInvalid(pose);
      return _compatUpdate();
    }

    _validFrames++;
    _missingFeatureGraceCount = 0;
    _resetSimilarity = _poseFeatureSimilarity(
      pose.features.values,
      _spec.startPose.features.values,
      _spec.requiredFeatureIds,
    );
    _completionSimilarity = _poseFeatureSimilarity(
      pose.features.values,
      _spec.completionPose.features.values,
      _spec.activeFeatureIds,
    );

    switch (_state) {
      case CustomPoseRuntimeState.waitingForSetup:
        _state = CustomPoseRuntimeState.waitingForStart;
        _guidance = 'Move into the starting position';
        _handleWaitingForStart();
      case CustomPoseRuntimeState.waitingForStart:
        _handleWaitingForStart();
      case CustomPoseRuntimeState.armed:
        _handleArmed(pose);
      case CustomPoseRuntimeState.matchingSequence:
      case CustomPoseRuntimeState.completionCandidate:
        _handleMatching(pose);
      case CustomPoseRuntimeState.waitingForReset:
        _handleWaitingForReset();
      case CustomPoseRuntimeState.cooldown:
        _handleCooldown(pose);
      case CustomPoseRuntimeState.invalid:
        break;
    }
    _currentSimilarity = _currentSimilarity.clamp(0.0, 1.0);
    _sequenceProgress = _sequenceProgress.clamp(0.0, 1.0);
    return _compatUpdate();
  }

  void _handleMissingOrInvalid(NormalizedPose pose) {
    _missingFeatureGraceCount++;
    _guidance = pose.isValid ? 'Step into frame' : 'Step into frame';
    if (_missingFeatureGraceCount > customPoseMissingFeatureGraceFrames) {
      _invalidateAttempt('missing_required_features');
    }
  }

  void _handleWaitingForStart() {
    if (_resetSimilarity >= _spec.resetSimilarityThreshold &&
        _validFeatureRatio >= _spec.minimumValidFeatureRatio &&
        _visibility >= _spec.minimumVisibility) {
      _stableStartFrames++;
      _guidance = _stableStartFrames >= customPoseStableStartFrameCount
          ? 'Begin the movement'
          : 'Hold the starting position';
      if (_stableStartFrames >= customPoseStableStartFrameCount) {
        _state = CustomPoseRuntimeState.armed;
        _currentTemplateIndex = 0;
        _highestTemplateIndex = 0;
        _sequenceProgress = 0;
        _framesSinceProgress = 0;
      }
    } else {
      _stableStartFrames = 0;
      _guidance = 'Move into the starting position';
    }
  }

  void _handleArmed(NormalizedPose pose) {
    final departed = _resetSimilarity < (_spec.resetSimilarityThreshold - 0.10);
    if (!departed) {
      _guidance = 'Begin the movement';
      _currentSimilarity = _matchAt(pose, 0);
      return;
    }
    if (!_departedAfterReturnCount) {
      _departedAfterReturnCount = true;
    }
    _state = CustomPoseRuntimeState.matchingSequence;
    _stableStartFrames = 0;
    _handleMatching(pose);
  }

  void _handleMatching(NormalizedPose pose) {
    final match = _bestWindowMatch(pose);
    _currentSimilarity = match.similarity;
    if (match.accepted) {
      if (match.index > _currentTemplateIndex) {
        _framesSinceProgress = 0;
      } else {
        _framesSinceProgress++;
      }
      _currentTemplateIndex = math.max(_currentTemplateIndex, match.index);
      _highestTemplateIndex = math.max(_highestTemplateIndex, match.index);
      _sequenceProgress = _highestTemplateIndex / (_indexedSequence.length - 1);
      _guidance = 'Ready';
    } else {
      _framesSinceProgress++;
      _guidance = 'Movement incomplete';
    }

    if (_framesSinceProgress > customPoseProgressTimeoutFrames) {
      _invalidateAttempt('progress_timeout');
      return;
    }

    if (_spec.completionStrategy ==
            CustomPoseCompletionStrategy.completionAfterSequenceReturn &&
        _sequenceProgress >= 0.70 &&
        _resetSimilarity >= _spec.resetSimilarityThreshold) {
      _highestTemplateIndex = _indexedSequence.length - 1;
      _currentTemplateIndex = _highestTemplateIndex;
      _sequenceProgress = 1;
    }

    final enoughProgress =
        _sequenceProgress >= customPoseMinimumSequenceCoverage;
    if (!enoughProgress) return;

    if (_spec.completionStrategy ==
        CustomPoseCompletionStrategy.completionAtTerminalPose) {
      _handleTerminalCompletion();
    } else {
      _handleReturnCompletion();
    }
  }

  void _handleTerminalCompletion() {
    if (_completionSimilarity >= _spec.completionSimilarityThreshold &&
        _cooldownFramesRemaining == 0) {
      _stableCompletionFrames++;
      _state = CustomPoseRuntimeState.completionCandidate;
      _guidance = 'Ready';
      if (_stableCompletionFrames >= customPoseStableCompletionFrameCount) {
        _countRepetition();
        _state = CustomPoseRuntimeState.waitingForReset;
        _guidance = 'Return to your starting position';
        _stableCompletionFrames = 0;
      }
    } else {
      _stableCompletionFrames = 0;
    }
  }

  void _handleReturnCompletion() {
    if (_resetSimilarity >= _spec.resetSimilarityThreshold &&
        _sequenceProgress >= 0.96 &&
        _departedAfterReturnCount &&
        _cooldownFramesRemaining == 0) {
      _stableResetFrames++;
      _guidance = 'Ready';
      if (_stableResetFrames >= customPoseStableResetFrameCount) {
        _countRepetition();
        _state = CustomPoseRuntimeState.cooldown;
        _departedAfterReturnCount = false;
        _stableResetFrames = 0;
      }
    } else {
      _stableResetFrames = 0;
      _guidance = 'Return to your starting position';
    }
  }

  void _handleWaitingForReset() {
    if (_resetSimilarity >= _spec.resetSimilarityThreshold &&
        _cooldownFramesRemaining == 0) {
      _stableResetFrames++;
      _guidance = _stableResetFrames >= customPoseStableResetFrameCount
          ? 'Begin the movement'
          : 'Hold the starting position';
      if (_stableResetFrames >= customPoseStableResetFrameCount) {
        _state = CustomPoseRuntimeState.armed;
        _resetAttemptProgress();
        _stableResetFrames = 0;
      }
    } else {
      _stableResetFrames = 0;
      _guidance = 'Return to your starting position';
    }
  }

  void _handleCooldown(NormalizedPose pose) {
    final departed = _resetSimilarity < (_spec.resetSimilarityThreshold - 0.10);
    if (_cooldownFramesRemaining > 0) {
      _guidance = 'Ready';
      return;
    }
    if (!_departedAfterReturnCount && departed) {
      _departedAfterReturnCount = true;
      _state = CustomPoseRuntimeState.matchingSequence;
      _resetAttemptProgress();
      _handleMatching(pose);
      return;
    }
    if (_departedAfterReturnCount) {
      _state = CustomPoseRuntimeState.armed;
    }
    _guidance = 'Begin the movement';
  }

  _WindowMatch _bestWindowMatch(NormalizedPose pose) {
    final start = math.max(
      0,
      _currentTemplateIndex - customPoseBackwardToleranceFrames,
    );
    final end = math.min(
      _indexedSequence.length - 1,
      _currentTemplateIndex + customPoseForwardLookaheadFrames,
    );
    var best = _WindowMatch(index: _currentTemplateIndex, similarity: 0);
    _WindowMatch? bestAcceptedForward;
    final threshold = math.min(_spec.sequenceSimilarityThreshold, 0.74);
    for (var index = start; index <= end; index++) {
      final similarity = _matchAt(pose, index);
      if (similarity > best.similarity) {
        best = _WindowMatch(index: index, similarity: similarity);
      }
      if (index > _currentTemplateIndex && similarity >= threshold) {
        if (bestAcceptedForward == null ||
            index > bestAcceptedForward.index ||
            similarity > bestAcceptedForward.similarity) {
          bestAcceptedForward = _WindowMatch(
            index: index,
            similarity: similarity,
          );
        }
      }
    }
    if (bestAcceptedForward != null) {
      return bestAcceptedForward.copyWith(accepted: true);
    }
    final accepted =
        best.similarity >= threshold &&
        best.index >= _currentTemplateIndex - customPoseBackwardToleranceFrames;
    return best.copyWith(accepted: accepted);
  }

  double _matchAt(NormalizedPose pose, int templateIndex) {
    final frame = _indexedSequence[templateIndex];
    return _templateFeatureSimilarity(pose.features.values, frame.features);
  }

  double _templateFeatureSimilarity(
    Map<String, PoseFeatureValue> observed,
    Map<String, PoseTemplateFeature> template,
  ) {
    var weighted = 0.0;
    var weightTotal = 0.0;
    var compared = 0;
    for (final id in _spec.activeFeatureIds) {
      final left = observed[id];
      final right = template[id];
      if (left == null ||
          right == null ||
          !left.valid ||
          !left.value.isFinite ||
          !right.value.isFinite) {
        continue;
      }
      compared++;
      final tolerance = math.max(
        _toleranceFor(right.kind),
        right.allowedVariation,
      );
      final contribution = (1 - (left.value - right.value).abs() / tolerance)
          .clamp(0.0, 1.0);
      final weight = math
          .min(left.confidence, math.min(right.confidence, right.reliability))
          .clamp(0.0, 1.0);
      weighted += contribution * weight;
      weightTotal += weight;
    }
    final ratio = compared / math.max(1, _spec.activeFeatureIds.length);
    if (ratio < _spec.minimumValidFeatureRatio || weightTotal <= 0) return 0;
    return (weighted / weightTotal).clamp(0.0, 1.0);
  }

  double _poseFeatureSimilarity(
    Map<String, PoseFeatureValue> observed,
    Map<String, PoseFeatureValue> reference,
    List<String> featureIds,
  ) {
    var weighted = 0.0;
    var weightTotal = 0.0;
    var compared = 0;
    for (final id in featureIds) {
      final left = observed[id];
      final right = reference[id];
      if (left == null ||
          right == null ||
          !left.valid ||
          !right.valid ||
          !left.value.isFinite ||
          !right.value.isFinite) {
        continue;
      }
      compared++;
      final contribution =
          (1 - (left.value - right.value).abs() / _toleranceFor(right.kind))
              .clamp(0.0, 1.0);
      final weight = math
          .min(left.confidence, right.confidence)
          .clamp(0.0, 1.0);
      weighted += contribution * weight;
      weightTotal += weight;
    }
    final ratio = compared / math.max(1, featureIds.length);
    if (ratio < _spec.minimumValidFeatureRatio || weightTotal <= 0) return 0;
    return (weighted / weightTotal).clamp(0.0, 1.0);
  }

  _FrameQuality _qualityFor(NormalizedPose pose) {
    if (!pose.isValid) return const _FrameQuality.empty();
    final requiredCoverage = _coverage(
      pose.features.values,
      _spec.requiredFeatureIds,
    );
    final activeCoverage = _coverage(
      pose.features.values,
      _spec.activeFeatureIds,
    );
    final confidences = _spec.requiredFeatureIds
        .map((id) => pose.features.values[id])
        .whereType<PoseFeatureValue>()
        .where((feature) => feature.valid)
        .map((feature) => feature.confidence)
        .toList(growable: false);
    final visibility = confidences.isEmpty
        ? 0.0
        : confidences.fold<double>(0, (sum, value) => sum + value) /
              confidences.length;
    return _FrameQuality(
      requiredCoverage: requiredCoverage,
      activeCoverage: activeCoverage,
      visibility: visibility.clamp(0.0, 1.0),
    );
  }

  double _coverage(Map<String, PoseFeatureValue> values, List<String> ids) {
    if (ids.isEmpty) return 0;
    final present = ids
        .where((id) => values[id]?.valid == true && values[id]!.value.isFinite)
        .length;
    return present / ids.length;
  }

  void _countRepetition() {
    _count++;
    _completionEvents++;
    _cooldownFramesRemaining = _cooldownFramesForSpec();
    _resetAttemptProgress();
    _guidance = _count >= target ? 'Ready' : 'Return to your starting position';
  }

  int _cooldownFramesForSpec() {
    return math.max(1, (_spec.cooldownMs / 120).ceil());
  }

  void _invalidateAttempt(String reason) {
    _invalidAttemptCount++;
    _failureReason = reason;
    _state = CustomPoseRuntimeState.waitingForStart;
    _resetAttemptProgress();
    _stableStartFrames = 0;
    _stableCompletionFrames = 0;
    _stableResetFrames = 0;
    _guidance = 'Move into the starting position';
  }

  void _resetAttemptProgress() {
    _currentTemplateIndex = 0;
    _highestTemplateIndex = 0;
    _sequenceProgress = 0;
    _currentSimilarity = 0;
    _completionSimilarity = 0;
    _framesSinceProgress = 0;
  }

  double _confidence() {
    final validRatio = _framesAnalyzed == 0
        ? 0.0
        : _validFrames / _framesAnalyzed;
    final targetRatio = (_count / math.max(1, target)).clamp(0.0, 1.0);
    final value =
        targetRatio * 0.45 +
        _sequenceProgress * 0.20 +
        _currentSimilarity * 0.15 +
        _validFeatureRatio * 0.10 +
        validRatio * 0.10;
    return value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
  }

  double _toleranceFor(String kind) {
    return switch (kind) {
      'coord' => 0.55,
      'angle' => 0.34,
      'distance' => 0.65,
      _ => 0.55,
    };
  }

  VerifierUpdate _compatUpdate() {
    final update = _customUpdate(completed: _count >= target);
    return VerifierUpdate(
      type: VerifierType.customPoseSequence,
      selectedMovement: supportedMovementDefinitions.first,
      count: update.count,
      holdSeconds: 0,
      target: target,
      confidence: update.confidence,
      completed: update.completed,
      debugValues: update.debugValues,
      validatorState: update.state.name,
      failedRuleReason: update.failureReason ?? '',
      customPoseUpdate: update,
    );
  }

  CustomPoseRuntimeUpdate _customUpdate({required bool completed}) {
    return CustomPoseRuntimeUpdate(
      state: _state,
      count: _count,
      target: target,
      completed: completed,
      sequenceProgress: _sequenceProgress,
      currentTemplateIndex: _currentTemplateIndex,
      currentSimilarity: _currentSimilarity,
      completionSimilarity: _completionSimilarity,
      resetSimilarity: _resetSimilarity,
      validFeatureRatio: _validFeatureRatio,
      visibility: _visibility,
      framesAnalyzed: _framesAnalyzed,
      validFrames: _validFrames,
      missingFeatureGraceCount: _missingFeatureGraceCount,
      framesSinceProgress: _framesSinceProgress,
      guidance: _guidance,
      failureReason: _failureReason.isEmpty ? null : _failureReason,
      confidence: _confidence(),
    );
  }

  @override
  VerifierResult finish() {
    final result = customResult();
    return VerifierResult(
      type: VerifierType.customPoseSequence,
      customPoseResult: result,
    );
  }

  CustomPoseRuntimeResult customResult() {
    final duration = _startedAt == null || _lastFrameAt == null
        ? Duration.zero
        : _lastFrameAt!.difference(_startedAt!);
    final complete =
        _count >= target &&
        _state != CustomPoseRuntimeState.invalid &&
        _validFeatureRatio >= _spec.minimumValidFeatureRatio;
    final failure = complete
        ? null
        : (_state == CustomPoseRuntimeState.invalid
              ? _failureReason
              : _count < target
              ? 'target_not_met'
              : _failureReason.isEmpty
              ? null
              : _failureReason);
    return CustomPoseRuntimeResult(
      verifierType: customPoseVerifierType,
      verifierVersion: customPoseRuntimeVersion,
      movementName: _spec.movementName,
      measurementType: _spec.measurementType,
      count: _count,
      target: target,
      verificationStatus: complete ? 'custom_verified' : 'custom_failed',
      confidence: _confidence(),
      framesAnalyzed: _framesAnalyzed,
      validFrames: _validFrames,
      durationMs: math.max(0, duration.inMilliseconds),
      completionEvents: _completionEvents,
      invalidAttemptCount: _invalidAttemptCount,
      finalFailureReason: failure,
    );
  }

  @override
  void dispose() {}
}

class CustomPoseRuntimeUpdate {
  const CustomPoseRuntimeUpdate({
    required this.state,
    required this.count,
    required this.target,
    required this.completed,
    required this.sequenceProgress,
    required this.currentTemplateIndex,
    required this.currentSimilarity,
    required this.completionSimilarity,
    required this.resetSimilarity,
    required this.validFeatureRatio,
    required this.visibility,
    required this.framesAnalyzed,
    required this.validFrames,
    required this.missingFeatureGraceCount,
    required this.framesSinceProgress,
    required this.guidance,
    required this.failureReason,
    required this.confidence,
  });

  final CustomPoseRuntimeState state;
  final int count;
  final int target;
  final bool completed;
  final double sequenceProgress;
  final int currentTemplateIndex;
  final double currentSimilarity;
  final double completionSimilarity;
  final double resetSimilarity;
  final double validFeatureRatio;
  final double visibility;
  final int framesAnalyzed;
  final int validFrames;
  final int missingFeatureGraceCount;
  final int framesSinceProgress;
  final String guidance;
  final String? failureReason;
  final double confidence;

  Map<String, double> get debugValues => {
    'sequenceProgress': sequenceProgress,
    'currentTemplateIndex': currentTemplateIndex.toDouble(),
    'currentSimilarity': currentSimilarity,
    'completionSimilarity': completionSimilarity,
    'resetSimilarity': resetSimilarity,
    'validFeatureRatio': validFeatureRatio,
    'visibility': visibility,
    'missingFeatureGraceCount': missingFeatureGraceCount.toDouble(),
    'framesSinceProgress': framesSinceProgress.toDouble(),
  };
}

class CustomPoseRuntimeResult {
  const CustomPoseRuntimeResult({
    required this.verifierType,
    required this.verifierVersion,
    required this.movementName,
    required this.measurementType,
    required this.count,
    required this.target,
    required this.verificationStatus,
    required this.confidence,
    required this.framesAnalyzed,
    required this.validFrames,
    required this.durationMs,
    required this.completionEvents,
    required this.invalidAttemptCount,
    required this.finalFailureReason,
  });

  factory CustomPoseRuntimeResult.fromJson(Map<String, dynamic> json) {
    return CustomPoseRuntimeResult(
      verifierType: _string(json['verifierType'], 'verifierType'),
      verifierVersion: _int(json['verifierVersion'], 'verifierVersion'),
      movementName: _string(json['movementName'], 'movementName'),
      measurementType: _string(json['measurementType'], 'measurementType'),
      count: _int(json['count'], 'count'),
      target: _int(json['target'], 'target'),
      verificationStatus: _string(
        json['verificationStatus'],
        'verificationStatus',
      ),
      confidence: _ratio(json['confidence'], 'confidence'),
      framesAnalyzed: _int(json['framesAnalyzed'], 'framesAnalyzed'),
      validFrames: _int(json['validFrames'], 'validFrames'),
      durationMs: _int(json['durationMs'], 'durationMs'),
      completionEvents: _int(json['completionEvents'], 'completionEvents'),
      invalidAttemptCount: _int(
        json['invalidAttemptCount'],
        'invalidAttemptCount',
      ),
      finalFailureReason: json['finalFailureReason'] == null
          ? null
          : _string(json['finalFailureReason'], 'finalFailureReason'),
    );
  }

  final String verifierType;
  final int verifierVersion;
  final String movementName;
  final String measurementType;
  final int count;
  final int target;
  final String verificationStatus;
  final double confidence;
  final int framesAnalyzed;
  final int validFrames;
  final int durationMs;
  final int completionEvents;
  final int invalidAttemptCount;
  final String? finalFailureReason;

  bool get isVerified => verificationStatus == 'custom_verified';

  Map<String, dynamic> toJson() => {
    'verifierType': verifierType,
    'verifierVersion': verifierVersion,
    'movementName': movementName,
    'measurementType': measurementType,
    'count': count,
    'target': target,
    'verificationStatus': verificationStatus,
    'confidence': confidence,
    'framesAnalyzed': framesAnalyzed,
    'validFrames': validFrames,
    'durationMs': durationMs,
    'completionEvents': completionEvents,
    'invalidAttemptCount': invalidAttemptCount,
    if (finalFailureReason != null) 'finalFailureReason': finalFailureReason,
  };

  Map<String, dynamic> toProofPayload({required String clientSubmissionId}) => {
    'proofType': 'ai_motion',
    'clientSubmissionId': clientSubmissionId,
    'client_submission_id': clientSubmissionId,
    'verifierType': verifierType,
    'verifierVersion': verifierVersion,
    'activityType': movementName,
    'metric': 'reps',
    'note': 'AI custom motion proof: $count $movementName detected.',
    'value': count,
    'targetValue': target,
    'detectedValue': count,
    'confidence': confidence,
    'verificationStatus': verificationStatus,
    'verificationSummary': isVerified
        ? 'Nuvo verified $count $movementName.'
        : 'Nuvo did not verify a complete $movementName.',
    'framesAnalyzed': framesAnalyzed,
    'validPoseFrames': validFrames,
    'durationMs': durationMs,
    'validatorVersion': 'nuvo-custom-pose-v$verifierVersion',
    'measurementType': measurementType,
    'completionEvents': completionEvents,
    'invalidAttemptCount': invalidAttemptCount,
    if (finalFailureReason != null) 'finalFailureReason': finalFailureReason,
  };
}

class CustomPoseVerifierReadiness {
  const CustomPoseVerifierReadiness({
    required this.verifierBuilt,
    required this.creatorLiveTestPassed,
    required this.readyForStage6Persistence,
    required this.result,
  });

  final bool verifierBuilt;
  final bool creatorLiveTestPassed;
  final bool readyForStage6Persistence;
  final CustomPoseRuntimeResult result;

  Map<String, dynamic> toJson() => {
    'verifierBuilt': verifierBuilt,
    'creatorLiveTestPassed': creatorLiveTestPassed,
    'readyForStage6Persistence': readyForStage6Persistence,
    'result': result.toJson(),
  };
}

class _WindowMatch {
  const _WindowMatch({
    required this.index,
    required this.similarity,
    this.accepted = false,
  });

  final int index;
  final double similarity;
  final bool accepted;

  _WindowMatch copyWith({bool? accepted}) => _WindowMatch(
    index: index,
    similarity: similarity,
    accepted: accepted ?? this.accepted,
  );
}

class _FrameQuality {
  const _FrameQuality({
    required this.requiredCoverage,
    required this.activeCoverage,
    required this.visibility,
  });

  const _FrameQuality.empty()
    : requiredCoverage = 0,
      activeCoverage = 0,
      visibility = 0;

  final double requiredCoverage;
  final double activeCoverage;
  final double visibility;

  bool get hasRequiredSetup =>
      requiredCoverage >= 0.40 && activeCoverage >= 0.40 && visibility >= 0.30;
}

String _string(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw PoseDataFormatException('Expected non-empty string $field.');
  }
  return value;
}

int _int(Object? value, String field) {
  if (value is! int || value < 0) {
    throw PoseDataFormatException('Expected non-negative integer $field.');
  }
  return value;
}

double _ratio(Object? value, String field) {
  if (value is! num) throw PoseDataFormatException('Expected numeric $field.');
  final result = value.toDouble();
  if (!result.isFinite || result < 0 || result > 1) {
    throw PoseDataFormatException('Expected ratio $field.');
  }
  return result;
}
