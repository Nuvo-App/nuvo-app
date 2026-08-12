import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/ai/airborne_state_tracker.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/preset_motion/multi_phase_definitions.dart';

import 'replay_fixture.dart';

// ============================================================================
// PHASE 2: CANONICAL DETECTOR INTERFACE
// ============================================================================

abstract class MotionCandidate {
  String get id;
  String get family;
  String get architecture;
  void initialize(Map<String, dynamic> config);
  void processFrame(NuvoPoseFrame frame);
  CandidateResult finalize();
}

class CandidateResult {
  final int repCount;
  final List<RepEvent> repEvents;
  final List<FailureExplanation> failures;
  final Map<String, dynamic> diagnostics;
  final int framesProcessed;
  final Duration processingTime;

  CandidateResult({
    required this.repCount,
    this.repEvents = const [],
    this.failures = const [],
    this.diagnostics = const {},
    required this.framesProcessed,
    required this.processingTime,
  });
}

class RepEvent {
  final int frameIndex;
  final double confidence;
  RepEvent({required this.frameIndex, this.confidence = 1.0});
}

class FailureExplanation {
  final int repAttempt;
  final String concept;
  final String phase;
  final double confidence;
  FailureExplanation({
    required this.repAttempt,
    required this.concept,
    required this.phase,
    this.confidence = 0,
  });
}

// ============================================================================
// ADAPTER: Production Jump Squat
// ============================================================================

class ProductionJumpSquatAdapter extends MotionCandidate {
  @override
  final String id = 'production_jsq';
  @override
  final String family = 'deterministic';
  @override
  final String architecture = 'MultiPhaseSequenceValidator';

  late MultiPhaseSequenceValidator _validator;
  int _frames = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    _validator = MultiPhaseSequenceValidator(
      activity: config['activity'] as AiMotionActivity? ?? AiMotionActivity.jumpSquats,
      targetValue: config['target'] as int? ?? 100,
      definitions: (a) => [buildJumpSquatDefinition(a)],
      statusText: 'Jump Squats',
      coachingTextActive: 'Keep jumping!',
      coachingTextIncomplete: 'Get full body in frame',
    );
    _frames = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();
    _validator.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _validator.currentValue,
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

// ============================================================================
// ADAPTER: Concept V2 (extracted from concept_detector_v2_test.dart)
// ============================================================================

class ConceptV2Adapter extends MotionCandidate {
  @override
  final String id = 'concept_v2';
  @override
  final String family = 'deterministic';
  @override
  final String architecture = 'ConceptStateMachine';

  late double _flightThresholdRatio;
  late double _standingHkr;
  late double _squatHkr;
  late double _fastRiseThreshold;
  late double _airbornePeakRequired;
  ConceptDetector? _detector;
  int _frames = 0;
  final _sw = Stopwatch();

  @override
  void initialize(Map<String, dynamic> config) {
    _flightThresholdRatio = (config['flightThresholdRatio'] as num?)?.toDouble() ?? 0.20;
    _standingHkr = (config['standingHkr'] as num?)?.toDouble() ?? 0.60;
    _squatHkr = (config['squatHkr'] as num?)?.toDouble() ?? 0.58;
    _fastRiseThreshold = (config['fastRiseThreshold'] as num?)?.toDouble() ?? -0.012;
    _airbornePeakRequired = (config['airbornePeakRequired'] as num?)?.toDouble() ?? 0.15;
    _detector = ConceptDetector(
      flightThresholdRatio: _flightThresholdRatio,
      standingHkr: _standingHkr,
      squatHkr: _squatHkr,
      fastRiseThreshold: _fastRiseThreshold,
      airbornePeakRequired: _airbornePeakRequired,
    );
    _frames = 0;
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames == 0) _sw.start();
    _detector!.update(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    _sw.stop();
    return CandidateResult(
      repCount: _detector!.repCount,
      failures: _detector!.failures
          .map((f) => FailureExplanation(
                repAttempt: f.repNumber,
                concept: f.failedConcept,
                phase: f.failedPhase.name,
                confidence: f.failedConfidence,
              ))
          .toList(),
      framesProcessed: _frames,
      processingTime: _sw.elapsed,
    );
  }
}

// ============================================================================
// PHASE 3-4: CANONICAL EVALUATOR + METRICS
// ============================================================================

class ClipGroundTruth {
  final String clipId;
  final String movement;
  final int expectedReps;
  final String split;
  final String source;
  final String? uploader;
  final bool isTarget;
  final bool isConfuser;

  ClipGroundTruth({
    required this.clipId,
    required this.movement,
    required this.expectedReps,
    this.split = 'dev',
    this.source = 'real',
    this.uploader,
    this.isTarget = false,
    this.isConfuser = false,
  });
}

class ClipResult {
  final String clipId;
  final String candidateId;
  final int expectedReps;
  final int detectedReps;
  final bool isTarget;
  final bool isConfuser;
  final String movement;
  final List<FailureExplanation> failures;
  final Duration processingTime;
  final int framesProcessed;

  ClipResult({
    required this.clipId,
    required this.candidateId,
    required this.expectedReps,
    required this.detectedReps,
    required this.isTarget,
    required this.isConfuser,
    required this.movement,
    this.failures = const [],
    required this.processingTime,
    required this.framesProcessed,
  });

  bool get exactMatch => detectedReps == expectedReps;
  bool get isFalseAccept => isConfuser && detectedReps > 0;
  int get repError => (detectedReps - expectedReps).abs();

  /// True positives on this clip: matched reps (bounded by expected).
  int get tp => isTarget ? math.min(detectedReps, expectedReps) : 0;

  /// False negatives on this clip: expected reps not detected.
  int get fn => isTarget ? math.max(0, expectedReps - detectedReps) : 0;

  /// False positives on this clip: overcounted reps on target clips,
  /// or all detected reps on confuser clips.
  int get fp => isTarget
      ? math.max(0, detectedReps - expectedReps)
      : detectedReps;

  /// Whether this clip has catastrophic overcount (>3x expected).
  bool get isCatastrophic => isTarget && detectedReps > expectedReps * 3;
}

class AggregateMetrics {
  final String candidateId;
  final int totalTargetClips;
  final int totalConfuserClips;
  final int totalExpectedReps;
  final int totalDetectedReps;
  final int totalTP;
  final int totalFN;
  final int totalFP;
  final int totalFP_overcount;
  final int totalFP_confuser;
  final int exactCountClips;
  final int overcountClips;
  final int undercountClips;
  final int catastrophicClips;
  final int falseAcceptClips;
  final int totalFalseAcceptReps;
  final double repRecall;
  final double repPrecision;
  final double f1;
  final double countMAE;
  final double exactCountRate;
  final double overcountRate;
  final double undercountRate;
  final double falseAcceptClipRate;
  final double falseAcceptRate;
  final double productScore;
  final Duration avgProcessingTime;
  final Map<String, int> confuserFalseAccepts;
  final Map<String, double> confuserFalseAcceptClipRates;
  final List<ClipResult> clipResults;

  AggregateMetrics({
    required this.candidateId,
    required this.totalTargetClips,
    required this.totalConfuserClips,
    required this.totalExpectedReps,
    required this.totalDetectedReps,
    required this.totalTP,
    required this.totalFN,
    required this.totalFP,
    required this.totalFP_overcount,
    required this.totalFP_confuser,
    required this.exactCountClips,
    required this.overcountClips,
    required this.undercountClips,
    required this.catastrophicClips,
    required this.falseAcceptClips,
    required this.totalFalseAcceptReps,
    required this.repRecall,
    required this.repPrecision,
    required this.f1,
    required this.countMAE,
    required this.exactCountRate,
    required this.overcountRate,
    required this.undercountRate,
    required this.falseAcceptClipRate,
    required this.falseAcceptRate,
    required this.productScore,
    required this.avgProcessingTime,
    required this.confuserFalseAccepts,
    required this.confuserFalseAcceptClipRates,
    required this.clipResults,
  });

  /// Bounded recall: TP / (TP + FN) == TP / totalExpected. Always in [0, 1].
  ///
  /// COUNT-BASED: We only have per-clip rep counts, not per-rep timestamps.
  /// TP = sum of min(detected, expected) across target clips.
  /// This is an upper bound on event-level TP (real matching could be lower
  /// if detected reps don't temporally align with ground truth reps).
  /// See EVENT_MATCHING.md for the matching definition.

  /// Bounded precision: TP / (TP + FP). Always in [0, 1].
  /// FP = overcount on target clips + all detections on confuser clips.

  /// F1: harmonic mean of precision and recall.

  /// Product score: F1 * (1 - falseAcceptClipRate) * countQualityFactor.
  /// countQualityFactor = 1 - (countMAE / maxPossibleMAE).
  /// See PRODUCT_SCORE.md for the full formula.

  Map<String, dynamic> toJson() => {
    'candidateId': candidateId,
    'totalTargetClips': totalTargetClips,
    'totalConfuserClips': totalConfuserClips,
    'totalExpectedReps': totalExpectedReps,
    'totalDetectedReps': totalDetectedReps,
    'totalTP': totalTP,
    'totalFN': totalFN,
    'totalFP': totalFP,
    'totalFP_overcount': totalFP_overcount,
    'totalFP_confuser': totalFP_confuser,
    'exactCountClips': exactCountClips,
    'overcountClips': overcountClips,
    'undercountClips': undercountClips,
    'catastrophicClips': catastrophicClips,
    'falseAcceptClips': falseAcceptClips,
    'totalFalseAcceptReps': totalFalseAcceptReps,
    'repRecall': repRecall.toStringAsFixed(4),
    'repPrecision': repPrecision.toStringAsFixed(4),
    'f1': f1.toStringAsFixed(4),
    'countMAE': countMAE.toStringAsFixed(4),
    'exactCountRate': exactCountRate.toStringAsFixed(4),
    'overcountRate': overcountRate.toStringAsFixed(4),
    'undercountRate': undercountRate.toStringAsFixed(4),
    'falseAcceptClipRate': falseAcceptClipRate.toStringAsFixed(4),
    'falseAcceptRate': falseAcceptRate.toStringAsFixed(4),
    'productScore': productScore.toStringAsFixed(4),
    'avgProcessingMs': avgProcessingTime.inMilliseconds,
    'confuserFalseAccepts': confuserFalseAccepts,
    'confuserFalseAcceptClipRates': confuserFalseAcceptClipRates.map((k, v) => MapEntry(k, v.toStringAsFixed(3))),
  };
}

class CanonicalEvaluator {
  final String targetMovement;
  final List<String> confuserMovements;
  final List<ClipGroundTruth> groundTruths;
  final String fixtureDir;

  CanonicalEvaluator({
    required this.targetMovement,
    required this.confuserMovements,
    required this.groundTruths,
    required this.fixtureDir,
  });

  AggregateMetrics evaluate(MotionCandidate candidate) {
    final results = <ClipResult>[];
    for (final gt in groundTruths) {
      final clipResult = _evaluateClip(candidate, gt);
      results.add(clipResult);
    }
    return _aggregate(candidate.id, results);
  }

  ClipResult _evaluateClip(MotionCandidate candidate, ClipGroundTruth gt) {
    final fixturePath = '$fixtureDir/${gt.clipId}.json';
    final file = File(fixturePath);
    if (!file.existsSync()) {
      return ClipResult(
        clipId: gt.clipId,
        candidateId: candidate.id,
        expectedReps: gt.expectedReps,
        detectedReps: 0,
        isTarget: gt.isTarget,
        isConfuser: gt.isConfuser,
        movement: gt.movement,
        processingTime: Duration.zero,
        framesProcessed: 0,
      );
    }

    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final fixture = ReplayFixture.fromJson(json);
    final frames = fixture.frames.map((f) => f.toPoseFrame()).toList();

    candidate.initialize({
      'target': math.max(gt.expectedReps, 100),
    });

    for (final frame in frames) {
      candidate.processFrame(frame);
    }
    final result = candidate.finalize();

    return ClipResult(
      clipId: gt.clipId,
      candidateId: candidate.id,
      expectedReps: gt.expectedReps,
      detectedReps: result.repCount,
      isTarget: gt.isTarget,
      isConfuser: gt.isConfuser,
      movement: gt.movement,
      failures: result.failures,
      processingTime: result.processingTime,
      framesProcessed: result.framesProcessed,
    );
  }

  AggregateMetrics _aggregate(String candidateId, List<ClipResult> results) {
    final targetResults = results.where((r) => r.isTarget).toList();
    final confuserResults = results.where((r) => r.isConfuser).toList();

    final totalExpected = targetResults.fold(0, (s, r) => s + r.expectedReps);
    final totalDetected = targetResults.fold(0, (s, r) => s + r.detectedReps);

    // Bounded TP/FN/FP — count-based matching
    // TP = sum of min(detected, expected) per target clip
    // FN = sum of max(0, expected - detected) per target clip
    // FP_overcount = sum of max(0, detected - expected) per target clip
    // FP_confuser = sum of detected on confuser clips
    final totalTP = targetResults.fold(0, (s, r) => s + r.tp);
    final totalFN = targetResults.fold(0, (s, r) => s + r.fn);
    final fpOvercount = targetResults.fold(0, (s, r) => s + r.fp);
    final fpConfuser = confuserResults.fold(0, (s, r) => s + r.fp);
    final totalFP = fpOvercount + fpConfuser;

    final exact = targetResults.where((r) => r.exactMatch).length;
    final over = targetResults.where((r) => r.detectedReps > r.expectedReps).length;
    final under = targetResults.where((r) => r.detectedReps < r.expectedReps).length;
    final catastrophic = targetResults.where((r) => r.isCatastrophic).length;

    final falseAcceptClips = confuserResults.where((r) => r.detectedReps > 0).length;
    final totalFalseAcceptReps = confuserResults.fold(0, (s, r) => s + r.detectedReps);

    // Per-confuser-movement false accept tracking
    final confuserMap = <String, int>{};
    final confuserClipRates = <String, double>{};
    final confuserByMovement = <String, List<ClipResult>>{};
    for (final r in confuserResults) {
      confuserByMovement.putIfAbsent(r.movement, () => []).add(r);
      if (r.detectedReps > 0) {
        confuserMap[r.movement] = (confuserMap[r.movement] ?? 0) + r.detectedReps;
      }
    }
    for (final entry in confuserByMovement.entries) {
      final clips = entry.value;
      final faClips = clips.where((r) => r.detectedReps > 0).length;
      confuserClipRates[entry.key] = clips.isEmpty ? 0 : faClips / clips.length;
    }

    // Bounded recall: TP / (TP + FN) == TP / totalExpected. Always in [0, 1].
    final recall = (totalTP + totalFN) > 0 ? totalTP / (totalTP + totalFN) : 0.0;
    // Bounded precision: TP / (TP + FP). Always in [0, 1].
    final precision = (totalTP + totalFP) > 0 ? totalTP / (totalTP + totalFP) : 0.0;
    // F1: harmonic mean
    final f1 = (recall + precision) > 0
        ? 2 * recall * precision / (recall + precision)
        : 0.0;

    final mae = targetResults.isEmpty
        ? 0.0
        : targetResults.map((r) => r.repError).reduce((a, b) => a + b) /
            targetResults.length;

    // False accept clip rate: fraction of confuser clips that triggered any detection
    final faClipRate = confuserResults.isEmpty
        ? 0.0
        : falseAcceptClips / confuserResults.length;

    // Product score: F1 * (1 - falseAcceptClipRate) * countQualityFactor
    // countQualityFactor = 1 - (countMAE / maxPossibleMAE)
    // maxPossibleMAE = max expected reps in any single clip (conservative)
    final maxExpected = targetResults.isEmpty
        ? 1
        : targetResults.map((r) => r.expectedReps).reduce((a, b) => a > b ? a : b);
    final countQuality = (maxExpected > 0) ? (1.0 - (mae / maxExpected).clamp(0.0, 1.0)) : 0.0;
    final productScore = f1 * (1.0 - faClipRate) * countQuality;

    final avgTime = results.isEmpty
        ? Duration.zero
        : Duration(
            milliseconds: results
                .map((r) => r.processingTime.inMilliseconds)
                .reduce((a, b) => a + b) ~/
                results.length);

    return AggregateMetrics(
      candidateId: candidateId,
      totalTargetClips: targetResults.length,
      totalConfuserClips: confuserResults.length,
      totalExpectedReps: totalExpected,
      totalDetectedReps: totalDetected,
      totalTP: totalTP,
      totalFN: totalFN,
      totalFP: totalFP,
      totalFP_overcount: fpOvercount,
      totalFP_confuser: fpConfuser,
      exactCountClips: exact,
      overcountClips: over,
      undercountClips: under,
      catastrophicClips: catastrophic,
      falseAcceptClips: falseAcceptClips,
      totalFalseAcceptReps: totalFalseAcceptReps,
      repRecall: recall.clamp(0.0, 1.0),
      repPrecision: precision.clamp(0.0, 1.0),
      f1: f1.clamp(0.0, 1.0),
      countMAE: mae,
      exactCountRate: targetResults.isEmpty ? 0 : exact / targetResults.length,
      overcountRate: targetResults.isEmpty ? 0 : over / targetResults.length,
      undercountRate: targetResults.isEmpty ? 0 : under / targetResults.length,
      falseAcceptClipRate: faClipRate.clamp(0.0, 1.0),
      falseAcceptRate: confuserResults.isEmpty
          ? 0
          : falseAcceptClips / confuserResults.length,
      productScore: productScore.clamp(0.0, 1.0),
      avgProcessingTime: avgTime,
      confuserFalseAccepts: confuserMap,
      confuserFalseAcceptClipRates: confuserClipRates,
      clipResults: results,
    );
  }
}

// ============================================================================
// PHASE 5-6: DATASET VERSIONING + SPLITS
// ============================================================================

class DatasetManifest {
  final String version;
  final List<ClipEntry> clips;

  DatasetManifest({required this.version, required this.clips});

  Map<String, dynamic> toJson() => {
    'version': version,
    'clipCount': clips.length,
    'splits': {
      'train': clips.where((c) => c.split == 'train').length,
      'dev': clips.where((c) => c.split == 'dev').length,
      'validation': clips.where((c) => c.split == 'validation').length,
      'holdout': clips.where((c) => c.split == 'holdout').length,
    },
    'movements': _movementCounts(),
    'clips': clips.map((c) => c.toJson()).toList(),
  };

  Map<String, int> _movementCounts() {
    final m = <String, int>{};
    for (final c in clips) {
      m[c.movement] = (m[c.movement] ?? 0) + 1;
    }
    return m;
  }
}

class ClipEntry {
  final String clipId;
  final String movement;
  final int expectedReps;
  final String source;
  final String? uploader;
  final String split;
  final String labelConfidence;
  final bool isTarget;
  final bool isConfuser;
  final bool isHardNegative;

  ClipEntry({
    required this.clipId,
    required this.movement,
    required this.expectedReps,
    this.source = 'real',
    this.uploader,
    required this.split,
    this.labelConfidence = 'medium',
    this.isTarget = false,
    this.isConfuser = false,
    this.isHardNegative = false,
  });

  Map<String, dynamic> toJson() => {
    'clipId': clipId,
    'movement': movement,
    'expectedReps': expectedReps,
    'source': source,
    'uploader': uploader,
    'split': split,
    'labelConfidence': labelConfidence,
    'isTarget': isTarget,
    'isConfuser': isConfuser,
    'isHardNegative': isHardNegative,
  };
}

DatasetManifest buildDatasetManifest() {
  final clips = <ClipEntry>[];

  // Real jump squat clips — split by uploader to avoid person leakage
  // dev: 001, 003, 005 (PureGym, unknown, unknown)
  // validation: 002, 004 (FitnessBlender, Pro Fitness)
  // holdout: 006 (unknown)
  final jsqSplit = {
    'yt_jump_squat_001': 'dev',
    'yt_jump_squat_002': 'validation',
    'yt_jump_squat_003': 'dev',
    'yt_jump_squat_004': 'validation',
    'yt_jump_squat_005': 'dev',
    'yt_jump_squat_006': 'holdout',
  };
  final jsqReps = {
    'yt_jump_squat_001': 3, 'yt_jump_squat_002': 5, 'yt_jump_squat_003': 3,
    'yt_jump_squat_004': 3, 'yt_jump_squat_005': 10, 'yt_jump_squat_006': 5,
  };
  for (final entry in jsqSplit.entries) {
    clips.add(ClipEntry(
      clipId: entry.key,
      movement: 'jump_squats',
      expectedReps: jsqReps[entry.key]!,
      split: entry.value,
      isTarget: true,
      labelConfidence: 'medium',
    ));
  }

  // Confuser clips — split across dev/validation/holdout to prevent overfitting.
  // dev: used during search (largest set, includes hardest negatives)
  // validation: used for champion confirmation runs
  // holdout: NEVER queried by search — only for final champion evaluation
  final confusers = [
    ('yt_squat_001', 'normal_squats', 5, 'dev'),
    ('yt_squat_002', 'normal_squats', 3, 'dev'),
    ('yt_squat_003', 'normal_squats', 5, 'dev'),
    ('yt_squat_004', 'normal_squats', 5, 'validation'),
    ('yt_squat_005', 'normal_squats', 5, 'holdout'),
    ('yt_deep_squat_001', 'deep_squats', 3, 'dev'),
    ('yt_deep_squat_003', 'deep_squats', 3, 'holdout'),
    ('yt_vertical_jump_001', 'vertical_jumps', 3, 'dev'),
    ('yt_vertical_jump_002', 'vertical_jumps', 3, 'dev'),
    ('yt_vertical_jump_003', 'vertical_jumps', 3, 'validation'),
    ('yt_vertical_jump_004', 'vertical_jumps', 3, 'holdout'),
    ('yt_jumping_jack_003', 'jumping_jacks', 5, 'dev'),
    ('yt_jumping_jack_004', 'jumping_jacks', 8, 'validation'),
    ('yt_squat_jack_001', 'squat_jacks', 5, 'dev'),
    ('yt_squat_jack_002', 'squat_jacks', 5, 'holdout'),
    ('yt_lunge_001', 'lunges', 5, 'dev'),
    ('yt_lunge_002', 'lunges', 4, 'validation'),
    ('yt_lunge_003', 'lunges', 5, 'holdout'),
  ];
  for (final entry in confusers) {
    clips.add(ClipEntry(
      clipId: entry.$1,
      movement: entry.$2,
      expectedReps: entry.$3,
      split: entry.$4,
      isConfuser: true,
      isHardNegative: entry.$2 == 'deep_squats' || entry.$2 == 'jumping_jacks',
    ));
  }

  // Synthetic clips — train split
  final syntheticBase = [
    'jsq_clean_3', 'jsq_noisy_3', 'jsq_very_noisy_2', 'jsq_minimal_1',
    'squat_confuser_3', 'jump_confuser_3', 'jacks_confuser_3',
    'partial_confuser_3', 'ljs_clean_2', 'ljs_noisy_2',
  ];
  for (final id in syntheticBase) {
    final isTarget = id.startsWith('jsq_');
    clips.add(ClipEntry(
      clipId: id,
      movement: isTarget ? 'jump_squats' : 'confuser',
      expectedReps: isTarget ? (id.contains('clean_3') || id.contains('noisy_3') ? 3 : id.contains('minimal') ? 1 : 2) : 0,
      source: 'synthetic',
      split: 'train',
      isTarget: isTarget,
      isConfuser: !isTarget,
      labelConfidence: 'high',
    ));
  }

  return DatasetManifest(version: 'v1.0.0', clips: clips);
}

// ============================================================================
// PHASE 5: LEADERBOARD GATES
// ============================================================================

/// Candidate classification based on evaluation metrics.
/// Provisional thresholds:
///   REJECT: precision < 0.70 OR any catastrophic clips
///   RESEARCH: meaningful signal but below usable gate
///   PROMISING: recall >= 0.75 AND precision >= 0.90
///   PRODUCT_CANDIDATE: recall >= 0.90 AND precision >= 0.95 AND faClipRate <= 0.10
enum CandidateGate { reject, research, promising, productCandidate }

// ============================================================================
// PHASE 7: LEADERBOARD
// ============================================================================

class LeaderboardEntry {
  final String candidateId;
  final String family;
  final String architecture;
  final Map<String, dynamic> parameters;
  final String gitSha;
  final String datasetVersion;
  final DateTime timestamp;
  final AggregateMetrics? devMetrics;
  final AggregateMetrics? validationMetrics;
  final AggregateMetrics? holdoutMetrics;
  final String notes;

  LeaderboardEntry({
    required this.candidateId,
    required this.family,
    required this.architecture,
    required this.parameters,
    required this.gitSha,
    required this.datasetVersion,
    required this.timestamp,
    this.devMetrics,
    this.validationMetrics,
    this.holdoutMetrics,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
    'candidateId': candidateId,
    'family': family,
    'architecture': architecture,
    'parameters': parameters,
    'gitSha': gitSha,
    'datasetVersion': datasetVersion,
    'timestamp': timestamp.toIso8601String(),
    'devMetrics': devMetrics?.toJson(),
    'validationMetrics': validationMetrics?.toJson(),
    'holdoutMetrics': holdoutMetrics?.toJson(),
    'notes': notes,
  };

  double get bestRecall =>
      (holdoutMetrics?.repRecall ??
       validationMetrics?.repRecall ??
       devMetrics?.repRecall ??
       0);

  double get bestPrecision =>
      (holdoutMetrics?.repPrecision ??
       validationMetrics?.repPrecision ??
       devMetrics?.repPrecision ??
       0);

  double get bestF1 =>
      (holdoutMetrics?.f1 ??
       validationMetrics?.f1 ??
       devMetrics?.f1 ??
       0);

  double get bestProductScore =>
      (holdoutMetrics?.productScore ??
       validationMetrics?.productScore ??
       devMetrics?.productScore ??
       0);

  double get bestFalseAcceptClipRate =>
      (holdoutMetrics?.falseAcceptClipRate ??
       validationMetrics?.falseAcceptClipRate ??
       devMetrics?.falseAcceptClipRate ??
       1.0);

  double get bestExactCountRate =>
      (holdoutMetrics?.exactCountRate ??
       validationMetrics?.exactCountRate ??
       devMetrics?.exactCountRate ??
       0);

  int get bestCatastrophicClips =>
      (holdoutMetrics?.catastrophicClips ??
       validationMetrics?.catastrophicClips ??
       devMetrics?.catastrophicClips ??
       0);

  /// Composite score for ranking. Uses dev productScore as primary.
  /// Product score = F1 * (1 - falseAcceptClipRate) * countQualityFactor.
  /// This cannot be gamed by inflating recall alone.
  /// Dev split is used for ranking because it has the most clips and confusers.
  /// Val/holdout are too small for reliable ranking (1-2 clips).
  double get compositeScore => devMetrics?.productScore ?? 0;

  /// Gate classification based on dev split metrics.
  /// Provisional thresholds — see GATE_DEFINITIONS.md.
  CandidateGate get gate {
    final m = devMetrics;
    if (m == null) return CandidateGate.reject;

    if (m.repPrecision < 0.70 || m.catastrophicClips > 0) {
      return CandidateGate.reject;
    }
    if (m.repRecall >= 0.90 && m.repPrecision >= 0.95 && m.falseAcceptClipRate <= 0.10) {
      return CandidateGate.productCandidate;
    }
    if (m.repRecall >= 0.75 && m.repPrecision >= 0.90) {
      return CandidateGate.promising;
    }
    return CandidateGate.research;
  }

  String get gateLabel => gate.name.toUpperCase();
}

class Leaderboard {
  final List<LeaderboardEntry> entries = [];

  void register(LeaderboardEntry entry) {
    entries.removeWhere((e) => e.candidateId == entry.candidateId);
    entries.add(entry);
    entries.sort((a, b) => b.compositeScore.compareTo(a.compositeScore));
  }

  String toCsv() {
    final buf = StringBuffer();
    buf.writeln('rank,candidate_id,family,architecture,gate,dev_recall,dev_precision,dev_f1,dev_product_score,dev_exact,dev_false_accept_clips,dev_false_accept_clip_rate,dev_count_mae,dev_catastrophic,val_recall,val_precision,holdout_recall,holdout_precision,composite');
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      buf.writeln([
        i + 1, e.candidateId, e.family, e.architecture, e.gateLabel,
        (e.devMetrics?.repRecall ?? 0).toStringAsFixed(4),
        (e.devMetrics?.repPrecision ?? 0).toStringAsFixed(4),
        (e.devMetrics?.f1 ?? 0).toStringAsFixed(4),
        (e.devMetrics?.productScore ?? 0).toStringAsFixed(4),
        (e.devMetrics?.exactCountRate ?? 0).toStringAsFixed(4),
        e.devMetrics?.falseAcceptClips ?? 0,
        (e.devMetrics?.falseAcceptClipRate ?? 0).toStringAsFixed(4),
        (e.devMetrics?.countMAE ?? 0).toStringAsFixed(4),
        e.devMetrics?.catastrophicClips ?? 0,
        (e.validationMetrics?.repRecall ?? 0).toStringAsFixed(4),
        (e.validationMetrics?.repPrecision ?? 0).toStringAsFixed(4),
        (e.holdoutMetrics?.repRecall ?? 0).toStringAsFixed(4),
        (e.holdoutMetrics?.repPrecision ?? 0).toStringAsFixed(4),
        e.compositeScore.toStringAsFixed(4),
      ].join(','));
    }
    return buf.toString();
  }

  String toReport() {
    final buf = StringBuffer();
    buf.writeln('=== MOTION INTELLIGENCE LEADERBOARD ===');
    buf.writeln('${entries.length} candidates registered');
    buf.writeln('');
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      buf.writeln('${i + 1}. ${e.candidateId} (${e.family}/${e.architecture}) [${e.gateLabel}]');
      buf.writeln('   product_score: ${e.compositeScore.toStringAsFixed(4)}');
      if (e.devMetrics != null) {
        final m = e.devMetrics!;
        buf.writeln('   dev: recall=${m.repRecall.toStringAsFixed(4)} precision=${m.repPrecision.toStringAsFixed(4)} f1=${m.f1.toStringAsFixed(4)}');
        buf.writeln('        exact=${m.exactCountRate.toStringAsFixed(4)} mae=${m.countMAE.toStringAsFixed(2)} faClips=${m.falseAcceptClips}/${m.totalConfuserClips} faClipRate=${m.falseAcceptClipRate.toStringAsFixed(3)}');
        buf.writeln('        TP=${m.totalTP} FN=${m.totalFN} FP=${m.totalFP} (overcount=${m.totalFP_overcount} confuser=${m.totalFP_confuser}) catastrophic=${m.catastrophicClips}');
        if (m.confuserFalseAcceptClipRates.isNotEmpty) {
          final rates = m.confuserFalseAcceptClipRates.entries
              .map((e) => '${e.key}:${e.value.toStringAsFixed(2)}')
              .join(' ');
          buf.writeln('        confuser clip rates: $rates');
        }
      }
      if (e.validationMetrics != null) {
        buf.writeln('   val: recall=${e.validationMetrics!.repRecall.toStringAsFixed(4)} precision=${e.validationMetrics!.repPrecision.toStringAsFixed(4)} f1=${e.validationMetrics!.f1.toStringAsFixed(4)}');
      }
      if (e.holdoutMetrics != null) {
        buf.writeln('   holdout: recall=${e.holdoutMetrics!.repRecall.toStringAsFixed(4)} precision=${e.holdoutMetrics!.repPrecision.toStringAsFixed(4)} f1=${e.holdoutMetrics!.f1.toStringAsFixed(4)}');
      }
      if (e.notes.isNotEmpty) buf.writeln('   notes: ${e.notes}');
      buf.writeln('');
    }
    return buf.toString();
  }

  String toJsonString() => jsonEncode({
    'entries': entries.map((e) => e.toJson()).toList(),
  });
}

// ============================================================================
// PHASE 15-16: FAILURE MINING
// ============================================================================

class FailureMiner {
  static Map<String, int> mineFailureCategories(List<ClipResult> results) {
    final categories = <String, int>{};
    for (final r in results) {
      for (final f in r.failures) {
        categories[f.concept] = (categories[f.concept] ?? 0) + 1;
      }
    }
    final sorted = categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  static Map<String, int> mineConfuserClusters(List<ClipResult> results) {
    final clusters = <String, int>{};
    for (final r in results) {
      if (r.isFalseAccept) {
        clusters[r.movement] = (clusters[r.movement] ?? 0) + r.detectedReps;
      }
    }
    final sorted = clusters.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  static String generateReport(List<ClipResult> results) {
    final failures = mineFailureCategories(results);
    final confusers = mineConfuserClusters(results);
    final buf = StringBuffer();

    buf.writeln('=== FAILURE MINING REPORT ===');
    buf.writeln('');
    buf.writeln('TOP FAILURE CAUSES:');
    if (failures.isEmpty) {
      buf.writeln('  (no failures recorded)');
    } else {
      for (final e in failures.entries) {
        buf.writeln('  ${e.value}x ${e.key}');
      }
    }
    buf.writeln('');
    buf.writeln('CONFUSER FALSE ACCEPT CLUSTERS:');
    if (confusers.isEmpty) {
      buf.writeln('  (no false accepts)');
    } else {
      for (final e in confusers.entries) {
        buf.writeln('  ${e.value} reps from ${e.key}');
      }
    }
    return buf.toString();
  }
}

// ============================================================================
// INTERNAL: Minimal concept detector for V2 adapter
// ============================================================================

class ConceptDetector {
  final double flightThresholdRatio;
  final double standingHkr;
  final double squatHkr;
  final double fastRiseThreshold;
  final double airbornePeakRequired;

  ConceptDetector({
    required this.flightThresholdRatio,
    required this.standingHkr,
    required this.squatHkr,
    required this.fastRiseThreshold,
    required this.airbornePeakRequired,
  });

  final AirborneStateTracker airborne = AirborneStateTracker();
  int _repCount = 0;
  final List<V2Failure> failures = [];
  int attempt = 0;

  V2Phase phase = V2Phase.idle;
  int framesInPhase = 0;
  double peakFastRise = 0;

  double _prevHipY = 0;
  double _prevKneeY = 0;
  bool _hasPrev = false;

  int get repCount => _repCount;

  void update(NuvoPoseFrame frame) {
    airborne.update(frame);

    final ls = frame.point('leftShoulder');
    final rs = frame.point('rightShoulder');
    final lh = frame.point('leftHip');
    final rh = frame.point('rightHip');
    final lk = frame.point('leftKnee');
    final rk = frame.point('rightKnee');

    if (ls == null || rs == null || lh == null || rh == null ||
        lk == null || rk == null) return;

    final hipY = (lh.y + rh.y) / 2;
    final kneeY = (lk.y + rk.y) / 2;
    final shoulderY = (ls.y + rs.y) / 2;
    final torsoH = (hipY - shoulderY).abs().clamp(0.12, 0.6);
    final hkr = ((kneeY - hipY) / torsoH).clamp(-2.0, 3.0);

    double hipVel = 0;
    double kneeVel = 0;
    if (_hasPrev) {
      hipVel = hipY - _prevHipY;
      kneeVel = kneeY - _prevKneeY;
    }
    _prevHipY = hipY;
    _prevKneeY = kneeY;
    _hasPrev = true;

    final isDescending = hipVel > 0.005;
    final isAscending = hipVel < -0.005;
    final isFastRise = hipVel < fastRiseThreshold;
    final isDeepFlexion = hkr < 0.50;
    final isStanding = hkr > standingHkr;
    final isAirborne = airborne.isAirborne;

    if (isFastRise) peakFastRise = math.max(peakFastRise, -hipVel);

    framesInPhase++;

    switch (phase) {
      case V2Phase.idle:
        if (isDescending || isDeepFlexion) {
          attempt++;
          phase = V2Phase.compression;
          framesInPhase = 0;
          peakFastRise = 0;
        }
      case V2Phase.compression:
        if (isAscending || isFastRise || kneeVel < -0.004) {
          phase = V2Phase.ascent;
          framesInPhase = 0;
        } else if (framesInPhase > 30) {
          recordFailure('compression_timeout');
          phase = V2Phase.idle;
          framesInPhase = 0;
        }
      case V2Phase.ascent:
        if (isAirborne && peakFastRise > airbornePeakRequired * 0.01) {
          phase = V2Phase.airborne;
          framesInPhase = 0;
        } else if (framesInPhase > 8 && !airborne.isAirborne && airborne.flightCount == 0) {
          recordFailure('airborne_not_detected');
          phase = V2Phase.rearm;
          framesInPhase = 0;
        } else if (framesInPhase > 20) {
          recordFailure('ascent_timeout');
          phase = V2Phase.rearm;
          framesInPhase = 0;
        }
      case V2Phase.airborne:
        if (!airborne.isAirborne) {
          phase = V2Phase.landing;
          framesInPhase = 0;
        } else if (framesInPhase > 15) {
          recordFailure('airborne_too_long');
          phase = V2Phase.rearm;
          framesInPhase = 0;
        }
      case V2Phase.landing:
        _repCount++;
        phase = V2Phase.rearm;
        framesInPhase = 0;
      case V2Phase.rearm:
        if (isStanding && framesInPhase > 2) {
          phase = V2Phase.idle;
          framesInPhase = 0;
        } else if (framesInPhase > 20) {
          phase = V2Phase.idle;
          framesInPhase = 0;
        }
    }
  }

  void recordFailure(String concept) {
    failures.add(V2Failure(
      repNumber: attempt,
      failedConcept: concept,
      failedPhase: phase,
      failedConfidence: 0,
    ));
  }
}

enum V2Phase { idle, compression, ascent, airborne, landing, rearm }

class V2Failure {
  final int repNumber;
  final String failedConcept;
  final V2Phase failedPhase;
  final double failedConfidence;
  V2Failure({
    required this.repNumber,
    required this.failedConcept,
    required this.failedPhase,
    required this.failedConfidence,
  });
}
