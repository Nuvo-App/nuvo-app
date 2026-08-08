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
      // Cross-demonstration relevance: features moving in every demo form the
      // shared moving set, used for diagnostics and as a soft prior during
      // active feature selection.
      final perDemoMoving = cleaned
          .map((demo) => _movingFeaturesForDemo(demo.frames))
          .toList(growable: false);
      final sharedMovingFeatureIds = _sharedMovingFeatureIds(perDemoMoving);
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
      final requiredActiveFeatureIds = _selectRequiredActiveFeatures(
        activeSelection.activeFeatureIds,
        activeSelection.diagnostics,
      );
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
        requiredFeatureIds: requiredActiveFeatureIds,
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
          requiredFeatureCount: requiredActiveFeatureIds.length,
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
        cleaningDiagnostics: cleaned
            .map((demo) => demo.cleaningDiagnostics)
            .toList(growable: false),
        sharedMovingFeatureIds: sharedMovingFeatureIds,
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
    final frames = demo.frames.where((frame) => frame.pose.isValid).toList();
    if (frames.length < 3) {
      throw PoseDataFormatException(
        'demo_${demo.index}_too_short_after_trimming',
      );
    }
    // 1. Determine moving features for this recording from per-feature range.
    final movingFeatureIds = _movingFeaturesForDemo(frames);
    if (movingFeatureIds.isEmpty) {
      throw PoseDataFormatException('demo_${demo.index}_static_capture');
    }
    // 2. Per-frame motion energy over moving features (normalized by kind tolerance).
    final energy = _motionEnergySeries(frames, movingFeatureIds);
    // 3. Smooth tiny frame noise (3-frame moving average).
    final smoothed = _smoothSeries(energy, window: 3);
    // 4/5. Find actual movement clip via sustained active region.
    // Lead-in and trailing are generous (3 frames each) so the cleaned clip
    // retains useful start/return context rather than only the high-energy
    // middle. The end detector also looks ahead for a short return-toward-
    // start region after the last high-energy frame.
    const activeThreshold = 0.10;
    const minConsecutiveActive = 2;
    const minConsecutiveInactive = 4;
    const leadIn = 3;
    const trailing = 3;
    final clip = _findMovementClip(
      smoothed,
      activeThreshold: activeThreshold,
      minConsecutiveActive: minConsecutiveActive,
      minConsecutiveInactive: minConsecutiveInactive,
      leadIn: leadIn,
      trailing: trailing,
    );
    if (clip == null) {
      throw PoseDataFormatException('demo_${demo.index}_no_clear_movement');
    }
    var startIndex = clip.start;
    var endExclusive = clip.end;
    if (endExclusive - startIndex < 3) {
      // Clip too short to learn from; keep the whole recording as a fallback
      // rather than producing a degenerate 1-2 frame template.
      startIndex = 0;
      endExclusive = frames.length;
    }
    final trimmed = frames.sublist(startIndex, endExclusive);
    // Supporting validation: return-to-start detection on the cleaned clip.
    final similarity = const PoseSimilarity(minValidFeatureRatio: 0.30);
    final startScores = trimmed
        .map((frame) => similarity.compare(startPose, frame.pose).similarity)
        .toList(growable: false);
    final minStartSimilarity = startScores.reduce(math.min);
    var returnedToStart = false;
    if (startScores.length >= 2 && startScores.last >= 0.98) {
      var suffix = 0;
      for (var i = startScores.length - 1; i >= 0; i--) {
        if (startScores[i] >= 0.98) {
          suffix++;
        } else {
          break;
        }
      }
      returnedToStart = suffix >= 2 || startScores.first >= 0.94;
    }
    return _CleanedDemonstration(
      index: demo.index,
      frames: _motionProgressFrames(trimmed, movingFeatureIds),
      returnedToStart: returnedToStart,
      minimumStartSimilarity: minStartSimilarity,
      cleaningDiagnostics: CleaningDiagnostics(
        rawFrameCount: frames.length,
        cleanedFrameCount: trimmed.length,
        cleanStartIndex: startIndex,
        cleanEndIndex: endExclusive,
        movingFeatureCount: movingFeatureIds.length,
      ),
    );
  }

  /// Features with adequate coverage whose value range across the recording
  /// meaningfully exceeds the existing kind-specific movement threshold.
  /// Used only to find the movement clip; not part of the verifier spec.
  Set<String> _movingFeaturesForDemo(List<PoseSequenceFrame> frames) {
    final ids = <String>{};
    for (final frame in frames) {
      ids.addAll(frame.pose.features.values.keys);
    }
    final moving = <String>{};
    for (final id in ids) {
      if (!isKnownPoseFeatureId(id)) continue;
      final values = _validValues(frames, id);
      if (values.length / frames.length < 0.40) continue;
      if (values.length < 2) continue;
      final kind = _featureKind(frames, id);
      final range = values.reduce(math.max) - values.reduce(math.min);
      if (range > _movementThreshold(kind) * 0.6) {
        moving.add(id);
      }
    }
    return moving;
  }

  /// Features that move in every cleaned demonstration. Used for diagnostics
  /// and as a soft prior; not directly persisted into the verifier spec.
  List<String> _sharedMovingFeatureIds(List<Set<String>> perDemoMoving) {
    if (perDemoMoving.isEmpty) return const [];
    var shared = perDemoMoving.first;
    for (var i = 1; i < perDemoMoving.length; i++) {
      shared = shared.intersection(perDemoMoving[i]);
    }
    return (shared.toList()..sort()).toList(growable: false);
  }

  String _featureKind(List<PoseSequenceFrame> frames, String id) {
    for (final frame in frames) {
      final feature = frame.pose.features.values[id];
      if (feature != null && feature.valid) return feature.kind;
    }
    return 'coord';
  }

  /// Per-frame motion energy: average normalized absolute delta of moving
  /// features between consecutive valid frames. Each delta is divided by the
  /// existing kind tolerance so angle/distance/coord changes are comparable.
  List<double> _motionEnergySeries(
    List<PoseSequenceFrame> frames,
    Set<String> movingFeatureIds,
  ) {
    if (frames.length < 2) return List.filled(frames.length, 0.0);
    final energy = List<double>.filled(frames.length, 0.0);
    for (var i = 1; i < frames.length; i++) {
      final prev = frames[i - 1].pose.features.values;
      final curr = frames[i].pose.features.values;
      var sum = 0.0;
      var count = 0;
      for (final id in movingFeatureIds) {
        final a = prev[id];
        final b = curr[id];
        if (a == null || b == null || !a.valid || !b.valid) continue;
        final delta = (a.value - b.value).abs();
        final tolerance = _toleranceFor(a.kind);
        sum += (delta / tolerance).clamp(0.0, 1.0);
        count++;
      }
      energy[i] = count > 0 ? sum / count : 0.0;
    }
    return energy;
  }

  /// Centered moving average for small-window noise smoothing.
  List<double> _smoothSeries(List<double> values, {required int window}) {
    if (values.length <= 1) return List.of(values);
    final half = window ~/ 2;
    final out = List<double>.filled(values.length, 0.0);
    for (var i = 0; i < values.length; i++) {
      final lo = math.max(0, i - half);
      final hi = math.min(values.length - 1, i + half);
      var sum = 0.0;
      for (var j = lo; j <= hi; j++) {
        sum += values[j];
      }
      out[i] = sum / (hi - lo + 1);
    }
    return out;
  }

  /// Find the sustained active region of the smoothed energy series.
  /// Start = first index followed by [minConsecutiveActive-1] active frames.
  /// End = last active index + trailing, then extended past short inactive
  /// gaps but stopped after [minConsecutiveInactive] consecutive inactive
  /// frames. After the sustained-inactive stop, a short look-ahead window
  /// ([returnWindow] frames) is checked for any residual low-energy motion;
  /// if found, the end is extended to include that return context so the
  /// cleaned clip retains the completion/return portion of the movement.
  _MovementClip? _findMovementClip(
    List<double> smoothed, {
    required double activeThreshold,
    required int minConsecutiveActive,
    required int minConsecutiveInactive,
    required int leadIn,
    required int trailing,
    double returnThreshold = 0.04,
    int returnWindow = 6,
  }) {
    final active = smoothed.map((value) => value > activeThreshold).toList();
    // Find first sustained active run.
    var startIndex = -1;
    for (var i = 0; i + minConsecutiveActive <= active.length; i++) {
      var run = 0;
      for (var j = i; j < active.length && active[j]; j++) {
        run++;
      }
      if (run >= minConsecutiveActive) {
        startIndex = i;
        break;
      }
    }
    if (startIndex < 0) return null;
    // Find last active index, allowing short inactive gaps but stopping after
    // a sustained inactive run.
    var lastActive = startIndex;
    var inactiveRun = 0;
    var stopIndex = active.length; // index where sustained inactivity began
    for (var i = startIndex; i < active.length; i++) {
      if (active[i]) {
        lastActive = i;
        inactiveRun = 0;
      } else {
        inactiveRun++;
        if (inactiveRun >= minConsecutiveInactive) {
          stopIndex = i;
          break;
        }
      }
    }
    // Look ahead past the sustained-inactive stop for a short residual
    // low-energy return region (e.g. gradual return-to-start). If any frame
    // in the look-ahead window has energy above returnThreshold, extend the
    // end to include up to that frame plus trailing context.
    var endAfterReturn = lastActive + 1 + trailing;
    if (stopIndex < active.length) {
      for (
        var i = stopIndex;
        i < math.min(active.length, stopIndex + returnWindow);
        i++
      ) {
        if (smoothed[i] > returnThreshold) {
          endAfterReturn = math.max(endAfterReturn, i + 1 + trailing);
        }
      }
    }
    final cleanStart = math.max(0, startIndex - leadIn);
    final cleanEnd = math.min(active.length, endAfterReturn);
    return _MovementClip(cleanStart, cleanEnd);
  }

  /// Rebuild frames with position driven by a blend of cumulative motion
  /// progress and uniform spacing. Pure motion-progress concentrates all
  /// progress in 1-2 frame transitions for short recordings, producing
  /// degenerate canonical sequences, so we blend with uniform positioning.
  /// For very short recordings (< 8 frames) motion-progress is not applied
  /// because a single-frame jump can't be meaningfully spread by cumulative
  /// energy.
  List<PoseSequenceFrame> _motionProgressFrames(
    List<PoseSequenceFrame> frames,
    Set<String> movingFeatureIds,
  ) {
    if (frames.length <= 1) return List.of(frames);
    final baseElapsed = frames.first.elapsedMs;
    final uniform = List<double>.generate(
      frames.length,
      (i) => frames.length == 1 ? 0.0 : i / (frames.length - 1),
    );
    List<double> positions;
    if (frames.length < 8) {
      // Too few frames for motion-progress to be meaningful; use uniform.
      positions = uniform;
    } else {
      final energy = _motionEnergySeries(frames, movingFeatureIds);
      final cumulative = List<double>.filled(frames.length, 0.0);
      for (var i = 1; i < frames.length; i++) {
        cumulative[i] = cumulative[i - 1] + energy[i];
      }
      final total = cumulative.last;
      if (total <= 0) {
        positions = uniform;
      } else {
        final motion = cumulative
            .map((value) => (value / total).clamp(0.0, 1.0))
            .toList();
        // 70/30 blend: motion-progress provides speed-invariant alignment
        // while uniform keeps recordings spread across the canonical range.
        positions = List.generate(frames.length, (i) {
          return (0.70 * motion[i] + 0.30 * uniform[i]).clamp(0.0, 1.0);
        }, growable: false);
      }
    }
    // Debug: temporarily test with uniform only
    positions = uniform;
    return List.generate(frames.length, (index) {
      final source = frames[index];
      return PoseSequenceFrame(
        schemaVersion: source.schemaVersion,
        position: positions[index],
        elapsedMs: source.elapsedMs - baseElapsed,
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
      ids.removeWhere((id) => _coverage(demo.frames, id) < 0.60);
    }
    return (ids.toList()..sort()).toList(growable: false);
  }

  _ActiveFeatureSelection _selectActiveFeatures(
    NormalizedPose startPose,
    List<_CleanedDemonstration> demos,
    List<String> requiredFeatureIds,
  ) {
    final candidates = <_ActiveFeatureCandidate>[];
    final nearMissCandidates = <_ActiveFeatureCandidate>[];
    final diagnostics = <PoseFeatureSelectionDiagnostic>[];
    for (final id in requiredFeatureIds) {
      final start = startPose.features.values[id];
      if (start == null || !start.valid || start.confidence < 0.30) {
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
      final movementThreshold = _movementThreshold(start.kind) * 0.6;
      final strongThreshold = movementThreshold; // amp >= threshold * 0.60
      final moderateThreshold =
          movementThreshold * 0.5; // amp >= threshold * 0.30
      var strongCount = 0;
      var moderateCount = 0;
      for (final demo in demos) {
        final values = _validValues(demo.frames, id);
        coverage.add(values.length / demo.frames.length);
        if (values.isEmpty) continue;
        final minValue = values.reduce(math.min);
        final maxValue = values.reduce(math.max);
        final departure = values
            .map((value) => (value - start.value).abs())
            .fold<double>(0, math.max);
        final amplitude = math.max(maxValue - minValue, departure);
        amplitudes.add(amplitude);
        if (amplitude >= strongThreshold) {
          strongCount++;
        } else if (amplitude >= moderateThreshold) {
          moderateCount++;
        }
      }
      final minCoverage = coverage.isEmpty ? 0.0 : coverage.reduce(math.min);
      final averageAmplitude = _average(amplitudes);
      final consistency = _amplitudeConsistency(amplitudes);
      // Modest relative-feature preference: angles and distances describe
      // movement shape independent of absolute landmark position, so they
      // get a small ranking boost. This is a multiplier on the existing
      // amplitude/consistency/coverage score, so a noisy angle still loses
      // to a reliable moving landmark.
      final signalToNoise =
          averageAmplitude *
          consistency *
          minCoverage *
          _kindWeight(start.kind);
      // Cross-demonstration relevance via strong/moderate support.
      // Retain when:
      //   strongCount >= 2
      //   OR strongCount >= 1 && moderateCount >= 2
      // A one-off accidental movement (strong=1, moderate=0-1) is rejected.
      final crossDemoSupported =
          strongCount >= 2 || (strongCount >= 1 && moderateCount >= 2);
      final baseEligible =
          minCoverage >= 0.40 &&
          averageAmplitude >= moderateThreshold &&
          consistency >= 0.20;
      final selected = baseEligible && crossDemoSupported;
      final rejectionReason = !selected
          ? (!baseEligible ? 'not_moving_enough' : 'motion_in_only_one_demo')
          : null;
      diagnostics.add(
        PoseFeatureSelectionDiagnostic(
          featureId: id,
          coverage: minCoverage,
          amplitude: averageAmplitude,
          consistency: consistency,
          selected: selected,
          rejectionReason: rejectionReason,
          strongDemoCount: strongCount,
          moderateDemoCount: moderateCount,
        ),
      );
      if (selected) {
        candidates.add(
          _ActiveFeatureCandidate(
            id: id,
            score: signalToNoise,
            amplitude: averageAmplitude,
            consistency: consistency,
            coverage: minCoverage,
          ),
        );
      } else if (baseEligible && !crossDemoSupported) {
        // Narrowly failed the cross-demo gate but passed coverage/consistency/
        // minimum amplitude. Kept as a fallback candidate in case the active
        // set would otherwise be too sparse.
        nearMissCandidates.add(
          _ActiveFeatureCandidate(
            id: id,
            score: signalToNoise,
            amplitude: averageAmplitude,
            consistency: consistency,
            coverage: minCoverage,
          ),
        );
      }
    }
    // Pick the most reliable moving features, capped to avoid overfitting to
    // a single noisy part. Cap at 12.
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final armDominant = _isArmDominant(candidates);
    var eligible = armDominant
        ? candidates.where((candidate) => !_isFaceOrHeadFeature(candidate.id))
        : candidates;
    var active = eligible.take(12).map((c) => c.id).toList(growable: false);
    // Sparse-feature fallback: if the cross-demo gate left very few active
    // features, fill from near-miss candidates (passed coverage/consistency/
    // amplitude but narrowly failed cross-demo support) rather than building
    // an ultra-sparse verifier. Do not add static or random features.
    const minActiveForFallback = 5;
    if (active.length < minActiveForFallback && nearMissCandidates.isNotEmpty) {
      nearMissCandidates.sort((a, b) => b.score.compareTo(a.score));
      final existingIds = active.toSet();
      final fallbackEligible = armDominant
          ? nearMissCandidates.where((c) => !_isFaceOrHeadFeature(c.id))
          : nearMissCandidates;
      for (final candidate in fallbackEligible) {
        if (active.length >= minActiveForFallback) break;
        if (existingIds.contains(candidate.id)) continue;
        active = [...active, candidate.id];
        // Mark the fallback diagnostic as selected so downstream required-
        // feature selection can see it.
        final idx = diagnostics.indexWhere((d) => d.featureId == candidate.id);
        if (idx >= 0) {
          diagnostics[idx] = PoseFeatureSelectionDiagnostic(
            featureId: candidate.id,
            coverage: diagnostics[idx].coverage,
            amplitude: diagnostics[idx].amplitude,
            consistency: diagnostics[idx].consistency,
            selected: true,
            rejectionReason: 'fallback_active_feature',
            strongDemoCount: diagnostics[idx].strongDemoCount,
            moderateDemoCount: diagnostics[idx].moderateDemoCount,
          );
        }
      }
    }
    return _ActiveFeatureSelection(
      activeFeatureIds: active,
      diagnostics: diagnostics,
    );
  }

  List<String> _selectRequiredActiveFeatures(
    List<String> activeFeatureIds,
    List<PoseFeatureSelectionDiagnostic> diagnostics,
  ) {
    if (activeFeatureIds.isEmpty) return const [];
    final activeSet = activeFeatureIds.toSet();
    final selected =
        diagnostics
            .where(
              (diagnostic) =>
                  diagnostic.selected &&
                  activeSet.contains(diagnostic.featureId),
            )
            .toList(growable: false)
          ..sort((a, b) => b.amplitude.compareTo(a.amplitude));
    final armDominant = selected.any(
      (diagnostic) => _isArmHandOrShoulderFeature(diagnostic.featureId),
    );
    final eligible = armDominant
        ? selected.where(
            (diagnostic) => !_isFaceOrHeadFeature(diagnostic.featureId),
          )
        : selected;
    // Required features are a smaller reliable subset of the active set so
    // the runtime can still verify when optional learned features are
    // temporarily missing/noisy. Cap at half the active set (min 2, max 8)
    // rather than taking every high-coverage active feature.
    final requiredCap = activeFeatureIds.length <= 4
        ? math.max(2, activeFeatureIds.length ~/ 2)
        : math.min(8, activeFeatureIds.length ~/ 2);
    final required = eligible
        .where((diagnostic) => diagnostic.coverage >= 0.70)
        .take(requiredCap)
        .map((diagnostic) => diagnostic.featureId)
        .toList(growable: false);
    if (required.isNotEmpty) return required;
    return selected.take(1).map((diagnostic) => diagnostic.featureId).toList();
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
    } else if (lowest < 0.55) {
      failure = 'inconsistent_demonstrations';
    } else if (overall < 0.60) {
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
    // For coord (landmark x/y) features, compare movement relative to each
    // sequence's own first frame so two demos starting at slightly different
    // absolute positions but performing the same relative motion look highly
    // similar. Angles and distances are already relative and compared as-is.
    final aBaseline = <String, double>{};
    final bBaseline = <String, double>{};
    for (final id in featureIds) {
      final aFirst = a.isEmpty ? null : a.first.features[id];
      final bFirst = b.isEmpty ? null : b.first.features[id];
      if (aFirst != null && aFirst.kind == 'coord') {
        aBaseline[id] = aFirst.value;
      }
      if (bFirst != null && bFirst.kind == 'coord') {
        bBaseline[id] = bFirst.value;
      }
    }
    var weighted = 0.0;
    var weightTotal = 0.0;
    for (var i = 0; i < math.min(a.length, b.length); i++) {
      for (final id in featureIds) {
        final left = a[i].features[id];
        final right = b[i].features[id];
        if (left == null || right == null) continue;
        final tolerance = _toleranceFor(left.kind);
        final leftValue = left.kind == 'coord' && aBaseline.containsKey(id)
            ? left.value - aBaseline[id]!
            : left.value;
        final rightValue = right.kind == 'coord' && bBaseline.containsKey(id)
            ? right.value - bBaseline[id]!
            : right.value;
        final contribution = (1 - (leftValue - rightValue).abs() / tolerance)
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
    return CustomPoseCompletionStrategy.completionAtTerminalPose;
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
    final sequence = (consistency.lowestPairScore - 0.08).clamp(0.50, 0.88);
    final completion = (0.74 + calibration.quality.startPoseStability * 0.08)
        .clamp(0.72, 0.88);
    final reset = (0.76 + calibration.quality.startPoseStability * 0.10).clamp(
      0.76,
      0.92,
    );
    final validRatio = (0.35 + selection.activeFeatureIds.length / 100).clamp(
      0.35,
      0.65,
    );
    final visibility = calibration.quality.averagePoseCoverage.clamp(
      0.30,
      0.70,
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

  double _kindWeight(String kind) {
    return switch (kind) {
      'angle' => 1.15,
      'distance' => 1.10,
      _ => 1.0,
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
    this.cleaningDiagnostics = const [],
    this.sharedMovingFeatureIds = const [],
  });

  factory CustomPoseBuildResult.success(
    CustomPoseVerifierSpec spec, {
    required List<PoseFeatureSelectionDiagnostic> diagnostics,
    required CustomPoseConsistencyResult consistency,
    List<CleaningDiagnostics> cleaningDiagnostics = const [],
    List<String> sharedMovingFeatureIds = const [],
  }) {
    return CustomPoseBuildResult._(
      succeeded: true,
      spec: spec,
      failureReason: null,
      featureDiagnostics: List.unmodifiable(diagnostics),
      consistency: consistency,
      cleaningDiagnostics: List.unmodifiable(cleaningDiagnostics),
      sharedMovingFeatureIds: List.unmodifiable(sharedMovingFeatureIds),
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
  final List<CleaningDiagnostics> cleaningDiagnostics;
  final List<String> sharedMovingFeatureIds;

  List<PoseFeatureSelectionDiagnostic> get selectedFeatureDiagnostics =>
      featureDiagnostics
          .where((diagnostic) => diagnostic.selected)
          .toList(growable: false)
        ..sort((a, b) => b.amplitude.compareTo(a.amplitude));

  Map<String, dynamic> toDiagnosticsJson() => {
    'succeeded': succeeded,
    if (failureReason != null) 'failureReason': failureReason,
    'activeFeatures': selectedFeatureDiagnostics
        .map((diagnostic) => diagnostic.toJson())
        .toList(),
    'rejectedFeatures': featureDiagnostics
        .where((diagnostic) => !diagnostic.selected)
        .map((diagnostic) => diagnostic.toJson())
        .toList(),
    'activeFeatureCount': selectedFeatureDiagnostics.length,
    'requiredFeatureCount': spec?.requiredFeatureIds.length ?? 0,
    if (consistency != null) 'consistency': consistency!.toJson(),
    'cleaning': cleaningDiagnostics
        .asMap()
        .entries
        .map(
          (entry) => <String, dynamic>{
            'demonstrationIndex': entry.key + 1,
            ...entry.value.toJson(),
          },
        )
        .toList(),
    'sharedMovingFeatureIds': sharedMovingFeatureIds,
  };
}

class PoseFeatureSelectionDiagnostic {
  const PoseFeatureSelectionDiagnostic({
    required this.featureId,
    required this.coverage,
    required this.amplitude,
    required this.consistency,
    required this.selected,
    required this.rejectionReason,
    this.strongDemoCount = 0,
    this.moderateDemoCount = 0,
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
  final int strongDemoCount;
  final int moderateDemoCount;

  Map<String, dynamic> toJson() => {
    'featureId': featureId,
    'bodyPart': poseFeatureBodyPart(featureId),
    'coverage': _jsonDouble(coverage),
    'amplitude': _jsonDouble(amplitude),
    'consistency': _jsonDouble(consistency),
    'selected': selected,
    'strongDemoCount': strongDemoCount,
    'moderateDemoCount': moderateDemoCount,
    if (rejectionReason != null) 'rejectionReason': rejectionReason,
  };
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

  Map<String, dynamic> toJson() => {
    'pairwiseScores': pairwiseScores.map(
      (key, value) => MapEntry(key, _jsonDouble(value)),
    ),
    'overallScore': _jsonDouble(overallScore),
    'lowestPairScore': _jsonDouble(lowestPairScore),
    'accepted': accepted,
    if (failureReason != null) 'failureReason': failureReason,
  };
}

String poseFeatureBodyPart(String featureId) {
  if (_isFaceOrHeadFeature(featureId)) return 'face/head';
  if (featureId.contains('leftWrist')) return 'left wrist';
  if (featureId.contains('rightWrist')) return 'right wrist';
  if (featureId.contains('leftElbow')) return 'left elbow';
  if (featureId.contains('rightElbow')) return 'right elbow';
  if (_isHandFeature(featureId)) return 'hands';
  if (featureId.contains('Shoulder') || featureId.contains('shoulder')) {
    return 'shoulders';
  }
  if (featureId.contains('Hip') || featureId.contains('hip')) return 'hips';
  if (featureId.contains('Knee') || featureId.contains('knee')) return 'knees';
  if (featureId.contains('Ankle') || featureId.contains('ankle')) {
    return 'ankles';
  }
  return 'other';
}

bool _isArmDominant(List<_ActiveFeatureCandidate> candidates) {
  if (candidates.isEmpty) return false;
  final top = candidates.take(math.min(8, candidates.length)).toList();
  final armScore = top
      .where((candidate) => _isArmHandOrShoulderFeature(candidate.id))
      .fold<double>(0, (sum, candidate) => sum + candidate.score);
  final faceScore = top
      .where((candidate) => _isFaceOrHeadFeature(candidate.id))
      .fold<double>(0, (sum, candidate) => sum + candidate.score);
  return armScore > 0 && armScore >= faceScore;
}

bool _isArmHandOrShoulderFeature(String featureId) {
  return featureId.contains('Wrist') ||
      featureId.contains('wrist') ||
      featureId.contains('Elbow') ||
      featureId.contains('elbow') ||
      featureId.contains('Shoulder') ||
      featureId.contains('shoulder') ||
      _isHandFeature(featureId);
}

bool _isHandFeature(String featureId) {
  return featureId.contains('Pinky') ||
      featureId.contains('pinky') ||
      featureId.contains('Index') ||
      featureId.contains('index') ||
      featureId.contains('Thumb') ||
      featureId.contains('thumb') ||
      featureId.contains('hand_');
}

bool _isFaceOrHeadFeature(String featureId) {
  return featureId.contains('nose') ||
      featureId.contains('Eye') ||
      featureId.contains('eye') ||
      featureId.contains('Ear') ||
      featureId.contains('ear') ||
      featureId.contains('Mouth') ||
      featureId.contains('mouth');
}

double _jsonDouble(double value) {
  if (!value.isFinite) return 0;
  return double.parse(value.toStringAsFixed(4));
}

class _CleanedDemonstration {
  const _CleanedDemonstration({
    required this.index,
    required this.frames,
    required this.returnedToStart,
    required this.minimumStartSimilarity,
    required this.cleaningDiagnostics,
  });

  final int index;
  final List<PoseSequenceFrame> frames;
  final bool returnedToStart;
  final double minimumStartSimilarity;
  final CleaningDiagnostics cleaningDiagnostics;
}

class CleaningDiagnostics {
  const CleaningDiagnostics({
    required this.rawFrameCount,
    required this.cleanedFrameCount,
    required this.cleanStartIndex,
    required this.cleanEndIndex,
    required this.movingFeatureCount,
  });

  final int rawFrameCount;
  final int cleanedFrameCount;
  final int cleanStartIndex;
  final int cleanEndIndex;
  final int movingFeatureCount;

  Map<String, dynamic> toJson() => {
    'rawFrameCount': rawFrameCount,
    'cleanedFrameCount': cleanedFrameCount,
    'cleanStartIndex': cleanStartIndex,
    'cleanEndIndex': cleanEndIndex,
    'movingFeatureCount': movingFeatureCount,
  };
}

class _ActiveFeatureCandidate {
  const _ActiveFeatureCandidate({
    required this.id,
    required this.score,
    required this.amplitude,
    required this.consistency,
    required this.coverage,
  });

  final String id;
  final double score;
  final double amplitude;
  final double consistency;
  final double coverage;
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

class _MovementClip {
  const _MovementClip(this.start, this.end);

  final int start;
  final int end;
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
