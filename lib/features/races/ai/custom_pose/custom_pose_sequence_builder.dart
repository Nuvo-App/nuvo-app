import 'dart:math' as math;

import 'custom_pose_verifier_spec.dart';
import 'normalized_pose.dart';
import 'pose_calibration_models.dart';
import 'pose_sequence_frame.dart';
import 'pose_similarity.dart';

const int customPoseBuilderVersion = 1;
const int customPoseTemplateFrameCount = 24;

class CustomPoseSequenceBuilder {
  const CustomPoseSequenceBuilder({
    this.sequenceFrameCount = customPoseTemplateFrameCount,
  });

  final int sequenceFrameCount;

  CustomPoseBuildResult build(CustomPoseCalibration calibration) {
    try {
      _validateCalibration(calibration);
      final cleaned = calibration.demonstrations
          .map((demo) => _cleanDemonstration(calibration.startPose, demo))
          .toList(growable: false);
      final requiredFeatureIds = _requiredFeatures(
        calibration.startPose,
        cleaned,
      );
      if (requiredFeatureIds.isEmpty) {
        return CustomPoseBuildResult.failure('low_shared_feature_coverage');
      }
      final activeSelection = _selectActiveFeatures(
        calibration.startPose,
        cleaned,
        requiredFeatureIds,
      );
      if (activeSelection.activeFeatureIds.isEmpty) {
        return CustomPoseBuildResult.failure('no_active_features');
      }
      final resampled = cleaned
          .map(
            (demo) => _resample(
              demo.frames,
              activeSelection.activeFeatureIds,
              sequenceFrameCount,
            ),
          )
          .toList(growable: false);
      final consistency = _measureConsistency(
        resampled,
        activeSelection.activeFeatureIds,
      );
      if (!consistency.accepted) {
        return CustomPoseBuildResult.failure(
          consistency.failureReason ?? 'inconsistent_demonstrations',
          diagnostics: activeSelection.diagnostics,
          consistency: consistency,
        );
      }
      final canonical = _canonicalSequence(
        resampled,
        activeSelection.activeFeatureIds,
      );
      final completionStrategy = _completionStrategy(cleaned);
      final completionPose = _completionPose(
        completionStrategy,
        calibration.startPose,
        cleaned,
      );
      final thresholds = _deriveThresholds(
        calibration,
        consistency,
        activeSelection,
      );
      final spec = CustomPoseVerifierSpec(
        schemaVersion: customPoseVerifierSpecSchemaVersion,
        verifierType: customPoseVerifierType,
        movementName: calibration.movementName.trim(),
        measurementType: customPoseMeasurementType,
        startPose: calibration.startPose,
        completionPose: completionPose,
        completionStrategy: completionStrategy,
        canonicalSequence: canonical,
        requiredFeatureIds: activeSelection.activeFeatureIds,
        activeFeatureIds: activeSelection.activeFeatureIds,
        sequenceSimilarityThreshold: thresholds.sequenceSimilarity,
        completionSimilarityThreshold: thresholds.completionSimilarity,
        resetSimilarityThreshold: thresholds.resetSimilarity,
        minimumValidFeatureRatio: thresholds.minimumValidFeatureRatio,
        minimumVisibility: thresholds.minimumVisibility,
        cooldownMs: thresholds.cooldownMs,
        expectedSequenceFrameCount: canonical.length,
        calibrationSummary: CustomPoseCalibrationSummary(
          sourceCalibrationSchemaVersion: calibration.schemaVersion,
          demonstrationCount: calibration.demonstrations.length,
          selectedActiveFeatureCount: activeSelection.activeFeatureIds.length,
          requiredFeatureCount: activeSelection.activeFeatureIds.length,
          canonicalSequenceLength: canonical.length,
          pairwiseSimilarityScores: consistency.pairwiseScores,
          overallConsistencyScore: consistency.overallScore,
          lowestPairwiseSimilarityScore: consistency.lowestPairScore,
          sequenceSimilarityThreshold: thresholds.sequenceSimilarity,
          completionSimilarityThreshold: thresholds.completionSimilarity,
          resetSimilarityThreshold: thresholds.resetSimilarity,
          minimumValidFeatureRatio: thresholds.minimumValidFeatureRatio,
          minimumVisibility: thresholds.minimumVisibility,
          cooldownMs: thresholds.cooldownMs,
          completionStrategy: completionStrategy,
          builderVersion: 'stage4-v$customPoseBuilderVersion',
        ),
      );
      spec.validate();
      final selfValidation = _selfValidate(spec, resampled);
      if (!selfValidation.accepted) {
        return CustomPoseBuildResult.failure(
          selfValidation.failureReason ?? 'self_validation_failed',
          diagnostics: activeSelection.diagnostics,
          consistency: consistency,
        );
      }
      return CustomPoseBuildResult.success(
        spec,
        diagnostics: activeSelection.diagnostics,
        consistency: consistency,
      );
    } on PoseDataFormatException catch (e) {
      return CustomPoseBuildResult.failure(e.message);
    }
  }

  void _validateCalibration(CustomPoseCalibration calibration) {
    if (calibration.schemaVersion != poseCalibrationSchemaVersion) {
      throw PoseDataFormatException(
        'unsupported_calibration_schema_${calibration.schemaVersion}',
      );
    }
    final nameError = validateMovementName(calibration.movementName);
    if (nameError != null) {
      throw const PoseDataFormatException('invalid_movement_name');
    }
    if (!calibration.isReady) {
      throw const PoseDataFormatException('calibration_not_ready');
    }
    if (!calibration.startPose.isValid ||
        calibration.startPose.validFeatureCount == 0) {
      throw const PoseDataFormatException('invalid_start_pose');
    }
    if (calibration.demonstrations.length < 2 ||
        calibration.demonstrations.length > 3) {
      throw const PoseDataFormatException(
        'requires_two_or_three_demonstrations',
      );
    }
    for (final demo in calibration.demonstrations) {
      if (!demo.accepted) {
        throw PoseDataFormatException('demo_${demo.index}_not_accepted');
      }
      if (demo.frames.isEmpty) {
        throw PoseDataFormatException('demo_${demo.index}_empty');
      }
      if (demo.frames.where((frame) => frame.pose.isValid).length < 4) {
        throw PoseDataFormatException(
          'demo_${demo.index}_too_few_valid_frames',
        );
      }
      if (demo.processedFrameCount < demo.frames.length ||
          demo.validFrameCount > demo.processedFrameCount ||
          demo.durationMs < demo.frames.last.elapsedMs) {
        throw PoseDataFormatException('demo_${demo.index}_metadata_mismatch');
      }
      var previousPosition = -1.0;
      var previousElapsed = -1;
      for (final frame in demo.frames) {
        if (!frame.pose.isValid || frame.pose.validFeatureCount == 0) {
          throw PoseDataFormatException('demo_${demo.index}_invalid_frame');
        }
        if (frame.position < previousPosition ||
            frame.elapsedMs < previousElapsed) {
          throw PoseDataFormatException(
            'demo_${demo.index}_non_monotonic_frames',
          );
        }
        previousPosition = frame.position;
        previousElapsed = frame.elapsedMs;
      }
    }
  }

  _CleanedDemonstration _cleanDemonstration(
    NormalizedPose startPose,
    PoseDemonstration demo,
  ) {
    final similarity = const PoseSimilarity(minValidFeatureRatio: 0.35);
    final frames = demo.frames.where((frame) => frame.pose.isValid).toList();
    final startScores = frames
        .map((frame) => similarity.compare(startPose, frame.pose).similarity)
        .toList(growable: false);
    // Require a clearer departure (0.97) than what counts as a return (0.98)
    // so small waves can depart without a terminal pose being forced to count
    // as a return.
    final departed = startScores.indexWhere((score) => score < 0.97);
    if (departed < 0) {
      throw PoseDataFormatException('demo_${demo.index}_static_capture');
    }
    final startIndex = math.max(0, departed - 1);

    var resetSuffixStart = frames.length;
    var suffixCount = 0;
    for (var i = frames.length - 1; i >= startIndex; i--) {
      if (startScores[i] >= 0.98) {
        suffixCount++;
        resetSuffixStart = i;
      } else {
        break;
      }
    }

    var endExclusive = frames.length;
    var returnedToStart = false;
    if (suffixCount >= 2) {
      returnedToStart = true;
      endExclusive = resetSuffixStart + 1;
    } else if (startScores.last >= 0.98 && departed < frames.length - 2) {
      returnedToStart = true;
    }
    final trimmed = frames.sublist(startIndex, endExclusive);
    if (trimmed.length < 3) {
      throw PoseDataFormatException(
        'demo_${demo.index}_too_short_after_trimming',
      );
    }
    final activeScores = startScores.sublist(startIndex, endExclusive);
    final minStartSimilarity = activeScores.reduce(math.min);
    if (minStartSimilarity > 0.995) {
      throw PoseDataFormatException('demo_${demo.index}_no_clear_movement');
    }
    return _CleanedDemonstration(
      index: demo.index,
      frames: _renormalizedFrames(trimmed),
      returnedToStart: returnedToStart,
      minimumStartSimilarity: minStartSimilarity,
    );
  }

  List<PoseSequenceFrame> _renormalizedFrames(List<PoseSequenceFrame> frames) {
    if (frames.length == 1) return frames;
    return List.generate(frames.length, (index) {
      final source = frames[index];
      return PoseSequenceFrame(
        schemaVersion: source.schemaVersion,
        position: index / (frames.length - 1),
        elapsedMs: source.elapsedMs - frames.first.elapsedMs,
        pose: source.pose,
      );
    }, growable: false);
  }

  List<String> _requiredFeatures(
    NormalizedPose startPose,
    List<_CleanedDemonstration> demos,
  ) {
    final ids = startPose.features.values.keys
        .where(isKnownPoseFeatureId)
        .toSet();
    for (final demo in demos) {
      ids.removeWhere((id) => _coverage(demo.frames, id) < 0.70);
    }
    return (ids.toList()..sort()).toList(growable: false);
  }

  _ActiveFeatureSelection _selectActiveFeatures(
    NormalizedPose startPose,
    List<_CleanedDemonstration> demos,
    List<String> requiredFeatureIds,
  ) {
    final active = <String>[];
    final diagnostics = <PoseFeatureSelectionDiagnostic>[];
    for (final id in requiredFeatureIds) {
      final start = startPose.features.values[id];
      if (start == null || !start.valid || start.confidence < 0.45) {
        diagnostics.add(
          PoseFeatureSelectionDiagnostic.rejected(
            featureId: id,
            coverage: 0,
            amplitude: 0,
            consistency: 0,
            reason: 'low_start_confidence',
          ),
        );
        continue;
      }
      final amplitudes = <double>[];
      final coverage = <double>[];
      for (final demo in demos) {
        final values = _validValues(demo.frames, id);
        coverage.add(values.length / demo.frames.length);
        if (values.isEmpty) continue;
        final minValue = values.reduce(math.min);
        final maxValue = values.reduce(math.max);
        final departure = values
            .map((value) => (value - start.value).abs())
            .fold<double>(0, math.max);
        amplitudes.add(math.max(maxValue - minValue, departure));
      }
      final minCoverage = coverage.isEmpty ? 0.0 : coverage.reduce(math.min);
      final averageAmplitude = _average(amplitudes);
      final consistency = _amplitudeConsistency(amplitudes);
      final movementThreshold = _movementThreshold(start.kind);
      String? rejectionReason;
      if (minCoverage < 0.70) {
        rejectionReason = 'low_coverage';
      } else if (averageAmplitude < movementThreshold) {
        rejectionReason = 'mostly_static';
      } else if (consistency < 0.35) {
        rejectionReason = 'inconsistent_motion';
      }
      if (rejectionReason == null) {
        active.add(id);
        diagnostics.add(
          PoseFeatureSelectionDiagnostic.selected(
            featureId: id,
            coverage: minCoverage,
            amplitude: averageAmplitude,
            consistency: consistency,
          ),
        );
      } else {
        diagnostics.add(
          PoseFeatureSelectionDiagnostic.rejected(
            featureId: id,
            coverage: minCoverage,
            amplitude: averageAmplitude,
            consistency: consistency,
            reason: rejectionReason,
          ),
        );
      }
    }
    return _ActiveFeatureSelection(
      activeFeatureIds: (active..sort()).toList(growable: false),
      diagnostics: diagnostics,
    );
  }

  List<_SampledFrame> _resample(
    List<PoseSequenceFrame> frames,
    List<String> featureIds,
    int count,
  ) {
    if (count < 2) {
      throw const PoseDataFormatException('sequence_length_too_short');
    }
    return List.generate(count, (index) {
      final position = index / (count - 1);
      final values = <String, _SampledFeature>{};
      for (final id in featureIds) {
        final value = _interpolateFeature(frames, id, position);
        if (value != null) values[id] = value;
      }
      return _SampledFrame(position: position, features: values);
    }, growable: false);
  }

  _SampledFeature? _interpolateFeature(
    List<PoseSequenceFrame> frames,
    String id,
    double position,
  ) {
    if (position <= 0) return _featureAt(frames.first, id);
    if (position >= 1) return _featureAt(frames.last, id);
    var upperIndex = frames.indexWhere((frame) => frame.position >= position);
    if (upperIndex <= 0) upperIndex = 1;
    final lower = frames[upperIndex - 1];
    final upper = frames[upperIndex];
    final left = _featureAt(lower, id);
    final right = _featureAt(upper, id);
    if (left == null || right == null || left.kind != right.kind) return null;
    final span = upper.position - lower.position;
    if (span <= 0) return left;
    final t = ((position - lower.position) / span).clamp(0.0, 1.0);
    final value = left.value + (right.value - left.value) * t;
    final confidence = math.min(left.confidence, right.confidence);
    if (!value.isFinite || !confidence.isFinite) return null;
    return _SampledFeature(
      value: value,
      confidence: confidence,
      kind: left.kind,
    );
  }

  _SampledFeature? _featureAt(PoseSequenceFrame frame, String id) {
    final feature = frame.pose.features.values[id];
    if (feature == null || !feature.valid || !feature.value.isFinite) {
      return null;
    }
    return _SampledFeature(
      value: feature.value,
      confidence: feature.confidence,
      kind: feature.kind,
    );
  }

  CustomPoseConsistencyResult _measureConsistency(
    List<List<_SampledFrame>> demos,
    List<String> activeFeatureIds,
  ) {
    final pairScores = <String, double>{};
    for (var a = 0; a < demos.length; a++) {
      for (var b = a + 1; b < demos.length; b++) {
        pairScores['${a + 1}-${b + 1}'] = _sequenceSimilarity(
          demos[a],
          demos[b],
          activeFeatureIds,
        );
      }
    }
    final scores = pairScores.values.toList(growable: false);
    final lowest = scores.reduce(math.min);
    final overall = _average(scores);
    String? failure;
    if (activeFeatureIds.length < 2) {
      failure = 'too_few_active_features';
    } else if (lowest < 0.60) {
      failure = 'inconsistent_demonstrations';
    } else if (overall < 0.65) {
      failure = 'low_overall_consistency';
    }
    return CustomPoseConsistencyResult(
      pairwiseScores: Map.unmodifiable(pairScores),
      overallScore: overall,
      lowestPairScore: lowest,
      accepted: failure == null,
      failureReason: failure,
    );
  }

  double _sequenceSimilarity(
    List<_SampledFrame> a,
    List<_SampledFrame> b,
    List<String> featureIds,
  ) {
    var weighted = 0.0;
    var weightTotal = 0.0;
    for (var i = 0; i < math.min(a.length, b.length); i++) {
      for (final id in featureIds) {
        final left = a[i].features[id];
        final right = b[i].features[id];
        if (left == null || right == null) continue;
        final tolerance = _toleranceFor(left.kind);
        final contribution = (1 - (left.value - right.value).abs() / tolerance)
            .clamp(0.0, 1.0);
        final weight = math
            .min(left.confidence, right.confidence)
            .clamp(0.0, 1.0);
        weighted += contribution * weight;
        weightTotal += weight;
      }
    }
    if (weightTotal <= 0) return 0;
    return (weighted / weightTotal).clamp(0.0, 1.0);
  }

  List<PoseTemplateFrame> _canonicalSequence(
    List<List<_SampledFrame>> demos,
    List<String> activeFeatureIds,
  ) {
    return List.generate(sequenceFrameCount, (index) {
      final position = index / (sequenceFrameCount - 1);
      final features = <String, PoseTemplateFeature>{};
      for (final id in activeFeatureIds) {
        final samples = demos
            .map((demo) => demo[index].features[id])
            .whereType<_SampledFeature>()
            .toList(growable: false);
        if (samples.length < 2) continue;
        final kind = samples.first.kind;
        if (samples.any((sample) => sample.kind != kind)) continue;
        final values = samples.map((sample) => sample.value).toList();
        final spread = values.reduce(math.max) - values.reduce(math.min);
        final tolerance = _toleranceFor(kind);
        features[id] = PoseTemplateFeature(
          value: _average(values),
          confidence: _average(samples.map((sample) => sample.confidence)),
          reliability: (1 - spread / tolerance).clamp(0.0, 1.0),
          allowedVariation: math.max(spread, tolerance * 0.10),
          contributingDemonstrationCount: samples.length,
          kind: kind,
        );
      }
      if (features.isEmpty) {
        throw PoseDataFormatException(
          'template_frame_${index}_has_no_features',
        );
      }
      return PoseTemplateFrame(
        position: position,
        features: Map.unmodifiable(features),
      );
    }, growable: false);
  }

  CustomPoseCompletionStrategy _completionStrategy(
    List<_CleanedDemonstration> demos,
  ) {
    final returned = demos.where((demo) => demo.returnedToStart).length;
    if (returned == demos.length) {
      return CustomPoseCompletionStrategy.completionAfterSequenceReturn;
    }
    if (returned == 0) {
      return CustomPoseCompletionStrategy.completionAtTerminalPose;
    }
    throw const PoseDataFormatException('ambiguous_completion_strategy');
  }

  NormalizedPose _completionPose(
    CustomPoseCompletionStrategy strategy,
    NormalizedPose startPose,
    List<_CleanedDemonstration> demos,
  ) {
    if (strategy ==
        CustomPoseCompletionStrategy.completionAfterSequenceReturn) {
      return startPose;
    }
    final poses = demos.map((demo) => demo.frames.last.pose).toList();
    return _averagePoseFeatures(poses);
  }

  NormalizedPose _averagePoseFeatures(List<NormalizedPose> poses) {
    final ids = <String>{
      for (final pose in poses) ...pose.features.values.keys,
    };
    final features = <String, PoseFeatureValue>{};
    for (final id in ids.toList()..sort()) {
      final values = poses
          .map((pose) => pose.features.values[id])
          .whereType<PoseFeatureValue>()
          .where((feature) => feature.valid)
          .toList();
      if (values.length < 2) continue;
      final kind = values.first.kind;
      if (values.any((value) => value.kind != kind)) continue;
      features[id] = PoseFeatureValue(
        value: _average(values.map((value) => value.value)),
        confidence: _average(values.map((value) => value.confidence)),
        valid: true,
        kind: kind,
      );
    }
    if (features.isEmpty) {
      throw const PoseDataFormatException('completion_pose_has_no_features');
    }
    return NormalizedPose(
      schemaVersion: normalizedPoseSchemaVersion,
      landmarks: const {},
      features: PoseFeatureVector(Map.unmodifiable(features)),
      originX: _average(poses.map((pose) => pose.originX)),
      originY: _average(poses.map((pose) => pose.originY)),
      scale: _average(poses.map((pose) => pose.scale)),
      originReference: poses.first.originReference,
      scaleReference: poses.first.scaleReference,
      validLandmarkCount: 0,
      validFeatureCount: features.length,
    );
  }

  _GeneratedThresholds _deriveThresholds(
    CustomPoseCalibration calibration,
    CustomPoseConsistencyResult consistency,
    _ActiveFeatureSelection selection,
  ) {
    final sequence = (consistency.lowestPairScore - 0.08).clamp(0.55, 0.88);
    final completion = (0.76 + calibration.quality.startPoseStability * 0.08)
        .clamp(0.74, 0.88);
    final reset = (0.78 + calibration.quality.startPoseStability * 0.10).clamp(
      0.78,
      0.92,
    );
    final validRatio = (0.55 + selection.activeFeatureIds.length / 100).clamp(
      0.55,
      0.75,
    );
    final visibility = calibration.quality.averagePoseCoverage.clamp(
      0.45,
      0.75,
    );
    return _GeneratedThresholds(
      sequenceSimilarity: sequence.toDouble(),
      completionSimilarity: completion.toDouble(),
      resetSimilarity: reset.toDouble(),
      minimumValidFeatureRatio: validRatio.toDouble(),
      minimumVisibility: visibility.toDouble(),
      cooldownMs: 900,
    );
  }

  CustomPoseConsistencyResult _selfValidate(
    CustomPoseVerifierSpec spec,
    List<List<_SampledFrame>> demos,
  ) {
    final template = spec.canonicalSequence
        .map(
          (frame) => _SampledFrame(
            position: frame.position,
            features: frame.features.map(
              (key, value) => MapEntry(
                key,
                _SampledFeature(
                  value: value.value,
                  confidence: value.confidence,
                  kind: value.kind,
                ),
              ),
            ),
          ),
        )
        .toList(growable: false);
    final scores = <String, double>{};
    for (var i = 0; i < demos.length; i++) {
      scores['source-${i + 1}'] = _sequenceSimilarity(
        demos[i],
        template,
        spec.activeFeatureIds,
      );
    }
    final lowest = scores.values.reduce(math.min);
    final overall = _average(scores.values);
    return CustomPoseConsistencyResult(
      pairwiseScores: scores,
      overallScore: overall,
      lowestPairScore: lowest,
      accepted: lowest >= spec.sequenceSimilarityThreshold,
      failureReason: lowest >= spec.sequenceSimilarityThreshold
          ? null
          : 'source_demonstration_below_threshold',
    );
  }

  List<double> _validValues(List<PoseSequenceFrame> frames, String id) {
    return frames
        .map((frame) => frame.pose.features.values[id])
        .whereType<PoseFeatureValue>()
        .where((feature) => feature.valid)
        .map((feature) => feature.value)
        .where((value) => value.isFinite)
        .toList(growable: false);
  }

  double _coverage(List<PoseSequenceFrame> frames, String id) {
    if (frames.isEmpty) return 0;
    return _validValues(frames, id).length / frames.length;
  }

  double _amplitudeConsistency(List<double> values) {
    if (values.length < 2) return 0;
    final maxValue = values.reduce(math.max);
    final minValue = values.reduce(math.min);
    if (maxValue <= 0) return 0;
    return (minValue / maxValue).clamp(0.0, 1.0);
  }

  double _movementThreshold(String kind) {
    return switch (kind) {
      'coord' => 0.15,
      'angle' => 0.08,
      'distance' => 0.12,
      _ => 0.15,
    };
  }

  double _toleranceFor(String kind) {
    return switch (kind) {
      'coord' => 0.35,
      'angle' => 0.22,
      'distance' => 0.45,
      _ => 0.35,
    };
  }

  double _average(Iterable<double> values) {
    final list = values.where((value) => value.isFinite).toList();
    if (list.isEmpty) return 0;
    return list.fold<double>(0, (sum, value) => sum + value) / list.length;
  }
}

class CustomPoseBuildResult {
  const CustomPoseBuildResult._({
    required this.succeeded,
    required this.spec,
    required this.failureReason,
    required this.featureDiagnostics,
    required this.consistency,
  });

  factory CustomPoseBuildResult.success(
    CustomPoseVerifierSpec spec, {
    required List<PoseFeatureSelectionDiagnostic> diagnostics,
    required CustomPoseConsistencyResult consistency,
  }) {
    return CustomPoseBuildResult._(
      succeeded: true,
      spec: spec,
      failureReason: null,
      featureDiagnostics: List.unmodifiable(diagnostics),
      consistency: consistency,
    );
  }

  factory CustomPoseBuildResult.failure(
    String reason, {
    List<PoseFeatureSelectionDiagnostic> diagnostics = const [],
    CustomPoseConsistencyResult? consistency,
  }) {
    return CustomPoseBuildResult._(
      succeeded: false,
      spec: null,
      failureReason: reason,
      featureDiagnostics: List.unmodifiable(diagnostics),
      consistency: consistency,
    );
  }

  final bool succeeded;
  final CustomPoseVerifierSpec? spec;
  final String? failureReason;
  final List<PoseFeatureSelectionDiagnostic> featureDiagnostics;
  final CustomPoseConsistencyResult? consistency;
}

class PoseFeatureSelectionDiagnostic {
  const PoseFeatureSelectionDiagnostic({
    required this.featureId,
    required this.coverage,
    required this.amplitude,
    required this.consistency,
    required this.selected,
    required this.rejectionReason,
  });

  factory PoseFeatureSelectionDiagnostic.selected({
    required String featureId,
    required double coverage,
    required double amplitude,
    required double consistency,
  }) {
    return PoseFeatureSelectionDiagnostic(
      featureId: featureId,
      coverage: coverage,
      amplitude: amplitude,
      consistency: consistency,
      selected: true,
      rejectionReason: null,
    );
  }

  factory PoseFeatureSelectionDiagnostic.rejected({
    required String featureId,
    required double coverage,
    required double amplitude,
    required double consistency,
    required String reason,
  }) {
    return PoseFeatureSelectionDiagnostic(
      featureId: featureId,
      coverage: coverage,
      amplitude: amplitude,
      consistency: consistency,
      selected: false,
      rejectionReason: reason,
    );
  }

  final String featureId;
  final double coverage;
  final double amplitude;
  final double consistency;
  final bool selected;
  final String? rejectionReason;
}

class CustomPoseConsistencyResult {
  const CustomPoseConsistencyResult({
    required this.pairwiseScores,
    required this.overallScore,
    required this.lowestPairScore,
    required this.accepted,
    required this.failureReason,
  });

  final Map<String, double> pairwiseScores;
  final double overallScore;
  final double lowestPairScore;
  final bool accepted;
  final String? failureReason;
}

class _CleanedDemonstration {
  const _CleanedDemonstration({
    required this.index,
    required this.frames,
    required this.returnedToStart,
    required this.minimumStartSimilarity,
  });

  final int index;
  final List<PoseSequenceFrame> frames;
  final bool returnedToStart;
  final double minimumStartSimilarity;
}

class _ActiveFeatureSelection {
  const _ActiveFeatureSelection({
    required this.activeFeatureIds,
    required this.diagnostics,
  });

  final List<String> activeFeatureIds;
  final List<PoseFeatureSelectionDiagnostic> diagnostics;
}

class _SampledFrame {
  const _SampledFrame({required this.position, required this.features});

  final double position;
  final Map<String, _SampledFeature> features;
}

class _SampledFeature {
  const _SampledFeature({
    required this.value,
    required this.confidence,
    required this.kind,
  });

  final double value;
  final double confidence;
  final String kind;
}

class _GeneratedThresholds {
  const _GeneratedThresholds({
    required this.sequenceSimilarity,
    required this.completionSimilarity,
    required this.resetSimilarity,
    required this.minimumValidFeatureRatio,
    required this.minimumVisibility,
    required this.cooldownMs,
  });

  final double sequenceSimilarity;
  final double completionSimilarity;
  final double resetSimilarity;
  final double minimumValidFeatureRatio;
  final double minimumVisibility;
  final int cooldownMs;
}
